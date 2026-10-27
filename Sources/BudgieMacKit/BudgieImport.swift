import CryptoKit
import Foundation
import SwiftData

/// Reads a Budgie data file (Settings > Advanced > Export Data in Budgie,
/// `src/services/portable-data.ts`, format version 1) and replaces all data
/// in a store with it. All or nothing: on any error nothing changes.
public enum BudgieImport {
    public static let formatVersion = 1

    public enum Failure: Error, Equatable, LocalizedError {
        case notJSON
        case notBudgieData
        case unsupportedVersion(Int)
        case damaged
        case brokenLink(String)

        public var errorDescription: String? {
            switch self {
            case .notJSON, .notBudgieData:
                "This isn't a Budgie data file. In Budgie, choose Settings > Advanced > Export Data to make one."
            case .unsupportedVersion(let version) where version > BudgieImport.formatVersion:
                "This file was made by a newer Budgie (format \(version)). Update BudgieMac to import it."
            case .unsupportedVersion(let version):
                "This file uses Budgie data format \(version), which BudgieMac can't read."
            case .damaged:
                "The file has been changed or damaged since Budgie exported it."
            case .brokenLink(let what):
                "The file refers to \(what) that isn't in it."
            }
        }
    }

    /// What an import brought in, for the banner.
    public struct Summary: Equatable, Sendable {
        public var accounts = 0
        public var categories = 0
        public var transactions = 0
        public var reconciliations = 0
        public var scheduledTransactions = 0
        public var payees = 0
        public var envelopes = 0
        public var envelopeCategories = 0
        public var budgetAllocations = 0
        public var budgetTransfers = 0
    }

    /// Checks a file before anything is replaced, so the confirmation can name what it holds.
    public static func read(_ data: Data) throws(Failure) -> Package {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { throw .notJSON }
        guard let root = object as? [String: Any], let manifest = root["manifest"] as? [String: Any] else {
            throw .notBudgieData
        }
        guard let version = manifest["formatVersion"] as? Int else { throw .notBudgieData }
        guard version == formatVersion else { throw .unsupportedVersion(version) }
        guard let checksum = manifest["checksum"] as? String else { throw .notBudgieData }
        guard verify(data, checksum: checksum) else { throw .damaged }
        let package: Package
        do {
            package = try JSONDecoder().decode(Package.self, from: data)
        } catch {
            throw .notBudgieData
        }
        try package.checkLinks()
        return package
    }

    /// Budgie hashes `JSON.stringify` of the package with an empty checksum,
    /// and writes the file with the same `JSON.stringify`. So the file's own
    /// bytes, with the checksum blanked, are exactly what was hashed.
    static func verify(_ data: Data, checksum: String) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let blanked = text.replacingOccurrences(of: "\"checksum\":\"\(checksum)\"", with: "\"checksum\":\"\"")
        guard blanked != text || checksum.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(blanked.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() == checksum
    }

    /// Deletes everything in `context` and inserts the package. Saves once.
    @discardableResult
    public static func replaceAll(in context: ModelContext, with package: Package) throws -> Summary {
        do {
            try deleteEverything(in: context)
            let summary = insert(package, into: context)
            try context.save()
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    static func deleteEverything(in context: ModelContext) throws {
        try context.delete(model: BudgetTransfer.self)
        try context.delete(model: BudgetAllocation.self)
        try context.delete(model: EnvelopeCategory.self)
        try context.delete(model: Envelope.self)
        try context.delete(model: Payee.self)
        try context.delete(model: ScheduledTransaction.self)
        try context.delete(model: AccountReconciliation.self)
        try context.delete(model: Transaction.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.delete(model: Preferences.self)
    }

    // Rows with `deletedAt` are Budgie's sync tombstones: rows already removed
    // in Budgie. They are skipped, so counts match what Budgie shows.
    static func insert(_ package: Package, into context: ModelContext) -> Summary {
        var summary = Summary()

        var accounts: [String: Account] = [:]
        for row in package.accounts where row.deletedAt == nil {
            let account = Account(name: row.name, type: AccountType(rawValue: row.type) ?? .bank,
                                  openingBalance: money(row.balance), currency: row.currency)
            account.uuid = uuid(row.publicId)
            account.number = row.number
            account.notes = row.notes
            account.interestRate = row.interestRate.map(money)
            account.creditLimit = row.creditLimit.map(money)
            account.softDeleted = row.deleted
            account.pendingReconcileBalance = row.pendingReconcileBalance.map(money)
            account.pendingReconcileDate = row.pendingReconcileDate.flatMap(Day.parse)
            stamp(account, row, \.createdAt, \.updatedAt)
            context.insert(account)
            accounts[row.publicId] = account
        }
        summary.accounts = accounts.count

        var categories: [String: Category] = [:]
        let liveCategories = package.categories.filter { $0.deletedAt == nil }
        for row in liveCategories {
            let category = Category(name: row.name, kind: CategoryKind(rawValue: row.expenseType) ?? .expense)
            category.uuid = uuid(row.publicId)
            category.softDeleted = row.deleted
            stamp(category, row, \.createdAt, \.updatedAt)
            context.insert(category)
            categories[row.publicId] = category
        }
        for row in liveCategories {
            categories[row.publicId]?.parent = row.parentPublicId.flatMap { categories[$0] }
        }
        summary.categories = categories.count

        for row in package.transactions where row.deletedAt == nil {
            guard let account = accounts[row.accountPublicId] else { continue }
            let transaction = Transaction(account: account, date: Day.parse(row.date) ?? Day.today, payee: row.payee,
                                          amount: money(row.amount), category: row.categoryPublicId.flatMap { categories[$0] })
            transaction.uuid = uuid(row.publicId)
            transaction.notes = row.notes
            transaction.cleared = row.cleared
            transaction.reconciled = row.reconciled
            transaction.transferUUID = row.transferTransactionPublicId.map(uuid)
            stamp(transaction, row, \.createdAt, \.updatedAt)
            context.insert(transaction)
            summary.transactions += 1
        }

        for row in package.accountReconciliations where row.deletedAt == nil {
            guard let account = accounts[row.accountPublicId] else { continue }
            let reconciliation = AccountReconciliation(account: account, date: Day.parse(row.date) ?? Day.today, balance: money(row.balance))
            reconciliation.uuid = uuid(row.publicId)
            reconciliation.notes = row.notes
            stamp(reconciliation, row, \.createdAt, \.updatedAt)
            context.insert(reconciliation)
            summary.reconciliations += 1
        }

        for row in package.scheduledTransactions where row.deletedAt == nil {
            guard let account = accounts[row.accountPublicId] else { continue }
            let scheduled = ScheduledTransaction(account: account, payee: row.payee, amount: money(row.amount), rrule: row.rrule)
            scheduled.uuid = uuid(row.publicId)
            scheduled.category = row.categoryPublicId.flatMap { categories[$0] }
            scheduled.nextDueDate = row.nextDueDate.flatMap(Day.parse)
            scheduled.autoPost = row.autoPost
            scheduled.daysInAdvance = row.daysInAdvance
            scheduled.notes = row.notes
            scheduled.active = row.active
            scheduled.transferToAccount = row.transferToAccountPublicId.flatMap { accounts[$0] }
            stamp(scheduled, row, \.createdAt, \.updatedAt)
            context.insert(scheduled)
            summary.scheduledTransactions += 1
        }

        for row in package.payees where row.deletedAt == nil {
            let payee = Payee(name: row.name, category: row.categoryPublicId.flatMap { categories[$0] }, amount: row.amount.map(money))
            payee.uuid = uuid(row.publicId)
            stamp(payee, row, \.createdAt, \.updatedAt)
            context.insert(payee)
            summary.payees += 1
        }

        var envelopes: [String: Envelope] = [:]
        for row in package.envelopes where row.deletedAt == nil {
            let envelope = Envelope(name: row.name, sortOrder: row.sortOrder)
            envelope.uuid = uuid(row.publicId)
            envelope.active = row.active
            stamp(envelope, row, \.createdAt, \.updatedAt)
            context.insert(envelope)
            envelopes[row.publicId] = envelope
        }
        summary.envelopes = envelopes.count

        for row in package.envelopeCategories where row.deletedAt == nil {
            guard let envelope = envelopes[row.envelopePublicId], let category = categories[row.categoryPublicId] else { continue }
            let link = EnvelopeCategory(envelope: envelope, category: category)
            link.uuid = uuid(row.publicId)
            stamp(link, row, \.createdAt, \.updatedAt)
            context.insert(link)
            summary.envelopeCategories += 1
        }

        for row in package.budgetAllocations where row.deletedAt == nil {
            guard let envelope = envelopes[row.envelopePublicId] else { continue }
            let allocation = BudgetAllocation(envelope: envelope, month: row.month, assigned: money(row.assigned))
            allocation.uuid = uuid(row.publicId)
            stamp(allocation, row, \.createdAt, \.updatedAt)
            context.insert(allocation)
            summary.budgetAllocations += 1
        }

        for row in package.budgetTransfers where row.deletedAt == nil {
            guard let from = envelopes[row.fromEnvelopePublicId], let to = envelopes[row.toEnvelopePublicId] else { continue }
            let move = BudgetTransfer(from: from, to: to, month: row.month, amount: money(row.amount))
            move.uuid = uuid(row.publicId)
            move.notes = row.notes
            stamp(move, row, \.createdAt, \.updatedAt)
            context.insert(move)
            summary.budgetTransfers += 1
        }

        let preferences = Preferences()
        let source = package.preferences
        preferences.hideReconciled = source.hideReconciled ?? false
        preferences.hideCleared = source.hideCleared ?? false
        preferences.backupFolder = source.backupFolder
        preferences.backupRetentionDays = source.backupRetentionDays
        preferences.autofillPayees = source.autofillPayees ?? true
        preferences.theme = source.theme
        preferences.startupPage = source.startupPage
        preferences.accountShortcuts = (source.accountShortcuts ?? []).compactMap { shortcut in
            accounts[shortcut.accountPublicId].map { AccountShortcut(key: shortcut.key, ctrl: shortcut.ctrl ?? false, accountUUID: $0.uuid) }
        }
        context.insert(preferences)
        return summary
    }

    /// JSON numbers arrive as `Double`. Its shortest text form is what
    /// JavaScript wrote, so parsing that text gives the exact `Decimal`.
    static func money(_ value: Double) -> Decimal {
        Decimal(string: String(value)) ?? Decimal(value)
    }

    /// Budgie's public ids are UUIDs; anything else gets a stable UUID from its text.
    static func uuid(_ publicId: String) -> UUID {
        if let uuid = UUID(uuidString: publicId) { return uuid }
        var bytes = Array(SHA256.hash(data: Data(publicId.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func stamp<M, R: Synced>(_ model: M, _ row: R, _ created: ReferenceWritableKeyPath<M, Date>,
                                            _ updated: ReferenceWritableKeyPath<M, Date?>) {
        if let date = row.createdAt.flatMap(timestamp) { model[keyPath: created] = date }
        model[keyPath: updated] = row.updatedAt.flatMap(timestamp)
    }

    /// SQLite's "2026-10-27 12:34:56" (UTC) or ISO 8601.
    static func timestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        let iso = text.replacingOccurrences(of: " ", with: "T") + "Z"
        return try? Date(iso, strategy: .iso8601)
    }
}

// MARK: - The file format

protocol Synced {
    var publicId: String { get }
    var createdAt: String? { get }
    var updatedAt: String? { get }
    var deletedAt: String? { get }
}

extension BudgieImport {
    public struct Package: Decodable, Sendable {
        public struct Manifest: Decodable, Sendable {
            public var formatVersion: Int
            public var applicationVersion: String
            public var exportedAt: String
        }

        struct PortablePreferences: Decodable, Sendable {
            struct Shortcut: Decodable, Sendable {
                var key: String
                var ctrl: Bool?
                var accountPublicId: String
            }
            var hideReconciled: Bool?
            var hideCleared: Bool?
            var backupFolder: String?
            var backupRetentionDays: Int?
            var autofillPayees: Bool?
            var theme: String?
            var startupPage: String?
            var accountShortcuts: [Shortcut]?
        }

        struct AccountRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var name: String, number: String?, type: String, balance: Double, currency: String, notes: String?
            var interestRate: Double?, creditLimit: Double?, deleted: Bool
            var pendingReconcileBalance: Double?, pendingReconcileDate: String?
        }
        struct CategoryRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var parentPublicId: String?, name: String, expenseType: String, deleted: Bool
        }
        struct TransactionRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var accountPublicId: String, categoryPublicId: String?, date: String, payee: String, amount: Double
            var notes: String?, cleared: Bool, reconciled: Bool, transferTransactionPublicId: String?
        }
        struct ReconciliationRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var accountPublicId: String, date: String, balance: Double, notes: String?
        }
        struct ScheduledRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var accountPublicId: String, categoryPublicId: String?, payee: String, amount: Double, rrule: String
            var nextDueDate: String?, autoPost: Bool, daysInAdvance: Int?, notes: String?, active: Bool
            var transferToAccountPublicId: String?
        }
        struct PayeeRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var name: String, categoryPublicId: String?, amount: Double?
        }
        struct EnvelopeRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var name: String, active: Bool, sortOrder: Int
        }
        struct EnvelopeCategoryRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var envelopePublicId: String, categoryPublicId: String
        }
        struct AllocationRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var envelopePublicId: String, month: String, assigned: Double
        }
        struct BudgetTransferRow: Decodable, Synced, Sendable {
            var publicId: String, createdAt: String?, updatedAt: String?, deletedAt: String?
            var fromEnvelopePublicId: String, toEnvelopePublicId: String, month: String, amount: Double, notes: String?
        }

        public var manifest: Manifest
        var preferences: PortablePreferences
        var accounts: [AccountRow]
        var categories: [CategoryRow]
        var transactions: [TransactionRow]
        var accountReconciliations: [ReconciliationRow]
        var scheduledTransactions: [ScheduledRow]
        var payees: [PayeeRow]
        var envelopes: [EnvelopeRow]
        var envelopeCategories: [EnvelopeCategoryRow]
        var budgetAllocations: [AllocationRow]
        var budgetTransfers: [BudgetTransferRow]

        /// Live (not tombstoned) rows, for the confirmation and progress text.
        public var accountCount: Int { accounts.count { $0.deletedAt == nil } }
        public var transactionCount: Int { transactions.count { $0.deletedAt == nil } }

        /// The same checks as Budgie's `validatePortableData`.
        func checkLinks() throws(Failure) {
            let accountIds = Set(accounts.map(\.publicId))
            let categoryIds = Set(categories.map(\.publicId))
            let transactionIds = Set(transactions.map(\.publicId))
            let envelopeIds = Set(envelopes.map(\.publicId))
            func need(_ id: String?, in ids: Set<String>, _ what: String) throws(Failure) {
                if let id, !ids.contains(id) { throw .brokenLink(what) }
            }
            for row in categories { try need(row.parentPublicId, in: categoryIds, "a parent category") }
            for row in transactions {
                try need(row.accountPublicId, in: accountIds, "an account")
                try need(row.categoryPublicId, in: categoryIds, "a category")
                try need(row.transferTransactionPublicId, in: transactionIds, "a transfer")
            }
            for row in accountReconciliations { try need(row.accountPublicId, in: accountIds, "an account") }
            for row in scheduledTransactions {
                try need(row.accountPublicId, in: accountIds, "an account")
                try need(row.categoryPublicId, in: categoryIds, "a category")
                try need(row.transferToAccountPublicId, in: accountIds, "an account")
            }
            for row in payees { try need(row.categoryPublicId, in: categoryIds, "a category") }
            for row in envelopeCategories {
                try need(row.envelopePublicId, in: envelopeIds, "an envelope")
                try need(row.categoryPublicId, in: categoryIds, "a category")
            }
            for row in budgetAllocations { try need(row.envelopePublicId, in: envelopeIds, "an envelope") }
            for row in budgetTransfers {
                try need(row.fromEnvelopePublicId, in: envelopeIds, "an envelope")
                try need(row.toEnvelopePublicId, in: envelopeIds, "an envelope")
            }
            for shortcut in preferences.accountShortcuts ?? [] {
                try need(shortcut.accountPublicId, in: accountIds, "an account")
            }
        }
    }
}
