import Foundation
import SwiftData

// S-005: an account's transactions with a running balance.

public enum TransactionStatus: String, Sendable {
    case uncleared, cleared, reconciled

    public var title: String {
        switch self {
        case .uncleared: "Uncleared"
        case .cleared: "Cleared"
        case .reconciled: "Reconciled"
        }
    }
}

public extension Transaction {
    var status: TransactionStatus {
        reconciled ? .reconciled : cleared ? .cleared : .uncleared
    }
}

public extension Category {
    /// "Household > Groceries".
    var path: String {
        parent.map { "\($0.name) > \(name)" } ?? name
    }
}

public struct RegisterRow: Identifiable {
    public let transaction: Transaction
    /// The account's balance after this transaction.
    public let balance: Decimal
    public var id: PersistentIdentifier { transaction.persistentModelID }
}

public enum Register {
    /// Oldest first; same-day transactions in the order they were added.
    public static let order = [SortDescriptor(\Transaction.date), SortDescriptor(\Transaction.createdAt)]

    /// The account's transactions, oldest first.
    public static func fetch(_ account: Account, in context: ModelContext) -> [Transaction] {
        let uuid = account.uuid
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.account?.uuid == uuid }, sortBy: order)
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Running balance on every row. `transactions` must be oldest first.
    public static func rows(_ transactions: [Transaction], openingBalance: Decimal) -> [RegisterRow] {
        var balance = openingBalance
        return transactions.map { transaction in
            balance += transaction.amount
            return RegisterRow(transaction: transaction, balance: balance)
        }
    }
}

// S-011: hide reconciled or cleared rows. Running balances are worked out on
// every row first, so hiding rows never changes the balances shown.
public extension Register {
    static func visible(_ rows: [RegisterRow], hideReconciled: Bool, hideCleared: Bool) -> [RegisterRow] {
        rows.filter { row in
            switch row.transaction.status {
            case .reconciled: !hideReconciled
            case .cleared: !hideCleared
            case .uncleared: true
            }
        }
    }

    /// "Hiding Reconciled", "Hiding Cleared", "Hiding Reconciled and Cleared", or nil.
    static func filterSummary(hideReconciled: Bool, hideCleared: Bool) -> String? {
        switch (hideReconciled, hideCleared) {
        case (true, true): "Hiding Reconciled and Cleared"
        case (true, false): "Hiding Reconciled"
        case (false, true): "Hiding Cleared"
        case (false, false): nil
        }
    }
}

public extension Preferences {
    /// The one Preferences row, made on first use.
    static func current(in context: ModelContext) -> Preferences {
        if let existing = try? context.fetch(FetchDescriptor<Preferences>()).first { return existing }
        let preferences = Preferences()
        context.insert(preferences)
        return preferences
    }
}
