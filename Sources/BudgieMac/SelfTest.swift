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

                account.softDeleted = true
                try? context.save()
                let open = (try? context.fetch(Account.openAccounts)) ?? []
                check("deleting an account hides it from lists", !open.contains { $0.uuid == account.uuid })
            }
            // S-006: adding a transaction updates the balance at once and can be undone.
            let wallet = model.add(AccountDraft(currency: "GBP").named("Self-test Wallet"), undoManager: nil)
            // Accounts can be put in any order, which is remembered and can be undone.
            _ = model.add(AccountDraft(currency: "GBP").named("Self-test Alpha"), undoManager: nil)
            _ = model.add(AccountDraft(currency: "GBP").named("Self-test Zulu"), undoManager: nil)
            if let last = model.orderedAccounts.last, model.orderedAccounts.count > 1 {
                let undoMove = UndoManager()
                let before = model.orderedAccounts.map(\.uuid)
                model.setAccountOrder(AccountOrder.moving(model.orderedAccounts, from: [model.orderedAccounts.count - 1], to: 0), undoManager: undoMove)
                check("dragging the last account to the top puts it first", model.orderedAccounts.first === last)
                model.moveAccount(last, by: -1, undoManager: undoMove)
                check("Move Account Up does nothing at the top", model.orderedAccounts.first === last)
                check("Undo is named Undo Move Account", undoMove.undoActionName == "Move Account")
                undoMove.undo()
                check("undoing the move restores the order", model.orderedAccounts.map(\.uuid) == before)
            }
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
            // S-007: changing the amount updates the running balance and the account totals.
            if let kept = try? model.addTransaction(spend, to: wallet, undoManager: nil) {
                var change = TransactionDraft(kept)
                change.withdrawal = "10"
                let undoEdit = UndoManager()
                try? model.edit(kept, with: change, undoManager: undoEdit)
                let rows = Register.rows(Register.fetch(wallet, in: context), openingBalance: wallet.openingBalance)
                check("editing the amount updates the running balance", rows.last?.balance == -10)
                check("editing the amount updates the account total", Money.totals([wallet]).first?.amount == -10)
                undoEdit.undo()
                check("Undo Edit Transaction puts the amount back", kept.amount == Decimal(string: "-3.40")!)
                context.delete(kept)
            }
            // S-008: deleting asks nothing and Undo restores it.
            if let doomed = try? model.addTransaction(spend, to: wallet, undoManager: nil) {
                let undoDelete = UndoManager()
                model.selectedTransactions = [doomed.persistentModelID]
                model.deleteSelectedTransactions(undoManager: undoDelete)
                check("deleting an unreconciled transaction asks nothing", wallet.balance == 0)
                check("Undo is named Undo Delete Transaction", undoDelete.undoActionName == "Delete Transaction")
                undoDelete.undo()
                check("Undo Delete Transaction restores it", wallet.balance == Decimal(string: "-3.40")!)
                for transaction in wallet.transactions { context.delete(transaction) }
                try? context.save()
            }
            // S-009: marking as cleared changes the cleared balance, and Undo puts it back.
            if let row = try? model.addTransaction(spend, to: wallet, undoManager: nil) {
                let undoClear = UndoManager()
                model.selectedTransactions = [row.persistentModelID]
                check("the menu offers Mark as Cleared for an uncleared row", model.clearingTitle == "Mark as Cleared")
                model.toggleCleared(model.selectedTransactionRows, undoManager: undoClear)
                check("Mark as Cleared changes the cleared balance", wallet.clearedBalance == Decimal(string: "-3.40")!)
                check("Undo is named Undo Mark as Cleared", undoClear.undoActionName == "Mark as Cleared")
                undoClear.undo()
                check("Undo Mark as Cleared puts it back", !row.cleared && wallet.clearedBalance == 0)
                model.selectedTransactions = []
                context.delete(row)
                try? context.save()
            }
            spend.withdrawal = ""
            check("an empty amount is refused", (try? model.addTransaction(spend, to: wallet, undoManager: nil)) == nil)

            // S-010: editing and closing an account, each undoable.
            var rename = AccountDraft(wallet)
            rename.name = "Self-test Purse"
            let undoAccount = UndoManager()
            model.save(rename, to: wallet, undoManager: undoAccount)
            check("Edit Account renames the account", wallet.name == "Self-test Purse")
            undoAccount.undo()
            check("Undo Edit Account puts the name back", wallet.name == "Self-test Wallet")
            model.setClosed(wallet, true, undoManager: undoAccount)
            let openNow = (try? context.fetch(Account.openAccounts)) ?? []
            check("a closed account leaves the sidebar", !openNow.contains { $0.uuid == wallet.uuid })
            undoAccount.undo()
            check("Undo Close Account reopens it", !wallet.softDeleted)

            // S-016 and S-017: add, refuse a duplicate, delete with Undo.
            let undoCategory = UndoManager()
            var newCategory = CategoryDraft()
            newCategory.name = "Self-test Hobbies"
            check("Add Category adds it", model.save(newCategory, editing: nil, undoManager: undoCategory))
            check("a duplicate sibling name is refused", !model.save(newCategory, editing: nil, undoManager: nil))
            if let hobbies = ((try? context.fetch(Category.visibleCategories)) ?? []).first(where: { $0.name == "Self-test Hobbies" }) {
                model.setDeleted(hobbies, undoManager: undoCategory)
                check("Delete Category hides it", hobbies.softDeleted)
                undoCategory.undo()
                check("Undo Delete Category brings it back", !hobbies.softDeleted)
            }

            // M3: reconcile the self-test wallet against a statement of -10.
            if let shop = try? model.addTransaction(spend.with(withdrawal: "10"), to: wallet, undoManager: nil) {
                model.startReconcile(wallet, date: Day.today, balance: -10)
                let reconcile = Reconcile(pendingOn: wallet)
                check("Next saves the pending statement", reconcile?.statementBalance == -10)
                check("the matching row starts ticked", model.reconcileTicked.contains(shop.persistentModelID) && model.reconcileAutoMatched)
                check("Finish is allowed when the difference is zero", reconcile?.isBalanced(ticked: model.reconcileTicked) == true)
                // S-024: a row added while reconciling arrives ticked; editing an amount moves the difference.
                if let extra = try? model.addTransaction(spend.with(withdrawal: "5"), to: wallet, undoManager: nil) {
                    check("a transaction added while reconciling arrives ticked", model.reconcileTicked.contains(extra.persistentModelID))
                    check("the new row unbalances the statement", reconcile?.difference(ticked: model.reconcileTicked) == 5)
                    var change = TransactionDraft(extra)
                    change.withdrawal = "2"
                    try? model.edit(extra, with: change, undoManager: nil)
                    check("editing an amount updates the difference", reconcile?.difference(ticked: model.reconcileTicked) == 2)
                    // S-023: an adjustment for the difference balances it.
                    var adjustment = TransactionDraft()
                    adjustment.payee = "Reconciliation adjustment"
                    adjustment.deposit = "2"
                    _ = try? model.addTransaction(adjustment, to: wallet, undoManager: nil)
                    check("an adjustment for the difference balances it", reconcile?.difference(ticked: model.reconcileTicked) == 0)
                }
                if let reconcile { model.finishReconcile(reconcile, undoManager: nil) }
                check("Finish reconciles and clears the pending statement", wallet.pendingReconcileDate == nil && wallet.lastReconciled != nil)
            }

            // M4: add a schedule, record it, skip it, pause it.
            var scheduleDraft = ScheduleDraft(account: wallet)
            scheduleDraft.payee = "Self-test Subscription"
            scheduleDraft.withdrawal = "9.99"
            scheduleDraft.nextDue = Day.parse("2030-01-15")!
            scheduleDraft.recurrence.frequency = .monthly
            scheduleDraft.recurrence.monthDays = [15]
            model.save(scheduleDraft, editing: nil, undoManager: nil)
            let schedules = (try? context.fetch(FetchDescriptor<ScheduledTransaction>())) ?? []
            if let subscription = schedules.first(where: { $0.payee == "Self-test Subscription" }) {
                check("a new schedule shows its frequency", subscription.frequencyLabel == "Monthly")
                let before = wallet.transactions.count
                try? model.record(subscription, as: Scheduling.draft(for: subscription))
                check("Record posts to the register and moves the due date on",
                      wallet.transactions.count == before + 1 && subscription.nextDueDate.map(Day.string) == "2030-02-15")
                Scheduling.skip(subscription, in: context)
                check("Skip moves the due date on without recording", wallet.transactions.count == before + 1
                      && subscription.nextDueDate.map(Day.string) == "2030-03-15")
                // Recording into an account being reconciled joins the list and re-matches.
                model.startReconcile(wallet, date: Day.today, balance: Reconcile(account: wallet, statementDate: Day.today, statementBalance: 0).openingBalance - 9.99)
                model.reconcileTicked = []
                model.reconcileAutoMatched = false
                try? model.record(subscription, as: Scheduling.draft(for: subscription, on: Day.today))
                let recorded = wallet.transactions.first { $0.payee == "Self-test Subscription" && $0.date == Day.today }
                check("a recorded schedule joins a reconcile under way and is matched",
                      recorded.map { Reconcile(pendingOn: wallet)?.eligible.contains($0) == true && model.reconcileTicked.contains($0.persistentModelID) } == true
                      && model.reconcileAutoMatched)
                model.stopReconcile(wallet)
                model.setActive(subscription, false, undoManager: nil)
                check("a paused schedule is left out of the 7-day summary",
                      Scheduling.dueSoon([subscription], today: Day.parse("2030-03-12")!).count == 0)
                context.delete(subscription)
                try? context.save()
            }

            // M5: assigning and moving money keep Available to Budget honest, with Undo.
            let month = "2031-01"
            let first = Envelope(name: "Self-test A"), second = Envelope(name: "Self-test B")
            context.insert(first)
            context.insert(second)
            try? context.save()
            let startATB = Budget.summary(for: month, in: context).availableToBudget
            let undoBudget = UndoManager()
            model.assign(100, to: first, in: month, undoManager: undoBudget)
            let assigned = Budget.summary(for: month, in: context)
            check("assigning lowers Available to Budget and fills the envelope",
                  assigned.availableToBudget == startATB - 100 && assigned.lines.first { $0.envelope === first }?.available == 100)
            model.moveMoney(30, from: first, to: second, in: month, notes: "", undoManager: nil)
            let moved = Budget.summary(for: month, in: context)
            check("moving money changes both envelopes but not Available to Budget",
                  moved.availableToBudget == assigned.availableToBudget
                  && moved.lines.first { $0.envelope === second }?.available == 30)
            undoBudget.undo()
            check("Undo Assign puts the amount back", Budget.assigned(to: first, in: month) == 0)
            Envelopes.delete(first, context: context)
            Envelopes.delete(second, context: context)
            try? context.save()

            // S-051: search narrows the register; clearing it shows everything again.
            let walletRows = Register.rows(Register.fetch(wallet, in: context), openingBalance: wallet.openingBalance)
            check("search narrows the register", !walletRows.isEmpty
                  && walletRows.filter { Register.matches($0.transaction, "no such payee") }.isEmpty
                  && walletRows.contains { Register.matches($0.transaction, $0.transaction.payee) })
            check("an empty search shows every row", walletRows.filter { Register.matches($0.transaction, "") }.count == walletRows.count)

            // S-055: a QIF row that's already there is a duplicate; the new one imports.
            if let qif = try? Qif.parse("!Type:Bank\nD01/02/2031\nPSelf-test QIF\nT-12.34\n^") {
                let before = wallet.transactions.count
                model.importQif(Qif.match(qif.rows, existing: wallet.transactions, lastReconciled: nil), into: wallet, undoManager: nil)
                check("QIF rows import into the account", wallet.transactions.count == before + 1)
                let again = Qif.match(qif.rows, existing: wallet.transactions, lastReconciled: nil)
                check("importing the same QIF again flags it as a duplicate", again.first?.status == .duplicate)
                // S-060: and says which transaction it matched.
                let added = wallet.transactions.first { $0.payee == "Self-test QIF" }
                check("a duplicate names the transaction it matched", added != nil && again.first?.matched?.uuid == added?.uuid)
                check("an imported transaction keeps its bank text", added?.bankText == "Self-test QIF")
            }

            // S-061: an import learns from the transactions you entered, and the next one fills in.
            if let category = try? context.fetch(FetchDescriptor<Category>()).first(where: { !$0.softDeleted && $0.kind == .expense }) {
                let typed = Transaction(account: wallet, date: Day.parse("2031-03-01")!, payee: "Self-test Cafe", amount: Decimal(string: "-4.20")!, category: category)
                context.insert(typed)
                let first = (try? Qif.parse("!Type:Bank\nD02/03/2031\nPSUMUP *SELFTEST CAF\nT-4.20\n^"))?.rows ?? []
                model.importQif(Qif.match(first, existing: wallet.transactions, lastReconciled: nil), into: wallet, undoManager: nil)
                check("a duplicate teaches its bank text", typed.bankText == "SUMUP *SELFTEST CAF")
                let next = ImportRuleBook(context: context).suggestion(for: "SumUp  *SELFTEST CAF", amount: Decimal(string: "-3.80")!)
                check("the next import fills in the payee and category it learned", next?.payee == "Self-test Cafe" && next?.category === category && next?.source == .rule)
                model.importQif(Qif.match(first, existing: wallet.transactions, lastReconciled: nil), into: wallet, undoManager: nil)
                let rules = (try? context.fetch(FetchDescriptor<ImportRule>()))?.filter { $0.payee == "Self-test Cafe" } ?? []
                check("importing the same file again learns nothing new", rules.count == 1 && rules.first?.count == 1)

                // S-062: a new row imports with the payee and category the sheet shows, adding no payee.
                let later = (try? Qif.parse("!Type:Bank\nD01/04/2031\nPSUMUP *SELFTEST CAF\nT-3.80\n^"))?.rows ?? []
                let matches = Qif.match(later, existing: wallet.transactions, lastReconciled: nil)
                let choices = model.qifChoices(for: matches, in: wallet)
                check("the review sheet fills a new row from what it learned", choices[0]?.payee == "Self-test Cafe" && choices[0]?.category === category)
                model.importQif(matches, choices: choices, into: wallet, undoManager: nil)
                let imported = wallet.transactions.first { $0.bankText == "SUMUP *SELFTEST CAF" && $0.amount == Decimal(string: "-3.80")! }
                check("the row imports with the payee and category shown", imported?.payee == "Self-test Cafe" && imported?.category === category)
                let payees = (try? context.fetch(FetchDescriptor<Payee>())) ?? []
                check("no payee is added for bank text that matched a payee", !payees.contains { $0.name.uppercased().contains("SELFTEST CAF") })

                // S-063: recategorising an imported transaction changes what the next import suggests; Undo changes it back.
                if let imported, let other = try? context.fetch(FetchDescriptor<Category>()).first(where: { !$0.softDeleted && $0.kind == .expense && $0 !== category }) {
                    var draft = TransactionDraft(imported, locale: Locale(identifier: "en_US_POSIX"))
                    draft.category = other
                    let undoEdit = UndoManager()
                    undoEdit.groupsByEvent = false
                    undoEdit.beginUndoGrouping()
                    try? model.edit(imported, with: draft, undoManager: undoEdit)
                    undoEdit.endUndoGrouping()
                    let afterEdit = ImportRuleBook(context: context).suggestion(for: "SUMUP *SELFTEST CAF", amount: -2)
                    check("recategorising an imported transaction changes the next suggestion", afterEdit?.category === other)
                    undoEdit.undo()
                    let afterUndo = ImportRuleBook(context: context).suggestion(for: "SUMUP *SELFTEST CAF", amount: -2)
                    check("Undo Edit Transaction puts the suggestion back", afterUndo?.category === category && imported.category === category)
                }

                // S-064: deleting a rule in Settings stops it filling the next import; Undo brings it back.
                let undoDelete = UndoManager()
                undoDelete.groupsByEvent = false
                let cafeRules = (try? context.fetch(FetchDescriptor<ImportRule>()))?.filter { $0.bankText == "SELFTEST CAF" } ?? []
                undoDelete.beginUndoGrouping()
                for rule in cafeRules { model.deleteImportRule(rule, undoManager: undoDelete) }
                undoDelete.endUndoGrouping()
                let afterDelete = ImportRuleBook(context: context).suggestion(for: "SUMUP *SELFTEST CAF", amount: -2)
                check("a deleted rule no longer fills the next import", afterDelete?.source != .rule && afterDelete?.source != .ruleForAmount)
                check("Undo is named Undo Delete Rule", undoDelete.undoActionName == "Delete Rule")
                undoDelete.undo()
                let restored = ImportRuleBook(context: context).suggestion(for: "SUMUP *SELFTEST CAF", amount: -2)
                check("Undo Delete Rule brings the rule back", restored?.source == .rule && restored?.category === category)
            }

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

            // S-052: preferences persist and apply at once.
            model.preferences.appearance = .dark
            model.applyAppearance()
            check("Dark appearance applies at once", NSApp.appearance?.name == .darkAqua)
            model.preferences.appearance = .system
            model.applyAppearance()
            check("System appearance follows the Mac", NSApp.appearance == nil)
            model.preferences.startupPage = "budget"
            model.openStartPage()
            check("the start page opens", model.sidebar == .page(.budget))
            model.preferences.startupPage = nil

            // S-050: an account shortcut that clashes with a menu shortcut is refused.
            check("⌘N can't open an account", Shortcuts.problem(with: KeyShortcut("n", .command, "x")) != nil)
            model.setShortcut(AccountShortcut(key: "9", ctrl: true, accountUUID: wallet.uuid), for: wallet.uuid)
            check("an account shortcut is saved", model.preferences.accountShortcuts.contains { $0.accountUUID == wallet.uuid })
            model.setShortcut(nil, for: wallet.uuid)

            // S-054: restore replaces the data with a backup, without a relaunch.
            let folder = URL(fileURLWithPath: "/tmp/BudgieMac-selftest-backups", isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
            if let backup = try? Backups.write(BudgieExport.data(from: context), to: folder) {
                let count = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
                _ = try? model.addTransaction(spend.with(withdrawal: "1"), to: wallet, undoManager: nil)
                let restored = try? model.restoreNow(backup)
                check("restoring a backup brings the data back", restored != nil
                      && ((try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0) == count)
                check("backups are listed newest first", Backups.list(folder).first?.url.lastPathComponent == backup.lastPathComponent)
            }

            // S-049: the menu bar has every shortcut, and items that can't apply are off.
            model.sidebar = .page(.accounts)
            model.selectedTransactions = []
            try? await Task.sleep(for: .seconds(0.5))
            func items(_ menu: NSMenu?) -> [NSMenuItem] {
                (menu?.items ?? []).flatMap { [$0] + items($0.submenu) }
            }
            let menuItems = items(NSApp.mainMenu)
            func item(_ title: String) -> NSMenuItem? { menuItems.first { $0.title == title } }
            for shortcut in Shortcuts.builtIn where !["Undo", "Redo", "Close Window", "Quit", "Hide", "Minimize", "Settings…", "Previous Month", "Next Month"].contains(shortcut.title) {
                let title = shortcut.title == "Find" ? "Find in Register" : shortcut.title
                let found = item(title)
                // AppKit stores arrow keys as function-key characters.
                let key = ["↑": "\u{F700}", "↓": "\u{F701}"][shortcut.key] ?? shortcut.key
                check("menu has \(title) \(shortcut.symbols)", found?.keyEquivalent.lowercased() == key,
                      "found \(found.map { "'\($0.keyEquivalent)'" } ?? "nothing")")
            }
            for title in ["New Transaction", "Reconcile…", "Forecast", "Edit Transaction…", "Delete Transaction", "Mark as Cleared"] {
                check("\(title) is off with no account open", item(title)?.isEnabled == false)
            }

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
