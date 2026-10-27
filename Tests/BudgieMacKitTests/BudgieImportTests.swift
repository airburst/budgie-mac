import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit


/// S-002. The fixture was written by Budgie's own exporter
/// (`createPortableData` + `serializePortableData`), so its checksum is real.
@MainActor
@Suite("Budgie import")
struct BudgieImportTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    static let fixture: Data = {
        let url = Bundle.module.url(forResource: "budgie-export", withExtension: "json", subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }()

    private func all<T: PersistentModel>(_ type: T.Type) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    @Test("Imports the same row counts per table as the source")
    func counts() throws {
        let package = try BudgieImport.read(Self.fixture)
        let summary = try BudgieImport.replaceAll(in: context, with: package)
        // The source's live rows; Budgie's sync tombstones (deletedAt) are skipped.
        let expected = BudgieImport.Summary(accounts: 4, categories: 4, transactions: 6, reconciliations: 1,
                                            scheduledTransactions: 2, payees: 2, envelopes: 2, envelopeCategories: 1,
                                            budgetAllocations: 2, budgetTransfers: 1)
        #expect(summary == expected)
        #expect(try all(Account.self).count == 4)
        #expect(try all(Category.self).count == 4)
        #expect(try all(Transaction.self).count == 6)
        #expect(try all(AccountReconciliation.self).count == 1)
        #expect(try all(ScheduledTransaction.self).count == 2)
        #expect(try all(Payee.self).count == 2)
        #expect(try all(Envelope.self).count == 2)
        #expect(try all(EnvelopeCategory.self).count == 1)
        #expect(try all(BudgetAllocation.self).count == 2)
        #expect(try all(BudgetTransfer.self).count == 1)
        #expect(try all(Preferences.self).count == 1)
        #expect(try !all(Transaction.self).contains { $0.payee == "Removed in Budgie" })
    }

    @Test("Fields, amounts and dates come over exactly")
    func fields() throws {
        try BudgieImport.replaceAll(in: context, with: BudgieImport.read(Self.fixture))
        let accounts = try all(Account.self)
        let current = try #require(accounts.first { $0.name == "Everyday Current" })
        #expect(current.uuid == UUID(uuidString: "00000000-0000-4000-8000-000000000011"))
        #expect(current.openingBalance == Decimal(string: "1000.1")!)
        #expect(current.number == "12344321" && current.notes == "Main" && current.type == .bank)
        #expect(Day.string(current.createdAt) == "2026-01-02")
        let card = try #require(accounts.first { $0.name == "Credit Card" })
        #expect(card.type == .creditCard && card.creditLimit == 3_000 && card.interestRate == Decimal(string: "22.9"))
        #expect(card.openingBalance == Decimal(string: "-250.75")!)
        #expect(accounts.first { $0.name == "Rainy Day Saver" }?.currency == "EUR")
        #expect(accounts.first { $0.name == "Old Account" }?.softDeleted == true)

        let grocer = try #require(current.transactions.first { $0.payee == "Corner Grocer" })
        #expect(grocer.amount == Decimal(string: "-70.2")!)
        #expect(Day.string(grocer.date) == "2026-08-10")
        #expect(grocer.cleared && grocer.reconciled && grocer.notes == "Weekly shop")
        // 0.1 + 0.2 from JSON numbers is exactly 0.3.
        #expect(card.transactions.reduce(Decimal(0)) { $0 + $1.amount } == Decimal(string: "-0.3")!)

        let rent = try #require(try all(ScheduledTransaction.self).first { $0.payee == "Rent" })
        #expect(rent.rrule == "FREQ=MONTHLY;BYMONTHDAY=1" && rent.autoPost && rent.daysInAdvance == 3)
        #expect(rent.nextDueDate.map(Day.string) == "2026-11-01" && rent.category?.name == "Household")
        #expect(try all(ScheduledTransaction.self).first { $0.payee == "Savings" }?.transferToAccount?.name == "Rainy Day Saver")

        let food = try #require(try all(Envelope.self).first { $0.name == "Food" })
        #expect(food.categories.first?.category?.name == "Groceries")
        #expect(food.allocations.first?.assigned == Decimal(string: "300.5")!)
        #expect(try all(BudgetTransfer.self).first?.toEnvelope === food)

        let prefs = try #require(try all(Preferences.self).first)
        #expect(prefs.hideReconciled && prefs.theme == "dark" && prefs.backupRetentionDays == 30)
        #expect(prefs.accountShortcuts == [AccountShortcut(key: "1", ctrl: true, accountUUID: current.uuid)])
    }

    @Test("Transfer pairs keep their link, and categories keep their parents")
    func links() throws {
        try BudgieImport.replaceAll(in: context, with: BudgieImport.read(Self.fixture))
        let transactions = try all(Transaction.self)
        let out = try #require(transactions.first { $0.payee == "Transfer to Rainy Day Saver" })
        let into = try #require(transactions.first { $0.payee == "Transfer from Everyday Current" })
        #expect(out.transferUUID == into.uuid && into.transferUUID == out.uuid)
        #expect(into.account?.name == "Rainy Day Saver")
        let groceries = try #require(try all(Category.self).first { $0.name == "Groceries" })
        #expect(groceries.parent?.name == "Household")
        #expect(groceries.parent?.children.map(\.name) == ["Groceries"])
        #expect(try all(Category.self).first { $0.name == "Old Hobby" }?.softDeleted == true)
    }

    @Test("Importing replaces what was there")
    func replaces() throws {
        context.insert(Account(name: "Made in BudgieMac"))
        try context.save()
        try BudgieImport.replaceAll(in: context, with: BudgieImport.read(Self.fixture))
        #expect(try !all(Account.self).contains { $0.name == "Made in BudgieMac" })
        #expect(try all(Account.self).count == 4)
    }

    @Test("An unsupported format version is refused with a message naming the version")
    func newerVersion() throws {
        let text = String(decoding: Self.fixture, as: UTF8.self).replacingOccurrences(of: "\"formatVersion\":1", with: "\"formatVersion\":2")
        #expect(throws: BudgieImport.Failure.unsupportedVersion(2)) { try BudgieImport.read(Data(text.utf8)) }
        let message = BudgieImport.Failure.unsupportedVersion(2).errorDescription ?? ""
        #expect(message.contains("format 2"))
    }

    @Test("A changed file is refused")
    func damaged() throws {
        let text = String(decoding: Self.fixture, as: UTF8.self).replacingOccurrences(of: "\"amount\":-70.2", with: "\"amount\":-7.2")
        #expect(throws: BudgieImport.Failure.damaged) { try BudgieImport.read(Data(text.utf8)) }
    }

    @Test("Other files are refused")
    func notBudgie() {
        #expect(throws: BudgieImport.Failure.notJSON) { try BudgieImport.read(Data("hello".utf8)) }
        #expect(throws: BudgieImport.Failure.notBudgieData) { try BudgieImport.read(Data("{\"a\":1}".utf8)) }
    }
}
