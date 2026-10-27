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

/// S-008: deleting transactions, with everything needed to bring them back.
public enum TransactionDeletion {
    /// A deleted transaction, field for field, so Undo can recreate it.
    public struct Record: Sendable {
        let uuid: UUID
        let accountID: PersistentIdentifier?
        let categoryID: PersistentIdentifier?
        let date: Date
        let payee: String
        let amount: Decimal
        let notes: String?
        let cleared: Bool
        let reconciled: Bool
        let transferUUID: UUID?
        let createdAt: Date
        let updatedAt: Date?

        init(_ transaction: Transaction) {
            uuid = transaction.uuid
            accountID = transaction.account?.persistentModelID
            categoryID = transaction.category?.persistentModelID
            date = transaction.date
            payee = transaction.payee
            amount = transaction.amount
            notes = transaction.notes
            cleared = transaction.cleared
            reconciled = transaction.reconciled
            transferUUID = transaction.transferUUID
            createdAt = transaction.createdAt
            updatedAt = transaction.updatedAt
        }
    }

    /// The selection plus the other half of every transfer in it.
    public static func expand(_ transactions: [Transaction], in context: ModelContext) -> [Transaction] {
        var result = transactions
        var seen = Set(transactions.map(\.uuid))
        for transaction in transactions {
            if let partner = Transfers.partner(of: transaction, in: context), seen.insert(partner.uuid).inserted {
                result.append(partner)
            }
        }
        return result
    }

    /// Deletes the transactions and their transfer partners. Returns records for Undo.
    public static func delete(_ transactions: [Transaction], in context: ModelContext) -> [Record] {
        let all = expand(transactions, in: context)
        let records = all.map(Record.init)
        all.forEach(context.delete)
        return records
    }

    /// Recreates deleted transactions with their own ids, so transfer links hold.
    @discardableResult
    public static func restore(_ records: [Record], in context: ModelContext) -> [Transaction] {
        records.map { record in
            let transaction = Transaction(account: record.accountID.flatMap { context.model(for: $0) as? Account },
                                          date: record.date, payee: record.payee, amount: record.amount,
                                          category: record.categoryID.flatMap { context.model(for: $0) as? Category })
            transaction.uuid = record.uuid
            transaction.notes = record.notes
            transaction.cleared = record.cleared
            transaction.reconciled = record.reconciled
            transaction.transferUUID = record.transferUUID
            transaction.createdAt = record.createdAt
            transaction.updatedAt = record.updatedAt
            context.insert(transaction)
            return transaction
        }
    }
}
