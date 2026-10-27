import Foundation
import Testing
@testable import BudgieMacKit

/// S-004: adding an account.
@Suite("Account draft")
struct AccountDraftTests {
    let uk = Locale(identifier: "en_GB")

    @Test("Currency defaults to GBP")
    func defaults() {
        #expect(AccountDraft(currency: nil).currency == "GBP")
        #expect(AccountDraft(currency: "GBP").type == .bank)
    }

    @Test("Add Account needs a name")
    func needsName() {
        var draft = AccountDraft(currency: "GBP")
        #expect(!draft.canAdd(locale: uk))
        draft.name = "   "
        #expect(!draft.canAdd(locale: uk))
        draft.name = "Wallet"
        #expect(draft.canAdd(locale: uk))
        draft.openingBalance = "twelve"
        #expect(!draft.canAdd(locale: uk))
    }

    @MainActor
    @Test("The opening balance is stored as given")
    func openingBalance() {
        var draft = AccountDraft(currency: "GBP")
        draft.name = "  Everyday   Current "
        draft.openingBalance = "-1,234.56"
        draft.number = " 12344321 "
        draft.interestRate = "1.5"
        let account = draft.makeAccount(locale: uk)
        #expect(account.name == "Everyday Current")
        #expect(account.openingBalance == Decimal(string: "-1234.56")!)
        #expect(account.currency == "GBP")
        #expect(account.number == "12344321")
        #expect(account.interestRate == Decimal(string: "1.5"))
        #expect(account.creditLimit == nil)
    }

    @MainActor
    @Test("Interest rate is kept for every type, credit limit for credit cards only", arguments: AccountType.allCases)
    func interestForEveryType(_ type: AccountType) {
        var draft = AccountDraft(currency: "GBP")
        draft.name = "A"
        draft.type = type
        draft.interestRate = "3.9"
        draft.creditLimit = "2000"
        let account = draft.makeAccount(locale: uk)
        #expect(account.interestRate == Decimal(string: "3.9"))
        #expect(account.creditLimit == (type == .creditCard ? 2_000 : nil))
    }

    @Test("Typed amounts", arguments: [("", "0"), ("12", "12"), ("£1,000.50", "1000.5"), ("-0.10", "-0.1"), ("−5", "-5")])
    func parse(_ text: String, expected: String) {
        #expect(Money.parse(text, locale: uk) == Decimal(string: expected)!)
    }

    @Test("Not amounts", arguments: ["abc", "1.2.3", "-", "."])
    func notAmounts(_ text: String) {
        #expect(Money.parse(text, locale: uk) == nil)
    }

    @Test("A duplicate name is noticed, ignoring case")
    func duplicate() {
        var draft = AccountDraft(currency: "GBP")
        draft.name = "wallet "
        #expect(draft.duplicateName(among: ["Wallet", "Bank"]) == "wallet")
        draft.name = "Purse"
        #expect(draft.duplicateName(among: ["Wallet"]) == nil)
    }
}
