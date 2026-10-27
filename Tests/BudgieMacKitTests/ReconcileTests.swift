import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// M3: reconciling.
@MainActor
@Suite("Reconcile")
struct ReconcileTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    private func account(_ rows: [(String, String, cleared: Bool, reconciled: Bool)], opening: Decimal = 100) -> Account {
        let account = Account(name: "Bank", openingBalance: opening)
        context.insert(account)
        for (day, amount, cleared, reconciled) in rows {
            let transaction = Transaction(account: account, date: Day.parse(day)!, payee: day, amount: Decimal(string: amount)!)
            transaction.cleared = cleared
            transaction.reconciled = reconciled
            context.insert(transaction)
        }
        try? context.save()
        return account
    }

    @Test("Start saves the pending statement")
    func start() {
        let bank = account([])
        Reconcile.start(bank, statementDate: Day.parse("2026-09-30")!, statementBalance: 250)
        #expect(bank.pendingReconcileBalance == 250 && bank.pendingReconcileDate.map(Day.string) == "2026-09-30")
        #expect(Reconcile(pendingOn: bank)?.statementBalance == 250)
        Reconcile.stop(bank)
        #expect(Reconcile(pendingOn: bank) == nil)
    }

    @Test("Ticked rows start as a subset that matches the statement")
    func autoMatch() {
        let bank = account([("2026-09-01", "-30", false, false), ("2026-09-02", "-20", true, false), ("2026-09-03", "50", false, false),
                            ("2026-10-15", "-5", false, false)])
        let reconcile = Reconcile(account: bank, statementDate: Day.parse("2026-09-30")!, statementBalance: 150)
        #expect(reconcile.eligible.count == 3)
        let (ticked, matched) = reconcile.initialTicks()
        #expect(matched && reconcile.isBalanced(ticked: ticked))
    }

    @Test("Without a matching subset, the cleared rows start ticked")
    func clearedFirst() {
        let bank = account([("2026-09-01", "-30", true, false), ("2026-09-02", "-20", false, false)])
        let reconcile = Reconcile(account: bank, statementDate: Day.parse("2026-09-30")!, statementBalance: 1)
        let (ticked, matched) = reconcile.initialTicks()
        #expect(!matched && ticked.count == 1)
        #expect(reconcile.clearedBalance(ticked: ticked) == 70 && reconcile.difference(ticked: ticked) == -69)
    }

    @Test("Finish is refused unless balanced, then reconciles the ticked rows and saves a checkpoint")
    func finish() throws {
        let bank = account([("2026-08-01", "10", true, true), ("2026-09-01", "-30", true, false), ("2026-09-02", "-20", false, false)])
        let reconcile = Reconcile.start(bank, statementDate: Day.parse("2026-09-30")!, statementBalance: 80)
        #expect(reconcile.openingBalance == 110)
        let ticked = Set(reconcile.eligible.filter(\.cleared).map(\.persistentModelID))
        #expect(throws: Reconcile.Problem.notBalanced) { try reconcile.finish(ticked: [], in: context) }
        try reconcile.finish(ticked: ticked, in: context)
        #expect(bank.transactions.filter(\.reconciled).count == 2)
        #expect(bank.lastReconciled.map(Day.string) == "2026-09-30" && bank.pendingReconcileDate == nil)
    }

    @Test("The reconcile cleared balance is the Accounts page's cleared balance")
    func sameClearedBalance() {
        let bank = account([("2026-08-01", "10", true, true), ("2026-09-01", "-30", true, false), ("2026-09-02", "-20", false, false)])
        let reconcile = Reconcile(account: bank, statementDate: Day.parse("2026-09-30")!, statementBalance: 0)
        let ticked = Set(reconcile.eligible.filter(\.cleared).map(\.persistentModelID))
        #expect(reconcile.clearedBalance(ticked: ticked) == bank.clearedBalance)
    }

    @Test("Subset sum, like Budgie's", arguments: [
        (["1.10", "2.20", "3.30"], "3.30", true),
        (["-5", "10", "-2.5"], "2.5", true),
        (["1", "2"], "4", false),
        (["1"], "0", false),
    ])
    func subsetSum(_ amounts: [String], target: String, found: Bool) {
        let values = amounts.map { Decimal(string: $0)! }
        let result = SubsetSum.find(values, target: Decimal(string: target)!)
        #expect((result != nil) == found)
        if let result { #expect(result.reduce(Decimal(0)) { $0 + values[$1] } == Decimal(string: target)!) }
    }
}
