import Foundation
import SwiftData

// The data model, ported field for field from Budgie's `src/main/db/schema.ts`.
// Money is `Decimal`, never `Double`. Days without a time (transaction dates,
// due dates) are `Date` values at midnight UTC; see `Day`. Every model has a
// `uuid` that matches Budgie's `public_id` when imported, so links survive.
// New fields need a default value, so existing stores keep loading.

public enum AccountType: String, Codable, CaseIterable, Sendable {
    case bank, creditCard = "credit_card", loan, investment, cash
}

public enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case expense, income, transfer
}

@Model
public final class Account {
    public var uuid: UUID = UUID()
    public var name: String = ""
    public var number: String?
    public var typeRaw: String = AccountType.bank.rawValue
    /// Budgie's `balance` column: the balance before the first transaction.
    public var openingBalance: Decimal = 0
    public var currency: String = "GBP"
    public var notes: String?
    public var interestRate: Decimal?
    public var creditLimit: Decimal?
    /// Soft delete: hidden from lists, kept for history. Budgie's "closed".
    /// Not called `deleted`: that is Core Data's own key, and it reads back
    /// false after a save (docs/FIXLOG.md).
    @Attribute(originalName: "deleted") public var softDeleted: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date?
    public var pendingReconcileBalance: Decimal?
    public var pendingReconcileDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    public var transactions: [Transaction] = []
    @Relationship(deleteRule: .cascade, inverse: \AccountReconciliation.account)
    public var reconciliations: [AccountReconciliation] = []
    @Relationship(deleteRule: .cascade, inverse: \ScheduledTransaction.account)
    public var scheduledTransactions: [ScheduledTransaction] = []

    public var type: AccountType {
        get { AccountType(rawValue: typeRaw) ?? .bank }
        set { typeRaw = newValue.rawValue }
    }

    public init(name: String, type: AccountType = .bank, openingBalance: Decimal = 0, currency: String = "GBP") {
        self.name = name
        self.typeRaw = type.rawValue
        self.openingBalance = openingBalance
        self.currency = currency
    }
}

@Model
public final class Category {
    public var uuid: UUID = UUID()
    public var name: String = ""
    public var kindRaw: String = CategoryKind.expense.rawValue
    /// See Account.softDeleted for why this isn't called `deleted`.
    @Attribute(originalName: "deleted") public var softDeleted: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    /// Two levels: a parent has children, a child has no children of its own.
    public var parent: Category?
    @Relationship(deleteRule: .nullify, inverse: \Category.parent)
    public var children: [Category] = []
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    public var transactions: [Transaction] = []

    public var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    public init(name: String, kind: CategoryKind = .expense, parent: Category? = nil) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.parent = parent
    }
}

@Model
public final class Transaction {
    public var uuid: UUID = UUID()
    public var account: Account?
    public var category: Category?
    public var date: Date = Day.today
    public var payee: String = ""
    /// Signed: withdrawals are negative, deposits positive.
    public var amount: Decimal = 0
    public var notes: String?
    public var cleared: Bool = false
    public var reconciled: Bool = false
    /// The `uuid` of the other half of a transfer.
    public var transferUUID: UUID?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(account: Account?, date: Date = Day.today, payee: String, amount: Decimal, category: Category? = nil) {
        self.account = account
        self.date = date
        self.payee = payee
        self.amount = amount
        self.category = category
    }
}

@Model
public final class AccountReconciliation {
    public var uuid: UUID = UUID()
    public var account: Account?
    public var date: Date = Day.today
    public var balance: Decimal = 0
    public var notes: String?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(account: Account?, date: Date, balance: Decimal) {
        self.account = account
        self.date = date
        self.balance = balance
    }
}

@Model
public final class ScheduledTransaction {
    public var uuid: UUID = UUID()
    public var account: Account?
    public var category: Category?
    public var payee: String = ""
    public var amount: Decimal = 0
    /// RFC 5545 repeat rule, as Budgie stores it.
    public var rrule: String = ""
    public var nextDueDate: Date?
    public var autoPost: Bool = false
    public var daysInAdvance: Int?
    public var notes: String?
    public var active: Bool = true
    public var transferToAccount: Account?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(account: Account?, payee: String, amount: Decimal, rrule: String) {
        self.account = account
        self.payee = payee
        self.amount = amount
        self.rrule = rrule
    }
}

@Model
public final class Payee {
    public var uuid: UUID = UUID()
    @Attribute(.unique) public var name: String = ""
    public var category: Category?
    public var amount: Decimal?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(name: String, category: Category? = nil, amount: Decimal? = nil) {
        self.name = name
        self.category = category
        self.amount = amount
    }
}

@Model
public final class Envelope {
    public var uuid: UUID = UUID()
    public var name: String = ""
    public var active: Bool = true
    public var sortOrder: Int = 0
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \EnvelopeCategory.envelope)
    public var categories: [EnvelopeCategory] = []
    @Relationship(deleteRule: .cascade, inverse: \BudgetAllocation.envelope)
    public var allocations: [BudgetAllocation] = []

    public init(name: String, sortOrder: Int = 0) {
        self.name = name
        self.sortOrder = sortOrder
    }
}

/// Puts one category in one envelope. A category belongs to at most one envelope.
@Model
public final class EnvelopeCategory {
    public var uuid: UUID = UUID()
    public var envelope: Envelope?
    public var category: Category?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(envelope: Envelope?, category: Category?) {
        self.envelope = envelope
        self.category = category
    }
}

@Model
public final class BudgetAllocation {
    public var uuid: UUID = UUID()
    public var envelope: Envelope?
    /// "2026-10", as Budgie stores it.
    public var month: String = ""
    public var assigned: Decimal = 0
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(envelope: Envelope?, month: String, assigned: Decimal) {
        self.envelope = envelope
        self.month = month
        self.assigned = assigned
    }
}

@Model
public final class BudgetTransfer {
    public var uuid: UUID = UUID()
    public var fromEnvelope: Envelope?
    public var toEnvelope: Envelope?
    public var month: String = ""
    public var amount: Decimal = 0
    public var notes: String?
    public var createdAt: Date = Date.now
    public var updatedAt: Date?

    public init(from: Envelope?, to: Envelope?, month: String, amount: Decimal) {
        self.fromEnvelope = from
        self.toEnvelope = to
        self.month = month
        self.amount = amount
    }
}

public struct AccountShortcut: Codable, Hashable, Sendable {
    public var key: String
    public var ctrl: Bool
    public var accountUUID: UUID

    public init(key: String, ctrl: Bool = false, accountUUID: UUID) {
        self.key = key
        self.ctrl = ctrl
        self.accountUUID = accountUUID
    }
}

/// One row holds every preference, like Budgie's `settings` table.
@Model
public final class Preferences {
    public var hideReconciled: Bool = false
    public var hideCleared: Bool = false
    public var backupFolder: String?
    public var backupRetentionDays: Int?
    public var autofillPayees: Bool = true
    /// "light", "dark" or "auto".
    public var theme: String?
    public var startupPage: String?
    /// JSON, because arrays of structs are fragile in SwiftData stores.
    public var accountShortcutsData: Data?

    public var accountShortcuts: [AccountShortcut] {
        get { accountShortcutsData.flatMap { try? JSONDecoder().decode([AccountShortcut].self, from: $0) } ?? [] }
        set { accountShortcutsData = try? JSONEncoder().encode(newValue) }
    }

    /// The order people dragged accounts into, as JSON. Empty means by name.
    public var accountOrderData: Data?

    public var accountOrder: [UUID] {
        get { accountOrderData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? [] }
        set { accountOrderData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    public init() {}
}

public enum BudgieSchema {
    public static let models: [any PersistentModel.Type] = [
        Account.self, Category.self, Transaction.self, AccountReconciliation.self,
        ScheduledTransaction.self, Payee.self, Envelope.self, EnvelopeCategory.self,
        BudgetAllocation.self, BudgetTransfer.self, Preferences.self,
    ]

    public static func container(url: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(url: url))
    }

    public static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}

/// Calendar days stored as midnight UTC, so a date never shifts with the time zone.
public enum Day {
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static var today: Date { from(Date.now, in: .current) }

    /// The same calendar day as `date` in `timeZone`, at midnight UTC.
    public static func from(_ date: Date, in timeZone: TimeZone) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: parts)!
    }

    /// Parses Budgie's "2026-10-27" (a longer timestamp keeps its first 10 characters).
    public static func parse(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func string(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

// Lists hide soft-deleted rows.
public extension Account {
    static var openAccounts: FetchDescriptor<Account> {
        FetchDescriptor(predicate: #Predicate { !$0.softDeleted }, sortBy: [SortDescriptor(\.name)])
    }
}

public extension Category {
    static var visibleCategories: FetchDescriptor<Category> {
        FetchDescriptor(predicate: #Predicate { !$0.softDeleted }, sortBy: [SortDescriptor(\.name)])
    }
}

public extension Day {
    /// Shows a stored day in the user's locale. Always use this: formatting a
    /// day in the local time zone shows the day before west of Greenwich.
    static func formatted(_ date: Date, _ style: Date.FormatStyle.DateStyle = .numeric, locale: Locale = .current) -> String {
        date.formatted(Date.FormatStyle(date: style, time: .omitted, locale: locale, timeZone: calendar.timeZone))
    }
}
