import Foundation
import SwiftData

/// S-019: what the payee sheet edits. The default amount is signed, like a
/// transaction: "-70.20" is a withdrawal.
public struct PayeeDraft {
    public var name = ""
    public var category: Category?
    public var amount = ""

    public init() {}

    public init(_ payee: Payee, locale: Locale = .current) {
        name = payee.name
        category = payee.category
        amount = payee.amount.map { $0.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale)) } ?? ""
    }

    public var cleanName: String { name.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    public func isValid(locale: Locale = .current) -> Bool {
        !cleanName.isEmpty && (amount.isEmpty || Money.parse(amount, locale: locale) != nil)
    }

    var parsedAmount: Decimal? { amount.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Money.parse(amount) }
}

public enum PayeeEditing {
    /// Another payee already has this name (ignoring case): saving merges into it.
    public static func mergeTarget(for draft: PayeeDraft, editing: Payee?, in payees: [Payee]) -> Payee? {
        payees.first { $0 !== editing && $0.name.caseInsensitiveCompare(draft.cleanName) == .orderedSame }
    }

    /// Transactions still carrying a payee's name.
    public static func transactions(named name: String, in context: ModelContext) -> [Transaction] {
        (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.payee == name }))) ?? []
    }

    public static func add(_ draft: PayeeDraft, in context: ModelContext, locale: Locale = .current) -> Payee {
        let payee = Payee(name: draft.cleanName, category: draft.category, amount: draft.parsedAmount)
        context.insert(payee)
        return payee
    }

    /// Saves an edit. A new name can be written into past transactions too.
    /// Renaming to another payee's name merges: this payee goes, the other
    /// keeps its defaults (taking these where it has none). Returns the payee that remains.
    @discardableResult
    public static func save(_ draft: PayeeDraft, to payee: Payee, updatingTransactions: Bool, in context: ModelContext) -> Payee {
        let all = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
        let target = mergeTarget(for: draft, editing: payee, in: all)
        let oldName = payee.name
        // Merging takes the other payee's exact name.
        let newName = target?.name ?? draft.cleanName
        if updatingTransactions, oldName != newName {
            for transaction in transactions(named: oldName, in: context) { transaction.payee = newName }
        }
        // S-063: future imports use the new name.
        ImportRuleBook.renamePayee(oldName, to: newName, in: context)
        if let target {
            if target.category == nil { target.category = draft.category }
            if target.amount == nil { target.amount = draft.parsedAmount }
            target.updatedAt = .now
            context.delete(payee)
            return target
        }
        payee.name = newName
        payee.category = draft.category
        payee.amount = draft.parsedAmount
        payee.updatedAt = .now
        return payee
    }
}
