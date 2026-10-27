import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

private typealias Category = BudgieMacKit.Category

/// S-001: every model round-trips through a store on disk with every field.
@MainActor
@Suite("Schema")
struct SchemaTests {
    let url = URL.temporaryDirectory.appending(path: "schema-\(UUID().uuidString).store")
    /// A context needs its container alive, so every opened container is kept.
    private final class Containers { var all: [ModelContainer] = [] }
    private let containers = Containers()

    /// Opens the store file again, as the app does on its next launch.
    private func reopen() throws -> ModelContext {
        let container = try BudgieSchema.container(url: url)
        containers.all.append(container)
        return container.mainContext
    }

    private func one<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> T {
        let rows = try context.fetch(FetchDescriptor<T>())
        #expect(rows.count == 1)
        return try #require(rows.first)
    }

    @Test("Every model round-trips with every field")
    func roundTrip() throws {
        let day = try #require(Day.parse("2026-08-10"))
        do {
            let context = try reopen()
            let parent = Category(name: "Household", kind: .expense)
            let groceries = Category(name: "Groceries", kind: .expense, parent: parent)
            let account = Account(name: "Everyday Current", type: .creditCard, openingBalance: Decimal(string: "1234.56")!, currency: "EUR")
            account.number = "12344321"
            account.notes = "Main"
            account.interestRate = Decimal(string: "19.9")
            account.creditLimit = 2_000
            account.pendingReconcileBalance = Decimal(string: "100.01")
            account.pendingReconcileDate = day
            let savings = Account(name: "Rainy Day Saver")
            let out = Transaction(account: account, date: day, payee: "Corner Grocer", amount: Decimal(string: "-70.20")!, category: groceries)
            out.notes = "Weekly shop"
            out.cleared = true
            out.reconciled = true
            let into = Transaction(account: savings, date: day, payee: "Transfer", amount: Decimal(string: "70.20")!)
            out.transferUUID = into.uuid
            into.transferUUID = out.uuid
            let reconciliation = AccountReconciliation(account: account, date: day, balance: Decimal(string: "5082.22")!)
            reconciliation.notes = "Statement"
            let scheduled = ScheduledTransaction(account: account, payee: "Rent", amount: -1_150, rrule: "FREQ=MONTHLY;BYMONTHDAY=1")
            scheduled.category = groceries
            scheduled.nextDueDate = day
            scheduled.autoPost = true
            scheduled.daysInAdvance = 3
            scheduled.notes = "Flat"
            scheduled.active = false
            scheduled.transferToAccount = savings
            let payee = Payee(name: "Corner Grocer", category: groceries, amount: Decimal(string: "-70.20"))
            let envelope = Envelope(name: "Food", sortOrder: 2)
            envelope.active = false
            let link = EnvelopeCategory(envelope: envelope, category: groceries)
            let bills = Envelope(name: "Bills")
            let allocation = BudgetAllocation(envelope: envelope, month: "2026-10", assigned: Decimal(string: "300.50")!)
            let move = BudgetTransfer(from: envelope, to: bills, month: "2026-10", amount: 25)
            move.notes = "Top up"
            let prefs = Preferences()
            prefs.hideReconciled = true
            prefs.hideCleared = true
            prefs.backupFolder = "/Backups"
            prefs.backupRetentionDays = 30
            prefs.autofillPayees = false
            prefs.theme = "dark"
            prefs.startupPage = "budget"
            prefs.accountShortcuts = [AccountShortcut(key: "1", ctrl: true, accountUUID: account.uuid)]
            for model in [parent, groceries, account, savings, out, into, reconciliation, scheduled, payee,
                          envelope, link, bills, allocation, move, prefs] as [any PersistentModel] {
                context.insert(model)
            }
            try context.save()
        }

        let context = try reopen()
        let accounts = try context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.name)]))
        let account = try #require(accounts.first { $0.name == "Everyday Current" })
        let savings = try #require(accounts.first { $0.name == "Rainy Day Saver" })
        #expect(account.type == .creditCard)
        #expect(account.number == "12344321")
        #expect(account.openingBalance == Decimal(string: "1234.56")!)
        #expect(account.currency == "EUR")
        #expect(account.notes == "Main")
        #expect(account.interestRate == Decimal(string: "19.9"))
        #expect(account.creditLimit == 2_000)
        #expect(account.pendingReconcileBalance == Decimal(string: "100.01"))
        #expect(account.pendingReconcileDate == day)
        #expect(savings.currency == "GBP")

        let out = try #require(account.transactions.first)
        #expect(out.date == day)
        #expect(out.payee == "Corner Grocer")
        #expect(out.amount == Decimal(string: "-70.20")!)
        #expect(out.notes == "Weekly shop")
        #expect(out.cleared && out.reconciled)
        #expect(out.category?.name == "Groceries")
        #expect(out.category?.parent?.name == "Household")
        let into = try #require(savings.transactions.first)
        #expect(out.transferUUID == into.uuid && into.transferUUID == out.uuid)

        let reconciliation = try one(AccountReconciliation.self, in: context)
        #expect(reconciliation.account === account)
        #expect(reconciliation.balance == Decimal(string: "5082.22")!)
        #expect(reconciliation.notes == "Statement")

        let scheduled = try one(ScheduledTransaction.self, in: context)
        #expect(scheduled.account === account)
        #expect(scheduled.category?.name == "Groceries")
        #expect(scheduled.amount == -1_150)
        #expect(scheduled.rrule == "FREQ=MONTHLY;BYMONTHDAY=1")
        #expect(scheduled.nextDueDate == day)
        #expect(scheduled.autoPost && scheduled.daysInAdvance == 3 && !scheduled.active)
        #expect(scheduled.notes == "Flat")
        #expect(scheduled.transferToAccount === savings)

        let payee = try one(Payee.self, in: context)
        #expect(payee.name == "Corner Grocer" && payee.category?.name == "Groceries")
        #expect(payee.amount == Decimal(string: "-70.20"))

        let envelopes = try context.fetch(FetchDescriptor<Envelope>())
        let food = try #require(envelopes.first { $0.name == "Food" })
        #expect(!food.active && food.sortOrder == 2)
        #expect(food.categories.first?.category?.name == "Groceries")
        #expect(food.allocations.first?.month == "2026-10")
        #expect(food.allocations.first?.assigned == Decimal(string: "300.50")!)

        let move = try one(BudgetTransfer.self, in: context)
        #expect(move.fromEnvelope === food && move.toEnvelope?.name == "Bills")
        #expect(move.amount == 25 && move.month == "2026-10" && move.notes == "Top up")

        let prefs = try one(Preferences.self, in: context)
        #expect(prefs.hideReconciled && prefs.hideCleared && !prefs.autofillPayees)
        #expect(prefs.backupFolder == "/Backups" && prefs.backupRetentionDays == 30)
        #expect(prefs.theme == "dark" && prefs.startupPage == "budget")
        #expect(prefs.accountShortcuts == [AccountShortcut(key: "1", ctrl: true, accountUUID: account.uuid)])
    }

    @Test("Decimal amounts are exact")
    func decimalsAreExact() throws {
        do {
            let context = try reopen()
            let account = Account(name: "Cash")
            context.insert(account)
            context.insert(Transaction(account: account, payee: "Sum", amount: Decimal(string: "0.1")! + Decimal(string: "0.2")!))
            try context.save()
        }
        let transaction = try one(Transaction.self, in: try reopen())
        #expect(transaction.amount == Decimal(string: "0.3")!)
    }

    @Test("Deleting an account or category hides it from lists")
    func softDelete() throws {
        let context = try reopen()
        let kept = Account(name: "Kept"), closed = Account(name: "Closed")
        let food = Category(name: "Food"), old = Category(name: "Old")
        [kept, closed].forEach { context.insert($0) }
        [food, old].forEach { context.insert($0) }
        closed.softDeleted = true
        old.softDeleted = true
        try context.save()

        let reopened = try reopen()
        #expect(try reopened.fetch(Account.openAccounts).map(\.name) == ["Kept"])
        #expect(try reopened.fetch(Category.visibleCategories).map(\.name) == ["Food"])
        #expect(try reopened.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(try reopened.fetchCount(FetchDescriptor<Category>()) == 2)
    }

    @Test("Days parse and print as Budgie stores them", arguments: ["2026-08-10", "2024-02-29"])
    func days(_ text: String) throws {
        #expect(Day.string(try #require(Day.parse(text))) == text)
        #expect(Day.string(try #require(Day.parse(text + "T12:34:56Z"))) == text)
    }
}

@Test("Days show as the same day in any time zone")
func dayFormatting() {
    let day = Day.parse("2026-09-22")!
    let uk = Locale(identifier: "en_GB")
    #expect(Day.formatted(day, locale: uk) == "22/09/2026")
    #expect(Day.formatted(day, .abbreviated, locale: uk) == "22 Sept 2026" || Day.formatted(day, .abbreviated, locale: uk) == "22 Sep 2026")
    // The bug this prevents: local-time formatting west of UTC gives the 21st.
    var pacific = Date.FormatStyle(date: .numeric, time: .omitted, locale: uk)
    pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    #expect(day.formatted(pacific) == "21/09/2026")
}

/// The soft-delete flag must read back after a save (it once clashed with Core Data's `deleted`).
@MainActor
@Test("Soft delete reads back after a save")
func softDeleteAfterSave() throws {
    let container = try BudgieSchema.container(url: URL.temporaryDirectory.appending(path: "soft-\(UUID()).store"))
    let context = container.mainContext
    let account = Account(name: "A")
    context.insert(account)
    try context.save()
    account.softDeleted = true
    try context.save()
    #expect(account.softDeleted)
}
