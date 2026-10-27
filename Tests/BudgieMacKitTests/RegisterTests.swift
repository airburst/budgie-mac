import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit


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

/// S-009: marking as cleared.
@MainActor
@Suite("Clearing")
struct ClearingTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("The cleared balance changes by the row's amount")
    func clearedBalance() {
        let account = Account(name: "Bank", openingBalance: 10)
        context.insert(account)
        let shop = Transaction(account: account, payee: "Shop", amount: Decimal(string: "-70.20")!)
        context.insert(shop)
        #expect(account.clearedBalance == 10)
        Clearing.toggle([shop])
        #expect(shop.cleared && account.clearedBalance == Decimal(string: "-60.20")!)
        Clearing.toggle([shop])
        #expect(!shop.cleared && account.clearedBalance == 10)
    }

    @Test("A reconciled transaction cannot be uncleared")
    func reconciledStays() {
        let account = Account(name: "Bank")
        context.insert(account)
        let locked = Transaction(account: account, payee: "Locked", amount: 5)
        locked.cleared = true
        locked.reconciled = true
        context.insert(locked)
        #expect(Clearing.toggle([locked]).isEmpty)
        #expect(locked.cleared && locked.status == .reconciled)
    }

    @Test("A mixed selection is all marked as cleared")
    func mixed() {
        let account = Account(name: "Bank")
        context.insert(account)
        let a = Transaction(account: account, payee: "a", amount: 1)
        let b = Transaction(account: account, payee: "b", amount: 1)
        b.cleared = true
        [a, b].forEach(context.insert)
        #expect(Clearing.willClear([a, b]))
        #expect(Clearing.toggle([a, b]).map(\.payee) == ["a"])
        #expect(a.cleared && b.cleared)
        #expect(!Clearing.willClear([a, b]))
    }
}

/// S-011: the register filter.
@MainActor
@Suite("Register filter")
struct RegisterFilterTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("Hidden rows leave the running balance alone")
    func hiding() throws {
        let account = Account(name: "Bank")
        context.insert(account)
        for (index, status) in ["reconciled", "cleared", "uncleared"].enumerated() {
            let transaction = Transaction(account: account, date: Day.parse("2026-09-0\(index + 1)")!, payee: status, amount: 10)
            transaction.cleared = status != "uncleared"
            transaction.reconciled = status == "reconciled"
            context.insert(transaction)
        }
        try context.save()
        let rows = Register.rows(Register.fetch(account, in: context), openingBalance: 0)
        let shown = Register.visible(rows, hideReconciled: true, hideCleared: false)
        #expect(shown.map(\.transaction.payee) == ["cleared", "uncleared"])
        #expect(shown.map(\.balance) == [20, 30])
        #expect(Register.visible(rows, hideReconciled: true, hideCleared: true).map(\.transaction.payee) == ["uncleared"])
        #expect(Register.filterSummary(hideReconciled: true, hideCleared: false) == "Hiding Reconciled")
        #expect(Register.filterSummary(hideReconciled: false, hideCleared: false) == nil)
    }

    @Test("The filter is saved in preferences, one row for every register")
    func saved() throws {
        Preferences.current(in: context).hideReconciled = true
        try context.save()
        #expect(Preferences.current(in: context).hideReconciled)
        #expect(try context.fetchCount(FetchDescriptor<Preferences>()) == 1)
    }
}
