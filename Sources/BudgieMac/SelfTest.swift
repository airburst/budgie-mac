import AppKit
import SwiftData
import BudgieMacKit

/// Self-test for agents: runs the app's real functions on a test store,
/// prints PASS or FAIL per check, and quits with exit code 0 or 1.
///   APP_STORE=/tmp/BudgieMac-self.store ~/Applications/BudgieMac.app/Contents/MacOS/BudgieMac --selftest
/// (tools/selftest.sh does this.) Add a check for every story with logic.
@MainActor
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--selftest") }
    /// Read by AppDelegate.applicationWillTerminate.
    static var exitCode: Int32 = 0
    private static var failures = 0
    private static var count = 0

    static func runIfRequested(model: AppModel) {
        guard requested else { return }
        // Print each line at once, so a crash keeps the lines before it.
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isOverridden else {
            print("SELFTEST refused: set APP_STORE to a file in /tmp")
            finish(code: 1)
            return
        }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            let context = model.container.mainContext
            func accounts() -> [Account] { (try? context.fetch(FetchDescriptor<Account>())) ?? [] }

            let before = accounts().count
            var draft = AccountDraft(currency: "GBP")
            check("Add Account is disabled until Name is filled", !draft.canAdd())
            draft.name = "Self-test Account"
            check("Add Account is enabled once Name is filled", draft.canAdd())
            let undo = UndoManager()
            model.add(draft, undoManager: undo)
            check("Add Account adds one account", accounts().count == before + 1)
            check("the new account is selected", accounts().contains { model.sidebar == .account($0.uuid) })

            check("Undo is named Undo Add Account", undo.undoActionName == "Add Account")
            undo.undo()
            check("undoing Add Account removes it", accounts().count == before)
            model.add(draft, undoManager: nil)

            if let account = accounts().first(where: { model.sidebar == .account($0.uuid) }) {
                // S-001: a transaction survives a reload of the store.
                let transaction = Transaction(account: account, payee: "Corner Grocer", amount: Decimal(string: "-70.20")!)
                context.insert(transaction)
                try? context.save()
                let reloaded = try? BudgieSchema.container(url: Store.url)
                let uuid = transaction.uuid
                let found = try? reloaded?.mainContext.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.uuid == uuid })).first
                check("a saved transaction is there after reloading the store",
                      found?.payee == "Corner Grocer" && found?.amount == Decimal(string: "-70.20")! && found?.account?.uuid == account.uuid)

                account.deleted = true
                try? context.save()
                let open = (try? context.fetch(Account.openAccounts)) ?? []
                check("deleting an account hides it from lists", !open.contains { $0.uuid == account.uuid })
            }
            // S-006: adding a transaction updates the balance at once and can be undone.
            let wallet = model.add(AccountDraft(currency: "GBP").named("Self-test Wallet"), undoManager: nil)
            var spend = TransactionDraft()
            spend.payee = "Self-test Café"
            spend.withdrawal = "3.40"
            let undoAdd = UndoManager()
            let added = try? model.addTransaction(spend, to: wallet, undoManager: undoAdd)
            check("Add Transaction updates the balance at once", wallet.balance == Decimal(string: "-3.40")!)
            check("the new transaction is selected", added.map { model.selectedTransactions == [$0.persistentModelID] } ?? false)
            check("Undo is named Undo Add Transaction", undoAdd.undoActionName == "Add Transaction")
            undoAdd.undo()
            check("undoing Add Transaction removes it", wallet.balance == 0)
            spend.withdrawal = ""
            check("an empty amount is refused", (try? model.addTransaction(spend, to: wallet, undoManager: nil)) == nil)

            // S-005: a register of 2,000 transactions opens in under 300 ms.
            let big = Account(name: "Self-test Big Register")
            context.insert(big)
            let start = Day.parse("2020-01-01")!
            for index in 0..<2_000 {
                context.insert(Transaction(account: big, date: start.addingTimeInterval(Double(index) * 86_400),
                                           payee: "Payee \(index % 40)", amount: Decimal(index % 7) - 3))
            }
            try? context.save()
            let clock = ContinuousClock()
            var rows: [RegisterRow] = []
            let elapsed = clock.measure {
                rows = Register.rows(Register.fetch(big, in: context), openingBalance: big.openingBalance)
            }
            check("a 2,000-transaction register loads in under 300 ms", rows.count == 2_000 && elapsed < .milliseconds(300),
                  "\(rows.count) rows in \(elapsed)")
            check("the register's last running balance is the account balance", rows.last?.balance == big.balance)

            check("account names are cleaned", AccountName.clean("  Joint   Account ") == "Joint Account")

            print(failures == 0 ? "SELFTEST PASS \(count) checks" : "SELFTEST FAIL \(failures) of \(count) checks")
            finish(code: failures == 0 ? 0 : 1)
        }
    }

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        count += 1
        if !ok { failures += 1 }
        print(ok ? "PASS \(name)" : "FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")")
    }

    /// Quits through NSApp.terminate, never exit(), and closes sheets first:
    /// an open sheet refuses terminate, and the run would wait forever.
    static func finish(code: Int32) {
        exitCode = code
        for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
        NSApp.terminate(nil)
    }
}
