import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

private typealias Category = BudgieMacKit.Category

/// S-005: the register's order and running balance.
@MainActor
@Suite("Register")
struct RegisterTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("The running balance is right on every row, oldest first")
    func runningBalance() throws {
        let account = Account(name: "Bank", openingBalance: 100)
        let other = Account(name: "Other")
        context.insert(account)
        context.insert(other)
        let rows: [(String, String)] = [("2026-09-03", "-30.10"), ("2026-09-01", "50"), ("2026-09-02", "-0.90")]
        for (day, amount) in rows {
            context.insert(Transaction(account: account, date: Day.parse(day)!, payee: day, amount: Decimal(string: amount)!))
        }
        context.insert(Transaction(account: other, payee: "elsewhere", amount: 999))
        try context.save()

        let register = Register.rows(Register.fetch(account, in: context), openingBalance: account.openingBalance)
        #expect(register.map(\.transaction.payee) == ["2026-09-01", "2026-09-02", "2026-09-03"])
        #expect(register.map(\.balance) == [150, Decimal(string: "149.10")!, 119])
        #expect(register.last?.balance == account.balance)
    }

    @Test("Same-day transactions keep the order they were added")
    func sameDay() throws {
        let account = Account(name: "Bank")
        context.insert(account)
        let day = Day.parse("2026-09-01")!
        for (index, payee) in ["first", "second", "third"].enumerated() {
            let transaction = Transaction(account: account, date: day, payee: payee, amount: 1)
            transaction.createdAt = Date(timeIntervalSince1970: Double(index))
            context.insert(transaction)
        }
        try context.save()
        #expect(Register.fetch(account, in: context).map(\.payee) == ["first", "second", "third"])
    }

    @Test("Status and category path")
    func statusAndPath() {
        let transaction = Transaction(account: nil, payee: "x", amount: 1)
        #expect(transaction.status == .uncleared)
        transaction.cleared = true
        #expect(transaction.status == .cleared)
        transaction.reconciled = true
        #expect(transaction.status == .reconciled)
        let household = Category(name: "Household")
        #expect(Category(name: "Groceries", parent: household).path == "Household > Groceries")
        #expect(household.path == "Household")
    }
}
