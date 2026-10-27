import BudgieMacKit
import SwiftData
import SwiftUI

/// Everything a person can do to accounts, each with its Undo:
/// add (S-004), edit and close (S-010).
extension AppModel {
    /// Adds the account, opens it, and offers "Undo Add Account".
    @discardableResult
    func add(_ draft: AccountDraft, undoManager: UndoManager?) -> Account {
        let account = draft.makeAccount()
        let context = container.mainContext
        context.insert(account)
        try? context.save()
        sidebar = .account(account.uuid)
        undoManager?.registerUndo(withTarget: self) { model in
            if model.sidebar == .account(account.uuid) { model.sidebar = .page(.accounts) }
            context.delete(account)
            try? context.save()
        }
        undoManager?.setActionName("Add Account")
        return account
    }

    /// Saves Edit Account and offers "Undo Edit Account".
    func save(_ draft: AccountDraft, to account: Account, undoManager: UndoManager?) {
        let before = AccountDraft(account)
        draft.apply(to: account)
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in
            model.save(before, to: account, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Account")
    }

    /// The open account, or the one selected in the sidebar, for the Account menu.
    var menuAccount: Account? {
        guard let uuid = openAccount else { return nil }
        return try? container.mainContext.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.uuid == uuid })).first
    }

    /// Asks, then hides the account from the sidebar and totals. Its
    /// transactions stay, so past reports don't change. Undo reopens it.
    func closeAccount(_ account: Account, undoManager: UndoManager?) {
        let count = account.transactions.count
        Confirm.destructive("Close “\(account.name)”?",
                            message: "It leaves the sidebar and the totals. Its \(ImportFlow.count(count, "transaction")) stay in reports for past dates.",
                            button: "Close Account") {
            self.setClosed(account, true, undoManager: undoManager)
        }
    }

    /// Closes or reopens without asking (the confirmation's action, and the self-test).
    func setClosed(_ account: Account, _ closed: Bool, undoManager: UndoManager?) {
        account.softDeleted = closed
        account.updatedAt = .now
        if closed, sidebar == .account(account.uuid) { sidebar = .page(.accounts) }
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in
            model.setClosed(account, !closed, undoManager: undoManager)
        }
        undoManager?.setActionName(closed ? "Close Account" : "Reopen Account")
    }
}

/// The context menu on an account, in the sidebar and the accounts table.
struct AccountMenuItems: View {
    let account: Account
    let undoManager: UndoManager?
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Open") { model.sidebar = .account(account.uuid) }
        Button("Edit Account…") { model.accountSheet = .edit(account.uuid) }
        Divider()
        Button("Close Account…", role: .destructive) { model.closeAccount(account, undoManager: undoManager) }
    }
}

/// The Account menu in the menu bar, for the open account.
struct AccountCommands: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button("Edit Account…") {
            if let uuid = model.openAccount { model.accountSheet = .edit(uuid) }
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
        .disabled(model.openAccount == nil)
        Button("Close Account…") {
            if let account = model.menuAccount { model.closeAccount(account, undoManager: undoManager) }
        }
        .disabled(model.openAccount == nil)
    }
}
