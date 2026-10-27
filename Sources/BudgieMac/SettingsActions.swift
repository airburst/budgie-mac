import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// S-050, S-052, S-054: what Settings changes, applied at once.
extension AppModel {
    var preferences: Preferences { Preferences.current(in: container.mainContext) }

    /// Light, Dark, or follow the Mac.
    func applyAppearance() {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Opens the start page from Settings, at launch.
    func openStartPage() {
        switch StartPage(preferences.startupPage) {
        case .page(let name):
            if let page = SidebarItem(rawValue: name) { sidebar = .page(page) }
        case .account(let uuid):
            let open = (try? container.mainContext.fetch(Account.openAccounts)) ?? []
            if open.contains(where: { $0.uuid == uuid }) { sidebar = .account(uuid) }
        case nil:
            break
        }
    }

    func setShortcut(_ shortcut: AccountShortcut?, for account: UUID) {
        let prefs = preferences
        var all = prefs.accountShortcuts.filter { $0.accountUUID != account }
        if let shortcut { all.append(shortcut) }
        prefs.accountShortcuts = all
        try? container.mainContext.save()
    }

    // MARK: Backups

    var backupFolder: URL {
        preferences.backupFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Backups.defaultFolder
    }

    var backupRetentionDays: Int { preferences.backupRetentionDays ?? Backups.defaultRetentionDays }

    /// Writes a backup and prunes old ones. Never for test stores.
    @discardableResult
    func backUp() -> URL? {
        guard !Store.isOverridden || ProcessInfo.processInfo.environment["APP_BACKUP_FOLDER"] != nil else { return nil }
        let folder = ProcessInfo.processInfo.environment["APP_BACKUP_FOLDER"].map { URL(fileURLWithPath: $0) } ?? backupFolder
        return try? Backups.write(BudgieExport.data(from: container.mainContext), to: folder, retentionDays: backupRetentionDays)
    }

    func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.backupFolder = url.path(percentEncoded: false)
        try? container.mainContext.save()
    }

    /// Asks, then replaces all data with the backup, without a relaunch.
    func restore(_ backup: Backups.Backup) {
        guard let window = NSApp.keyWindow ?? NSApp.mainAppWindow else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore the Backup from \(backup.date.formatted(date: .abbreviated, time: .shortened))?"
        alert.informativeText = "All data in BudgieMac is replaced with this backup. BudgieMac backs up what you have now first, so you can go back."
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let restore = alert.addButton(withTitle: "Restore")
        restore.hasDestructiveAction = true
        restore.keyEquivalent = ""
        alert.beginSheetModal(for: window) { response in
            guard response == .alertSecondButtonReturn else { return }
            _ = try? self.restoreNow(backup.url)
        }
    }

    /// The restore itself: a backup of the current data, then replace all.
    @discardableResult
    func restoreNow(_ url: URL) throws -> BudgieImport.Summary {
        backUp()
        let package = try BudgieImport.read(Data(contentsOf: url))
        let summary = try BudgieImport.replaceAll(in: container.mainContext, with: package)
        sidebar = .page(.accounts)
        selectedTransactions = []
        return summary
    }
}

/// View > Accounts: the shortcuts from Settings > Shortcuts (S-050).
struct AccountShortcutCommands: View {
    let model: AppModel
    @Query private var preferences: [Preferences]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]

    var body: some View {
        let shortcuts = preferences.first?.accountShortcuts ?? []
        ForEach(shortcuts, id: \.self) { shortcut in
            if let account = accounts.first(where: { $0.uuid == shortcut.accountUUID }), let key = shortcut.key.first {
                Button(account.name) { model.sidebar = .account(account.uuid) }
                    .keyboardShortcut(KeyEquivalent(key), modifiers: shortcut.ctrl ? .control : [])
            }
        }
    }
}
