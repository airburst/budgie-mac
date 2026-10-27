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
