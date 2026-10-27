import Foundation
import SwiftData

// S-012 and S-013: type-ahead for categories and payees.
public enum Suggestions {
    /// Categories whose "Parent > Child" path contains the text, in path order.
    /// Parents can be picked too, as in Budgie.
    public static func categories(_ categories: [Category], matching text: String) -> [Category] {
        let text = text.trimmingCharacters(in: .whitespaces)
        let live = categories.filter { !$0.softDeleted }
        let matches = text.isEmpty ? live : live.filter { $0.path.localizedStandardContains(text) }
        return matches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The category whose path or name is exactly the text, ignoring case.
    public static func category(named text: String, in categories: [Category]) -> Category? {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let live = categories.filter { !$0.softDeleted }
        return live.first { $0.path.caseInsensitiveCompare(text) == .orderedSame }
            ?? live.first { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    }

    /// Payees whose name contains the text, by name.
    public static func payees(_ payees: [Payee], matching text: String) -> [Payee] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return payees.filter { $0.name.localizedStandardContains(text) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func payee(named text: String, in payees: [Payee]) -> Payee? {
        let text = text.trimmingCharacters(in: .whitespaces)
        return payees.first { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    }
}

public extension TransactionDraft {
    /// S-013: picking a payee. With autofill on, its default category and
    /// amount fill in, but only fields that are still empty.
    mutating func fill(from payee: Payee, autofill: Bool, locale: Locale = .current) {
        self.payee = payee.name
        guard autofill else { return }
        if category == nil { category = payee.category }
        if withdrawal.isEmpty, deposit.isEmpty, let amount = payee.amount, amount != 0 {
            let text = abs(amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
            if amount < 0 { withdrawal = text } else { deposit = text }
        }
    }
}

public extension Transaction {
    /// Half of a transfer between two of your accounts, or filed under a
    /// Transfer category. Reports leave these out of spending and income.
    var isTransfer: Bool {
        transferUUID != nil || category?.kind == .transfer
    }
}
