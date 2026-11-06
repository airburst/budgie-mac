import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-061: import rules learned from your transactions fill in later imports.
@Suite("Import rules")
@MainActor
struct ImportRuleTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    private func day(_ text: String) -> Date { Day.parse(text)! }

    private func category(_ name: String) -> Category {
        let category = Category(name: name)
        context.insert(category)
        return category
    }

    @Test("A rule keeps its amounts as exact decimals")
    func amounts() {
        let rule = ImportRule(bankText: "NETFLIX", isDeposit: false, payee: "Netflix", category: nil)
        rule.amounts = [Decimal(string: "-12.99")!, Decimal(string: "-0.1")!]
        #expect(rule.amountsText == "-12.99 -0.1")
        #expect(rule.amounts == [Decimal(string: "-12.99")!, Decimal(string: "-0.1")!])
    }

    @Test("A rule for the amount wins over the usual meaning of the bank text")
    func ruleForAmount() {
        let household = category("Household"), books = category("Books")
        let book = ImportRuleBook(context: context)
        for _ in 0..<5 { book.learn(bankText: "AMZNMktplace*BB9G4", amount: -20, payee: "Amazon", category: household) }
        book.learn(bankText: "AMZNMktplace*XY911", amount: Decimal(string: "-5.99")!, payee: "Kindle", category: books)
        #expect(book.suggestion(for: "AMZNMktplace*Q1W2E", amount: Decimal(string: "-5.99")!)
            == .init(payee: "Kindle", category: books, source: .ruleForAmount, confirmations: 1))
        #expect(book.suggestion(for: "AMZNMktplace*Q1W2E", amount: -7)
            == .init(payee: "Amazon", category: household, source: .rule, confirmations: 5))
    }

    @Test("Bank text that means many things stays blank")
    func ambiguous() {
        let book = ImportRuleBook(context: context)
        for (payee, name) in [("Mark", "Transfer"), ("Fuel", "Fuel"), ("John Lewis", "Gifts"), ("Mark", "Transfer")] {
            book.learn(bankText: "M FAIRHURST", amount: -100, payee: payee, category: category(name))
        }
        #expect(book.suggestion(for: "M FAIRHURST", amount: -50) == nil)
    }

    @Test("Money in and money out are separate rules")
    func direction() {
        let salary = category("Salary"), transfer = category("Transfer")
        let book = ImportRuleBook(context: context)
        book.learn(bankText: "XBRIDGE LIMITED", amount: 5000, payee: "Mark", category: salary)
        book.learn(bankText: "XBRIDGE LIMITED", amount: -40, payee: "Mark", category: transfer)
        #expect(book.suggestion(for: "XBRIDGE LIMITED", amount: 5100)?.category === salary)
        #expect(book.suggestion(for: "XBRIDGE LIMITED", amount: -30)?.category === transfer)
    }

    @Test("A rule beats a payee with the same name: you file Wiltshire Council under Council Tax")
    func ruleBeforePayee() {
        let maintenance = category("Maintenance"), tax = category("Council Tax")
        context.insert(Payee(name: "Wiltshire Council", category: maintenance))
        let book = ImportRuleBook(context: context)
        book.learn(bankText: "WILTSHIRE COUNCIL", amount: -386, payee: "Council Tax", category: tax)
        #expect(book.suggestion(for: "WILTSHIRE COUNCIL", amount: -386)?.payee == "Council Tax")
    }

    @Test("With no rule: the payee's name, then a payee the text starts with, then a near one")
    func payeeLevels() {
        let groceries = category("Groceries"), fuel = category("Fuel"), bakery = category("Bakery")
        context.insert(Payee(name: "Vodafone"))
        context.insert(Payee(name: "Sainsburys", category: groceries))
        context.insert(Payee(name: "Bertinet", category: bakery))
        context.insert(Payee(name: "Mark"))
        context.insert(Payee(name: "Shop", category: groceries))
        // Your history files Sainsburys under Fuel more often than its default.
        for _ in 0..<2 { context.insert(Transaction(account: nil, payee: "Sainsburys", amount: -60, category: fuel)) }
        let book = ImportRuleBook(context: context)
        #expect(book.suggestion(for: "vodafone", amount: -10)?.source == .payeeName)
        #expect(book.suggestion(for: "SAINSBURYS PETROL", amount: -60) == .init(payee: "Sainsburys", category: fuel, source: .payeeWord, confirmations: 0))
        #expect(book.suggestion(for: "ZETTLE_*THE BERTIN", amount: -8)?.payee == "Bertinet")
        #expect(book.suggestion(for: "ZETTLE_*THE BERTIN", amount: -8)?.source == .nearPayee)
        #expect(book.suggestion(for: "MARKS&SPENCER PLC", amount: -5) == nil)
        #expect(book.suggestion(for: "OS MAPS SHOP", amount: -29) == nil)
    }

    @Test("Learning counts up one rule and keeps recent amounts first")
    func learning() throws {
        let book = ImportRuleBook(context: context)
        book.learn(bankText: "CO-OP GROUP 070590", amount: -12, payee: "Coop", category: nil, on: day("2026-11-01"))
        book.learn(bankText: "CO-OP GROUP 070123", amount: -9, payee: "Coop", category: nil, on: day("2026-11-04"))
        let rules = try context.fetch(FetchDescriptor<ImportRule>())
        #expect(rules.count == 1)
        #expect(rules.first?.bankText == "COOP")
        #expect(rules.first?.count == 2)
        #expect(rules.first?.amounts == [-9, -12])
        #expect(rules.first?.lastUsed == day("2026-11-04"))
        // A fresh book reads what was saved.
        #expect(ImportRuleBook(context: context).suggestion(for: "CO-OP GROUP 070590", amount: -3)?.confirmations == 2)
    }

    @Test("A duplicate teaches once: the transaction keeps the bank text")
    func learnsOnce() throws {
        let typed = Transaction(account: nil, date: day("2026-11-04"), payee: "Coop", amount: Decimal(string: "-12.05")!)
        context.insert(typed)
        let row = Qif.Row(date: day("2026-11-05"), payee: "CO-OP GROUP 070590", amount: Decimal(string: "-12.05")!)
        let book = ImportRuleBook(context: context)
        book.learn(from: row, matched: typed)
        book.learn(from: row, matched: typed)
        #expect(typed.bankText == "CO-OP GROUP 070590")
        #expect(try context.fetch(FetchDescriptor<ImportRule>()).first?.count == 1)
    }

    @Test("S-062: a file's duplicates teach its new rows, and the preview saves nothing")
    func preview() throws {
        let groceries = category("Groceries")
        let typed = Transaction(account: nil, date: day("2026-10-25"), payee: "Corner Grocer", amount: Decimal(string: "-81.02")!, category: groceries)
        context.insert(typed)
        try context.save()
        let rows = [
            Qif.Row(date: day("2026-10-25"), payee: "CORNER GROCER 0412", amount: Decimal(string: "-81.02")!),
            Qif.Row(date: day("2026-10-28"), payee: "CORNER GROCER 0413", amount: Decimal(string: "-23.40")!),
            Qif.Row(date: day("2026-10-29"), payee: "BIG SUPERMARKET 22", amount: -108),
        ]
        let matches = Qif.match(rows, existing: [typed], lastReconciled: nil)
        let previews = ImportRuleBook.preview(matches, in: container)
        #expect(previews[0] == nil) // the duplicate itself
        #expect(previews[1] == .init(payee: "Corner Grocer", categoryID: groceries.persistentModelID, source: .rule, confirmations: 1))
        #expect(previews[2] == nil)
        #expect(try context.fetch(FetchDescriptor<ImportRule>()).isEmpty)
        #expect(typed.bankText == nil)
    }

    @Test("S-062: your changes in the sheet count more than a learned match")
    func edits() {
        let household = category("Household"), fitness = category("Fitness")
        let book = ImportRuleBook(context: context)
        let row = Qif.Row(date: day("2026-10-01"), payee: "AMZNMktplace*BB9G4", amount: -20)
        book.learn(imported: row, payee: "Amazon", category: household, edited: false)
        book.learn(imported: row, payee: "Amazon", category: household, edited: false)
        book.learn(imported: row, payee: "Amazon", category: fitness, edited: true)
        #expect(book.suggestion(for: "AMZNMktplace*Q1W2E", amount: -7)?.category === fitness)
    }

    @Test("S-062: a row imported as its bank text with no category teaches nothing")
    func blankTeachesNothing() throws {
        let book = ImportRuleBook(context: context)
        let row = Qif.Row(date: day("2026-10-01"), payee: "BIG SUPERMARKET 22", amount: -108)
        book.learn(imported: row, payee: "BIG SUPERMARKET 22", category: nil, edited: false)
        #expect(try context.fetch(FetchDescriptor<ImportRule>()).isEmpty)
        book.learn(imported: row, payee: "Big Supermarket", category: nil, edited: true)
        #expect(try context.fetch(FetchDescriptor<ImportRule>()).first?.count == ImportRuleBook.editWeight)
    }
}

