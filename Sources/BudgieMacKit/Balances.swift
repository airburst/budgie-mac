import Foundation

// S-003: the numbers on All Accounts and in the sidebar.

public extension Account {
    /// Opening balance plus every transaction.
    var balance: Decimal {
        transactions.reduce(openingBalance) { $0 + $1.amount }
    }

    /// Opening balance plus cleared and reconciled transactions.
    var clearedBalance: Decimal {
        transactions.reduce(openingBalance) { $0 + (($1.cleared || $1.reconciled) ? $1.amount : 0) }
    }

    /// Credit limit plus balance, for credit cards with a limit only.
    var remainingCredit: Decimal? {
        guard type == .creditCard, let creditLimit else { return nil }
        return creditLimit + balance
    }

    /// The statement date of the latest reconciliation.
    var lastReconciled: Date? {
        reconciliations.map(\.date).max()
    }

    /// "•• 4321": account numbers are masked everywhere but the account form.
    var maskedNumber: String? {
        Money.mask(number)
    }
}

public enum Money {
    /// A total for one currency. Currencies are never added together.
    public struct Total: Equatable, Sendable {
        public var currency: String
        public var amount: Decimal
    }

    /// Adds balances up per currency: the Mac's own currency first, then the rest by code.
    public static func totals(_ accounts: [Account], localCurrency: String? = Locale.current.currency?.identifier) -> [Total] {
        var sums: [String: Decimal] = [:]
        for account in accounts { sums[account.currency, default: 0] += account.balance }
        let codes = sums.keys.sorted { ($0 == localCurrency ? 0 : 1, $0) < ($1 == localCurrency ? 0 : 1, $1) }
        return codes.map { Total(currency: $0, amount: sums[$0]!) }
    }

    /// "-£1,150.00": sign first, thousands separators, the currency's own decimals.
    public static func string(_ amount: Decimal, currency: String, locale: Locale = .current) -> String {
        amount.formatted(.currency(code: currency).locale(locale).sign(strategy: .automatic))
    }

    public static func mask(_ number: String?) -> String? {
        let characters = (number ?? "").filter { $0.isLetter || $0.isNumber }
        return characters.isEmpty ? nil : "•• \(characters.suffix(4))"
    }
}
