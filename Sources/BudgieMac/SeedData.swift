import BudgieMacKit
import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic accounts and transactions (short and long names,
/// positive and negative balances, two currencies, one closed account).
/// Seed only what a person can create in the app, or the snapshots show
/// features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) == 0 else { return }
        insert(into: context)
        try? context.save()
    }

    private static func money(_ text: String) -> Decimal { Decimal(string: text)! }

    /// Days before 27 Oct 2026, the "today" of the reference screenshots.
    private static func day(_ daysAgo: Int) -> Date {
        Day.calendar.date(byAdding: .day, value: -daysAgo, to: Day.parse("2026-10-27")!)!
    }

    static func insert(into context: ModelContext) {
        // Budgie's default tree, as a new user gets, plus a few of the user's own.
        DefaultCategories.seedIfEmpty(context)
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        func category(_ name: String, kind: CategoryKind = .expense, parent: Category? = nil) -> Category {
            if let found = existing.first(where: { $0.name == name && $0.parent === parent }) { return found }
            let made = Category(name: name, kind: kind, parent: parent)
            context.insert(made)
            return made
        }
        let household = category("Household")
        let groceries = category("Groceries", parent: household)
        let utilities = category("Utilities", parent: household)
        let salary = category("Salary", kind: .income)
        let eatingOut = category("Eating Out")

        let current = Account(name: "Everyday Current", openingBalance: money("1200"))
        current.number = "12344321"
        let card = Account(name: "Credit Card", type: .creditCard, openingBalance: money("-250.75"))
        card.number = "4929123456785678"
        card.creditLimit = 3_000
        let saver = Account(name: "Rainy Day Saver", openingBalance: money("5000"))
        saver.number = "87651234"
        let loan = Account(name: "Car Loan", type: .loan, openingBalance: money("-8400"))
        let isa = Account(name: "Stocks and Shares ISA with the investment platform since 2019", type: .investment, openingBalance: money("12850.40"))
        let wallet = Account(name: "Wallet", type: .cash, openingBalance: money("60"))
        let euro = Account(name: "Euro Account", openingBalance: money("420"), currency: "EUR")
        let closed = Account(name: "Old Current Account", openingBalance: money("12"))
        closed.softDeleted = true
        [current, card, saver, loan, isa, wallet, euro, closed].forEach(context.insert)

        // (account, days ago, payee, amount, category, cleared, reconciled)
        let rows: [(Account, Int, String, String, Category?, Bool, Bool)] = [
            (current, 70, "Employer Ltd", "2345.67", salary, true, true),
            (current, 66, "Corner Grocer", "-70.20", groceries, true, true),
            (current, 60, "Power Co", "-84.10", utilities, true, true),
            (current, 40, "Employer Ltd", "2345.67", salary, true, false),
            (current, 38, "Rent", "-1150", household, true, false),
            (current, 30, "Corner Grocer", "-64.35", groceries, true, false),
            (current, 12, "The Noodle Bar", "-23.80", eatingOut, false, false),
            (current, 9, "Employer Ltd", "2345.67", salary, false, false),
            (current, 7, "Rent", "-1150", household, false, false),
            (current, 2, "Corner Grocer", "-81.02", groceries, false, false),
            (card, 20, "Bookshop", "-18.99", nil, true, false),
            (card, 10, "The Noodle Bar", "-41.50", eatingOut, false, false),
            (card, 5, "Payment Received", "250.75", nil, true, false),
            (loan, 30, "Loan Payment", "350", nil, true, false),
            (wallet, 3, "Coffee", "-3.40", eatingOut, false, false),
            (euro, 15, "Café de Paris", "-28.60", eatingOut, true, false),
        ]
        for (account, daysAgo, payee, amount, category, cleared, reconciled) in rows {
            let transaction = Transaction(account: account, date: day(daysAgo), payee: payee, amount: money(amount), category: category)
            transaction.cleared = cleared
            transaction.reconciled = reconciled
            context.insert(transaction)
        }
        context.insert(AccountReconciliation(account: current, date: day(35), balance: money("3391.37")))
        // Scheduled transactions: monthly, weekly transfer, yearly, paused, and one due this week.
        func schedule(_ account: Account, _ payee: String, _ amount: String, _ rrule: String, due daysAhead: Int,
                      category: Category? = nil, to other: Account? = nil, active: Bool = true) {
            let scheduled = ScheduledTransaction(account: account, payee: payee, amount: money(amount), rrule: rrule)
            scheduled.nextDueDate = day(-daysAhead)
            scheduled.category = category
            scheduled.transferToAccount = other
            scheduled.active = active
            context.insert(scheduled)
        }
        schedule(current, "Employer Ltd", "2345.67", "FREQ=MONTHLY;BYMONTHDAY=18", due: 22, category: salary)
        schedule(current, "Rent", "-1150", "FREQ=MONTHLY;BYMONTHDAY=20", due: 24, category: household)
        schedule(current, "Rainy Day Saver", "-200", "FREQ=WEEKLY;BYDAY=FR", due: 3, to: saver)
        schedule(current, "Power Co", "-84.10", "FREQ=MONTHLY;BYMONTHDAY=28", due: 1, category: utilities)
        schedule(card, "Gym Membership", "-35", "FREQ=MONTHLY;BYMONTHDAY=16", due: 20, active: false)
        schedule(current, "Car Insurance", "-480", "FREQ=YEARLY", due: 60)

        // Payees with defaults, as saving those transactions would have made them.
        context.insert(Payee(name: "Corner Grocer", category: groceries, amount: money("-70.20")))
        context.insert(Payee(name: "Employer Ltd", category: salary, amount: money("2345.67")))
        context.insert(Payee(name: "Rent", category: household, amount: money("-1150")))
        context.insert(Payee(name: "The Noodle Bar", category: eatingOut))
        for name in ["Power Co", "Bookshop", "Coffee", "Café de Paris", "Loan Payment", "Payment Received"] {
            context.insert(Payee(name: name))
        }
    }
}
