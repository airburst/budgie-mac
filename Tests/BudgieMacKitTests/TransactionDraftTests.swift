import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-006: adding a transaction.
@MainActor
@Suite("Transaction draft")
struct TransactionDraftTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }
    let uk = Locale(identifier: "en_GB")

    private func account() -> Account {
        let account = Account(name: "Bank", openingBalance: 100)
        context.insert(account)
        return account
    }

    @Test("A withdrawal is negative and a deposit positive")
    func signs() throws {
        let bank = account()
        var draft = TransactionDraft()
        draft.payee = "Corner Grocer"
        draft.withdrawal = "70.20"
        #expect(try draft.add(to: bank, in: context, locale: uk).amount == Decimal(string: "-70.20")!)
        draft.withdrawal = ""
        draft.deposit = "1,000"
        #expect(try draft.add(to: bank, in: context, locale: uk).amount == 1_000)
        draft.deposit = "-5"
        #expect(try draft.add(to: bank, in: context, locale: uk).amount == 5)
        #expect(bank.balance == Decimal(string: "1034.80")!)
    }

    @Test("Both amounts, or neither, are refused")
    func refused() {
        let bank = account()
        var draft = TransactionDraft()
        #expect(throws: TransactionDraft.Problem.noAmount) { try draft.add(to: bank, in: context, locale: uk) }
        draft.withdrawal = "1"
        draft.deposit = "2"
        #expect(throws: TransactionDraft.Problem.bothAmounts) { try draft.add(to: bank, in: context, locale: uk) }
        draft.deposit = ""
        draft.withdrawal = "lots"
        #expect(throws: TransactionDraft.Problem.notANumber) { try draft.add(to: bank, in: context, locale: uk) }
        #expect(bank.transactions.isEmpty)
    }

    @Test("A new payee name creates a Payee, once")
    func newPayee() throws {
        let bank = account()
        context.insert(Payee(name: "Corner Grocer"))
        var draft = TransactionDraft()
        draft.withdrawal = "1"
        draft.payee = "corner grocer"
        try draft.add(to: bank, in: context, locale: uk)
        draft.payee = "  The   Noodle Bar "
        try draft.add(to: bank, in: context, locale: uk)
        try draft.add(to: bank, in: context, locale: uk)
        let names = try context.fetch(FetchDescriptor<Payee>()).map(\.name).sorted()
        #expect(names == ["Corner Grocer", "The Noodle Bar"])
    }

    @Test("Editing fills the sheet and writes back")
    func edit() throws {
        let bank = account()
        let transaction = Transaction(account: bank, payee: "Rent", amount: Decimal(string: "-1150")!)
        transaction.notes = "Flat"
        context.insert(transaction)
        var draft = TransactionDraft(transaction, locale: uk)
        #expect(draft.withdrawal == "1150.00" && draft.deposit.isEmpty && draft.notes == "Flat")
        draft.withdrawal = "1200"
        try draft.apply(to: transaction, in: context, locale: uk)
        #expect(transaction.amount == -1_200 && bank.balance == -1_100)
    }

    @Test("A date more than a year away is noticed")
    func farDate() {
        var draft = TransactionDraft()
        #expect(!draft.isFarFromToday)
        draft.date = Day.calendar.date(byAdding: .month, value: 13, to: Day.today)!
        #expect(draft.isFarFromToday)
    }
}

/// S-007: editing one half of a transfer updates the other half.
@MainActor
@Suite("Transfers")
struct TransferTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("Editing one half of a transfer updates the other")
    func syncsPartner() throws {
        let current = Account(name: "Current"), saver = Account(name: "Saver")
        context.insert(current)
        context.insert(saver)
        let out = Transaction(account: current, date: Day.parse("2026-09-01")!, payee: "To Saver", amount: -100)
        let into = Transaction(account: saver, date: Day.parse("2026-09-01")!, payee: "From Current", amount: 100)
        out.transferUUID = into.uuid
        into.transferUUID = out.uuid
        into.cleared = true
        context.insert(out)
        context.insert(into)

        var draft = TransactionDraft(out, locale: Locale(identifier: "en_GB"))
        draft.withdrawal = "250"
        draft.date = Day.parse("2026-09-02")!
        try draft.apply(to: out, in: context, locale: Locale(identifier: "en_GB"))
        Transfers.syncPartner(of: out, in: context)

        #expect(into.amount == 250 && Day.string(into.date) == "2026-09-02")
        #expect(into.payee == "From Current" && into.cleared)
        #expect(current.balance == -250 && saver.balance == 250)
    }
}

/// S-008: deleting transactions.
@MainActor
@Suite("Deletion")
struct DeletionTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("Deleting one half of a transfer deletes both, and restoring brings both back linked")
    func transferPair() throws {
        let current = Account(name: "Current"), saver = Account(name: "Saver")
        context.insert(current)
        context.insert(saver)
        let out = Transaction(account: current, payee: "To Saver", amount: -100)
        let into = Transaction(account: saver, payee: "From Current", amount: 100)
        out.transferUUID = into.uuid
        into.transferUUID = out.uuid
        let other = Transaction(account: current, payee: "Shop", amount: -5)
        [out, into, other].forEach(context.insert)
        try context.save()
        let outUUID = out.uuid

        let records = TransactionDeletion.delete([out], in: context)
        try context.save()
        #expect(records.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(current.balance == -5 && saver.balance == 0)

        TransactionDeletion.restore(records, in: context)
        try context.save()
        let restored = try #require(try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.uuid == outUUID })).first)
        #expect(Transfers.partner(of: restored, in: context)?.account?.name == "Saver")
        #expect(current.balance == -105 && saver.balance == 100)
    }
}
