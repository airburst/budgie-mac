import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-019 and S-020.
@MainActor
@Suite("Payees")
struct PayeeTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    private func setUp() -> (Payee, Transaction) {
        let account = Account(name: "Bank")
        context.insert(account)
        let payee = Payee(name: "Corner Grocer", amount: -70)
        context.insert(payee)
        let transaction = Transaction(account: account, payee: "Corner Grocer", amount: -70)
        context.insert(transaction)
        return (payee, transaction)
    }

    @Test("Renaming can update existing transactions with the old name")
    func renameUpdates() throws {
        let (payee, transaction) = setUp()
        var draft = PayeeDraft(payee)
        draft.name = "Corner Shop"
        PayeeEditing.save(draft, to: payee, updatingTransactions: true, in: context)
        #expect(payee.name == "Corner Shop" && transaction.payee == "Corner Shop")
    }

    @Test("Renaming without updating leaves past transactions alone")
    func renameOnly() throws {
        let (payee, transaction) = setUp()
        var draft = PayeeDraft(payee)
        draft.name = "Corner Shop"
        PayeeEditing.save(draft, to: payee, updatingTransactions: false, in: context)
        #expect(payee.name == "Corner Shop" && transaction.payee == "Corner Grocer")
    }

    @Test("Renaming to an existing name merges the two")
    func merge() throws {
        let (payee, transaction) = setUp()
        let other = Payee(name: "Big Supermarket")
        context.insert(other)
        try context.save()
        var draft = PayeeDraft(payee)
        draft.name = "big supermarket"
        let kept = PayeeEditing.save(draft, to: payee, updatingTransactions: true, in: context)
        try context.save()
        #expect(kept === other && other.amount == -70)
        #expect(try context.fetch(FetchDescriptor<Payee>()).map(\.name) == ["Big Supermarket"])
        #expect(transaction.payee == "Big Supermarket")
    }

    @Test("Deleting a payee keeps its text on past transactions")
    func delete() throws {
        let (payee, transaction) = setUp()
        context.delete(payee)
        try context.save()
        #expect(transaction.payee == "Corner Grocer")
        #expect(try context.fetchCount(FetchDescriptor<Payee>()) == 0)
    }
}
