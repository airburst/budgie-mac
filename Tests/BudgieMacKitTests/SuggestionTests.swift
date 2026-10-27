import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

private typealias Category = BudgieMacKit.Category

/// S-012, S-013, S-014.
@MainActor
@Suite("Suggestions and transfers")
struct SuggestionTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }
    let uk = Locale(identifier: "en_GB")

    @Test("Categories match on their full path, parents included")
    func categories() {
        let household = Category(name: "Household")
        let groceries = Category(name: "Groceries", parent: household)
        let gifts = Category(name: "Gifts")
        let gone = Category(name: "Grocery Old")
        gone.softDeleted = true
        let all = [household, groceries, gifts, gone]
        #expect(Suggestions.categories(all, matching: "gro").map(\.path) == ["Household > Groceries"])
        #expect(Suggestions.categories(all, matching: "house").map(\.path) == ["Household", "Household > Groceries"])
        #expect(Suggestions.category(named: "household > groceries", in: all) === groceries)
        #expect(Suggestions.category(named: "gifts", in: all) === gifts)
        #expect(Suggestions.category(named: "Grocery Old", in: all) == nil)
    }

    @Test("Payees match anywhere in the name")
    func payees() {
        let all = [Payee(name: "Corner Grocer"), Payee(name: "Big Supermarket"), Payee(name: "Grocer's Outlet")]
        #expect(Suggestions.payees(all, matching: "grocer").map(\.name) == ["Corner Grocer", "Grocer's Outlet"])
        #expect(Suggestions.payees(all, matching: " ").isEmpty)
    }

    @Test("With autofill on, a payee fills only the empty category and amount")
    func autofillOn() {
        let groceries = Category(name: "Groceries")
        let payee = Payee(name: "Corner Grocer", category: groceries, amount: Decimal(string: "-70.2"))
        var draft = TransactionDraft()
        draft.fill(from: payee, autofill: true, locale: uk)
        #expect(draft.payee == "Corner Grocer" && draft.category === groceries && draft.withdrawal == "70.20")

        let other = Category(name: "Gifts")
        var typed = TransactionDraft()
        typed.category = other
        typed.deposit = "5"
        typed.fill(from: payee, autofill: true, locale: uk)
        #expect(typed.category === other && typed.deposit == "5" && typed.withdrawal.isEmpty)
    }

    @Test("With autofill off, only the name fills in")
    func autofillOff() {
        let payee = Payee(name: "Corner Grocer", category: Category(name: "Groceries"), amount: -70)
        var draft = TransactionDraft()
        draft.fill(from: payee, autofill: false, locale: uk)
        #expect(draft.payee == "Corner Grocer" && draft.category == nil && draft.withdrawal.isEmpty)
    }

    @Test("A transfer creates two linked transactions with opposite amounts")
    func transfer() throws {
        let current = Account(name: "Everyday Current"), saver = Account(name: "Rainy Day Saver")
        [current, saver].forEach(context.insert)
        let transferParent = Category(name: "Transfer", kind: .transfer)
        let toSaver = Category(name: "Rainy Day Saver", kind: .transfer, parent: transferParent)
        let toCurrent = Category(name: "Everyday Current", kind: .transfer, parent: transferParent)
        [transferParent, toSaver, toCurrent].forEach(context.insert)
        var draft = TransactionDraft()
        draft.payee = "Savings"
        draft.withdrawal = "100"
        draft.transferAccount = saver
        let out = try draft.add(to: current, in: context, locale: uk)
        let into = try #require(Transfers.partner(of: out, in: context))
        #expect(out.amount == -100 && into.amount == 100 && into.account === saver)
        #expect(Transfers.partner(of: into, in: context) === out)
        #expect(out.category === toSaver && into.category === toCurrent)
        #expect(out.isTransfer && into.isTransfer)
        #expect(current.balance == -100 && saver.balance == 100)
        #expect(!Transaction(account: current, payee: "Shop", amount: -1).isTransfer)
    }
}
