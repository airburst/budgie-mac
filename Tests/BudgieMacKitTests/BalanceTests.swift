import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-003: balances, cleared balances, remaining credit, and totals per currency.
@MainActor
@Suite("Balances")
struct BalanceTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    private func add(_ account: Account, _ amounts: [(String, cleared: Bool, reconciled: Bool)]) {
        context.insert(account)
        for (amount, cleared, reconciled) in amounts {
            let transaction = Transaction(account: account, payee: "x", amount: Decimal(string: amount)!)
            transaction.cleared = cleared
            transaction.reconciled = reconciled
            context.insert(transaction)
        }
    }

    @Test("Balance, cleared balance and remaining credit")
    func balances() throws {
        let card = Account(name: "Card", type: .creditCard, openingBalance: Decimal(string: "-100.50")!)
        card.creditLimit = 1_000
        add(card, [("-70.20", true, false), ("-29.30", false, false), ("200", true, true)])
        #expect(card.balance == Decimal(string: "0")!)
        #expect(card.clearedBalance == Decimal(string: "29.30")!)
        #expect(card.remainingCredit == 1_000)

        let bank = Account(name: "Bank", openingBalance: 5)
        bank.creditLimit = 500
        add(bank, [])
        #expect(bank.balance == 5 && bank.clearedBalance == 5)
        #expect(bank.remainingCredit == nil)
        #expect(Account(name: "No limit", type: .creditCard).remainingCredit == nil)
    }

    @Test("Last reconciled is the latest statement date")
    func lastReconciled() throws {
        let account = Account(name: "Bank")
        context.insert(account)
        #expect(account.lastReconciled == nil)
        for day in ["2026-08-22", "2026-09-22", "2026-07-22"] {
            context.insert(AccountReconciliation(account: account, date: Day.parse(day)!, balance: 0))
        }
        #expect(account.lastReconciled.map(Day.string) == "2026-09-22")
    }

    @Test("Totals are added up per currency")
    func totals() throws {
        let gbp1 = Account(name: "A", openingBalance: 100), gbp2 = Account(name: "B", openingBalance: -30)
        let eur = Account(name: "C", openingBalance: 50, currency: "EUR")
        [gbp1, gbp2, eur].forEach { add($0, [("0.25", false, false)]) }
        #expect(Money.totals([gbp1, gbp2, eur], localCurrency: "GBP") == [
            Money.Total(currency: "GBP", amount: Decimal(string: "70.50")!),
            Money.Total(currency: "EUR", amount: Decimal(string: "50.25")!),
        ])
        #expect(Money.totals([gbp1, eur], localCurrency: "USD").map(\.currency) == ["EUR", "GBP"])
    }

    @Test("Money shows sign first with separators")
    func format() {
        let uk = Locale(identifier: "en_GB")
        #expect(Money.string(Decimal(string: "-1150")!, currency: "GBP", locale: uk) == "-£1,150.00")
        #expect(Money.string(Decimal(string: "4778.58")!, currency: "GBP", locale: uk) == "£4,778.58")
        #expect(Money.string(Decimal(string: "-0.5")!, currency: "EUR", locale: uk) == "-€0.50")
    }

    @Test("Account numbers are masked", arguments: [("12344321", "•• 4321"), ("12-34-56 7890", "•• 7890"), ("", nil)])
    func mask(_ number: String, expected: String?) {
        #expect(Money.mask(number) == expected)
    }
}
