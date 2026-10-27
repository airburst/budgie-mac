import Foundation

/// S-009: Mark as Cleared / Mark as Uncleared.
public enum Clearing {
    /// The menu says "Mark as Cleared" when any selected row is uncleared.
    public static func willClear(_ transactions: [Transaction]) -> Bool {
        transactions.contains { !$0.cleared && !$0.reconciled }
    }

    /// Clears every row, or unclears every row, depending on `willClear`.
    /// Reconciled rows never change. Returns the rows that changed.
    @discardableResult
    public static func toggle(_ transactions: [Transaction]) -> [Transaction] {
        let clear = willClear(transactions)
        let changing = transactions.filter { !$0.reconciled && $0.cleared != clear }
        for transaction in changing {
            transaction.cleared = clear
            transaction.updatedAt = .now
        }
        return changing
    }
}
