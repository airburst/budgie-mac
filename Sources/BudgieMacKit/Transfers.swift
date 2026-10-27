import Foundation
import SwiftData

/// A transfer is two linked transactions in two accounts (`transferUUID`).
public enum Transfers {
    /// The other half of a transfer.
    public static func partner(of transaction: Transaction, in context: ModelContext) -> Transaction? {
        guard let uuid = transaction.transferUUID else { return nil }
        return try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.uuid == uuid })).first
    }

    /// S-007: after editing one half, the other half gets the same date and
    /// the opposite amount. Its payee, category and status stay its own.
    public static func syncPartner(of transaction: Transaction, in context: ModelContext) {
        guard let partner = partner(of: transaction, in: context) else { return }
        partner.date = transaction.date
        partner.amount = -transaction.amount
        partner.updatedAt = .now
    }
}

/// Every field a user can edit, to put a transaction back on Undo.
public struct TransactionValues: Sendable {
    public var date: Date
    public var payee: String
    public var amount: Decimal
    public var categoryID: PersistentIdentifier?
    public var notes: String?
    public var cleared: Bool

    public init(_ transaction: Transaction) {
        date = transaction.date
        payee = transaction.payee
        amount = transaction.amount
        categoryID = transaction.category?.persistentModelID
        notes = transaction.notes
        cleared = transaction.cleared
    }

    public func restore(_ transaction: Transaction, in context: ModelContext) {
        transaction.date = date
        transaction.payee = payee
        transaction.amount = amount
        transaction.category = categoryID.flatMap { context.model(for: $0) as? Category }
        transaction.notes = notes
        transaction.cleared = cleared
    }
}
