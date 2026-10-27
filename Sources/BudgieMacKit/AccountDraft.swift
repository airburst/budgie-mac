import Foundation
import SwiftData

/// S-004: what the Add Account sheet edits before the account exists.
public struct AccountDraft: Equatable, Sendable {
    public var name = ""
    public var type: AccountType = .bank
    public var number = ""
    public var openingBalance = ""
    public var currency: String
    public var creditLimit = ""
    public var interestRate = ""

    /// Currency defaults to the Mac's region, and to GBP when it has none.
    public init(currency: String? = Locale.current.currency?.identifier) {
        self.currency = currency ?? "GBP"
    }

    /// Add Account stays disabled until Name is filled and the numbers read as numbers.
    public func canAdd(locale: Locale = .current) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Money.parse(openingBalance, locale: locale) != nil
            && (creditLimit.isEmpty || Money.parse(creditLimit, locale: locale) != nil)
            && (interestRate.isEmpty || Money.parse(interestRate, locale: locale) != nil)
    }

    /// "Another account is already called "Wallet"." A warning only.
    public func duplicateName(among names: [String]) -> String? {
        let clean = AccountName.clean(name)
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              names.contains(where: { $0.compare(clean, options: .caseInsensitive) == .orderedSame }) else { return nil }
        return clean
    }

    /// The same draft with a name, for tests and scripts.
    public func named(_ name: String) -> AccountDraft {
        var draft = self
        draft.name = name
        return draft
    }

    public func makeAccount(locale: Locale = .current) -> Account {
        let account = Account(name: AccountName.clean(name), type: type,
                              openingBalance: Money.parse(openingBalance, locale: locale) ?? 0, currency: currency)
        let number = number.trimmingCharacters(in: .whitespaces)
        account.number = number.isEmpty ? nil : number
        if type == .creditCard, !creditLimit.isEmpty { account.creditLimit = Money.parse(creditLimit, locale: locale) }
        if !interestRate.isEmpty { account.interestRate = Money.parse(interestRate, locale: locale) }
        return account
    }
}

public extension Money {
    /// Reads what someone typed: "1,234.56", "-50", "£1,000", "" (zero). Nil when it isn't a number.
    static func parse(_ text: String, locale: Locale = .current) -> Decimal? {
        let separator = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        var cleaned = text.filter { !$0.isWhitespace && !$0.isCurrencySymbol }
        cleaned = cleaned.replacingOccurrences(of: grouping, with: "")
        cleaned = cleaned.replacingOccurrences(of: separator, with: ".")
        cleaned = cleaned.replacingOccurrences(of: "−", with: "-")
        if cleaned.isEmpty { return 0 }
        guard cleaned.wholeMatch(of: /-?\d*\.?\d*/) != nil, cleaned.contains(where: \.isNumber) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

private extension Character {
    var isCurrencySymbol: Bool { unicodeScalars.allSatisfy { $0.properties.generalCategory == .currencySymbol } }
}
