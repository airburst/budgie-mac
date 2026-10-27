import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// M6: reports.
@MainActor
@Suite("Reports")
struct ReportTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }
    private func day(_ text: String) -> Date { Day.parse(text)! }

    @Test("Spending: top five and Other, leaving out transfers and income, no roll-up")
    func spending() {
        let bank = Account(name: "Bank")
        context.insert(bank)
        let parent = Category(name: "Food")
        let names = ["Groceries", "Takeaway", "Fuel", "Gifts", "Books", "Music", "Films"]
        let categories = names.map { Category(name: $0, parent: $0 == "Groceries" ? parent : nil) }
        let salary = Category(name: "Salary", kind: .income), moves = Category(name: "Transfer", kind: .transfer)
        for (index, category) in categories.enumerated() {
            context.insert(Transaction(account: bank, payee: "x", amount: Decimal(-(70 - index * 10)), category: category))
        }
        context.insert(Transaction(account: bank, payee: "pay", amount: 2000, category: salary))
        context.insert(Transaction(account: bank, payee: "move", amount: -500, category: moves))
        let linked = Transaction(account: bank, payee: "linked", amount: -999, category: categories[0])
        linked.transferUUID = UUID()
        context.insert(linked)
        let slices = Reports.spending(bank.transactions)
        #expect(slices.map(\.name) == ["Groceries", "Takeaway", "Fuel", "Gifts", "Books", "Other"])
        #expect(slices.first?.amount == 70 && slices.last?.amount == 30)
    }

    @Test("Monthly totals leave out transfers")
    func months() {
        let bank = Account(name: "Bank")
        context.insert(bank)
        let salary = Category(name: "Salary", kind: .income), food = Category(name: "Food")
        context.insert(Transaction(account: bank, date: day("2026-09-25"), payee: "pay", amount: 2000, category: salary))
        context.insert(Transaction(account: bank, date: day("2026-09-26"), payee: "shop", amount: -300, category: food))
        let move = Transaction(account: bank, date: day("2026-10-01"), payee: "move", amount: -100, category: food)
        move.transferUUID = UUID()
        context.insert(move)
        context.insert(Transaction(account: bank, date: day("2026-10-02"), payee: "shop", amount: -50, category: food))
        let totals = Reports.incomeVsExpenses(bank.transactions)
        #expect(totals == [Reports.MonthTotals(month: "2026-09", income: 2000, expenses: 300),
                           Reports.MonthTotals(month: "2026-10", income: 0, expenses: 50)])
        #expect(totals.first?.difference == 1700)
    }

    @Test("Net worth is the balances at each month end, in one currency")
    func netWorth() {
        let bank = Account(name: "Bank", openingBalance: 100)
        let card = Account(name: "Card", type: .creditCard, openingBalance: -50)
        let euro = Account(name: "Euro", openingBalance: 1000, currency: "EUR")
        [bank, card, euro].forEach(context.insert)
        context.insert(Transaction(account: bank, date: day("2026-09-10"), payee: "a", amount: 20))
        context.insert(Transaction(account: card, date: day("2026-10-05"), payee: "b", amount: -30))
        let points = Reports.netWorth(accounts: [bank, card, euro], range: day("2026-09-01")...day("2026-10-27"), currency: "GBP")
        #expect(points == [Reports.NetWorthPoint(month: "2026-09", netWorth: 70), Reports.NetWorthPoint(month: "2026-10", netWorth: 40)])
    }

    @Test("Figures are per currency; saving rate is surplus over income, or none")
    func figures() {
        let bank = Account(name: "Bank", openingBalance: 100), loan = Account(name: "Loan", type: .loan, openingBalance: -900)
        let euro = Account(name: "Euro", openingBalance: 50, currency: "EUR")
        [bank, loan, euro].forEach(context.insert)
        context.insert(Transaction(account: bank, date: day("2026-11-20"), payee: "Later", amount: -1799))
        let months = [Reports.MonthTotals(month: "2026-09", income: 2000, expenses: 1500),
                      Reports.MonthTotals(month: "2026-10", income: 0, expenses: 200)]
        let figures = Reports.figures(accounts: [bank, loan, euro], months: months, today: day("2026-10-27"))
        #expect(figures.assets == ["GBP": 100, "EUR": 50] && figures.debt == ["GBP": 900])
        #expect(figures.surplus == 500 && figures.savingRate == 0.25)
        let none = Reports.figures(accounts: [], months: [Reports.MonthTotals(month: "2026-09")], today: day("2026-10-27"))
        #expect(none.savingRate == nil)
    }

    @Test("Period presets")
    func periods() {
        let today = day("2026-10-27")
        #expect(Day.string(Reports.Period.last30.range(today: today).lowerBound) == "2026-09-27")
        #expect(Day.string(Reports.Period.last90.range(today: today).lowerBound) == "2026-07-29", "Budgie: 90 days before today")
        #expect(Day.string(Reports.Period.lastMonth.range(today: today).lowerBound) == "2026-09-01")
        #expect(Day.string(Reports.Period.lastMonth.range(today: today).upperBound) == "2026-09-30")
        #expect(Day.string(Reports.Period.thisYear.range(today: today).lowerBound) == "2026-01-01")
    }
}
