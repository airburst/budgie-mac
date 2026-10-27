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
            model.addAccount()
            check("New Account adds one account", accounts().count == before + 1)
            let added = accounts().first { model.sidebar == .account($0.uuid) }
            check("the new account is selected", added != nil)

            if let account = added {
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
