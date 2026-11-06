import Foundation
import SwiftData

/// S-061: fills in the payee and category of an imported QIF row from what
/// you chose before, and learns from each import. Load once per import.
public final class ImportRuleBook {
    public enum Source: Equatable, Sendable {
        /// A rule for this bank text and this amount (Netflix £12.99 by PayPal).
        case ruleForAmount
        /// A rule for this bank text and direction, when most of what it learned agrees.
        case rule
        /// The bank text is a payee's name.
        case payeeName
        /// The cleaned bank text starts with a payee's name ("SAINSBURYS PETROL").
        case payeeWord
        /// The cleaned bank text is close to a payee's name ("BERTIN", "Bertinet").
        case nearPayee
    }

    public struct Suggestion: Equatable {
        public var payee: String
        public var category: Category?
        public var source: Source
        /// How many times you confirmed the rule; 0 for the payee levels.
        public var confirmations: Int
    }

    /// A rule only fills in when at least this share of what it learned agrees.
    public static let agreement = 0.6
    /// Amounts kept per rule.
    static let amountsKept = 24

    private let context: ModelContext
    private var rules: [String: [ImportRule]]
    private let payees: [Payee]
    private let usual: [String: Category]

    public init(context: ModelContext) {
        self.context = context
        let all = (try? context.fetch(FetchDescriptor<ImportRule>())) ?? []
        rules = Dictionary(grouping: all, by: \.bankText)
        payees = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        usual = Self.usualCategories((try? context.fetch(FetchDescriptor<Transaction>())) ?? [])
    }

    /// The words of the bank text that say who it was, as a rule stores them.
    public static func key(_ bankText: String) -> String {
        let words = Qif.cleaned(bankText)
        return words.isEmpty ? bankText.uppercased().trimmingCharacters(in: .whitespaces) : words.joined(separator: " ")
    }

    /// The category each payee is most often filed under, ties to the latest.
    static func usualCategories(_ transactions: [Transaction]) -> [String: Category] {
        var counts: [String: [PersistentIdentifier: (category: Category, count: Int, latest: Date)]] = [:]
        for transaction in transactions {
            guard let category = transaction.category, !category.softDeleted else { continue }
            let key = transaction.payee.lowercased()
            var entry = counts[key, default: [:]][category.persistentModelID] ?? (category, 0, .distantPast)
            entry.count += 1
            entry.latest = max(entry.latest, transaction.date)
            counts[key, default: [:]][category.persistentModelID] = entry
        }
        return counts.compactMapValues { $0.values.max { ($0.count, $0.latest) < ($1.count, $1.latest) }?.category }
    }

    // MARK: Suggest

    public func suggestion(for bankText: String, amount: Decimal) -> Suggestion? {
        let key = Self.key(bankText)
        let candidates = (rules[key] ?? []).filter { $0.isDeposit == (amount > 0) && $0.count > 0 }
        if let rule = candidates.filter({ $0.amounts.contains(amount) }).max(by: Self.weaker) {
            return Suggestion(payee: rule.payee, category: rule.category, source: .ruleForAmount, confirmations: rule.count)
        }
        if let rule = candidates.max(by: Self.weaker) {
            let total = candidates.reduce(0) { $0 + $1.count }
            if Double(rule.count) / Double(total) >= Self.agreement {
                return Suggestion(payee: rule.payee, category: rule.category, source: .rule, confirmations: rule.count)
            }
            return nil // the bank text means different things (a person's name); leave it to you
        }
        if let payee = payeeMatch(bankText) {
            return Suggestion(payee: payee.payee.name, category: usual[payee.payee.name.lowercased()] ?? payee.payee.category, source: payee.source, confirmations: 0)
        }
        return nil
    }

    private static func weaker(_ a: ImportRule, _ b: ImportRule) -> Bool {
        (a.count, a.lastUsed) < (b.count, b.lastUsed)
    }

    private func payeeMatch(_ bankText: String) -> (payee: Payee, source: Source)? {
        let text = bankText.trimmingCharacters(in: .whitespaces)
        if let payee = payees.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
            return (payee, .payeeName)
        }
        let words = Qif.cleaned(bankText)
        guard !words.isEmpty else { return nil }
        // The longest payee the cleaned text starts with: "SAINSBURYS PETROL" -> Sainsburys.
        let starts = Set(words.indices.map { words[...$0].joined() })
        let keyed = payees.map { (payee: $0, key: Qif.squashed($0.name)) }.filter { $0.key.count >= 3 }
        if let hit = keyed.filter({ starts.contains($0.key) }).max(by: { $0.key.count < $1.key.count }) {
            return (hit.payee, .payeeWord)
        }
        // Bank text is cut at 18 characters: a long word can be the start of a payee.
        let joined = words.joined()
        let near = keyed.filter { $0.key.count >= 4 }.map { candidate -> (Payee, Double) in
            let truncated = words.contains { $0.count >= 5 && candidate.key.hasPrefix($0) }
            return (candidate.payee, truncated ? 0.9 : Self.similarity(joined, candidate.key))
        }
        if let best = near.max(by: { $0.1 < $1.1 }), best.1 >= 0.8 {
            return (best.0, .nearPayee)
        }
        return nil
    }

    /// 1 for the same text, 0 for nothing in common (edit distance).
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }

    // MARK: Learn

    /// Records that this bank text and amount meant this payee and category.
    public func learn(bankText: String, amount: Decimal, payee: String, category: Category?, weight: Int = 1, on date: Date = .now) {
        let key = Self.key(bankText)
        let payee = payee.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !payee.isEmpty, weight > 0 else { return }
        let isDeposit = amount > 0
        let rule: ImportRule
        if let existing = rules[key]?.first(where: { $0.isDeposit == isDeposit && $0.payee == payee && $0.category?.persistentModelID == category?.persistentModelID }) {
            rule = existing
        } else {
            rule = ImportRule(bankText: key, isDeposit: isDeposit, payee: payee, category: category)
            rule.lastUsed = date
            context.insert(rule)
            rules[key, default: []].append(rule)
        }
        rule.count += weight
        rule.lastUsed = max(rule.lastUsed, date)
        rule.amounts = Array(([amount] + rule.amounts.filter { $0 != amount }).prefix(Self.amountsKept))
    }

    /// Learns from a transaction a QIF row matched as a duplicate, once:
    /// the transaction keeps the bank text, so the same file again adds nothing.
    public func learn(from row: Qif.Row, matched transaction: Transaction) {
        guard transaction.bankText == nil else { return }
        transaction.bankText = row.payee
        learn(bankText: row.payee, amount: row.amount, payee: transaction.payee, category: transaction.category, on: row.date)
    }
}
