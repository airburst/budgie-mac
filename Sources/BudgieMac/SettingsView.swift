import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// The Settings window (⌘,). One tab per topic, each a grouped Form that
/// sizes to its content.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Query private var importRules: [ImportRule]

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.settingsTab) {
            ForEach(SettingsTab.allCases) { tab in
                page(tab)
                    .tabItem { Label(tab.title, systemImage: tab.symbol) }
                    .tag(tab)
            }
        }
        .modelContainer(model.container)
        .noInitialFocus()
    }

    @ViewBuilder
    private func page(_ tab: SettingsTab) -> some View {
        Form {
            switch tab {
            case .general: GeneralSettings()
            case .appearance: AppearanceSettings()
            case .shortcuts: ShortcutSettings()
            case .backups: BackupSettings()
            case .importRules: ImportRuleSettings()
            }
        }
        .formStyle(.grouped)
        .modifier(TabSizing(scrolls: tab == .shortcuts || (tab == .importRules && !importRules.isEmpty)))
    }
}

/// Tabs fit their content; the long shortcut and rule lists scroll in a fixed
/// height, so searching rules doesn't resize the window.
private struct TabSizing: ViewModifier {
    let scrolls: Bool

    func body(content: Content) -> some View {
        if scrolls {
            content.frame(width: 560, height: 520)
        } else {
            content.fitsContent().frame(width: 560)
        }
    }
}

/// The Settings tabs. Snapshot mode walks through every case.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, backups, importRules

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Accent"
        case .shortcuts: "Shortcuts"
        case .backups: "Backups"
        case .importRules: "Import Rules"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .shortcuts: "keyboard"
        case .backups: "externaldrive"
        case .importRules: "tray.and.arrow.down"
        }
    }
}

/// S-052: Appearance, Open on Launch, and payee autofill. Each applies at once.
struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Query private var preferences: [Preferences]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]

    var body: some View {
        Section {
            Picker("Appearance", selection: binding(\.appearance)) {
                ForEach(Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Open on Launch", selection: binding(\.startupPage)) {
                Text("All Accounts").tag(String?.none)
                ForEach(SidebarItem.allCases.filter { $0 != .accounts }) { Text($0.title).tag(String?.some($0.rawValue)) }
                if !accounts.isEmpty {
                    Divider()
                    ForEach(accounts) { Text($0.name).tag(String?.some(StartPage.account($0.uuid).text)) }
                }
            }
        }
        Section {
            Toggle("Fill in category and amount from payee", isOn: binding(\.autofillPayees))
        } footer: {
            Text("When you pick a known payee in a transaction, its default category and amount fill in any empty fields.")
                .font(.caption).foregroundStyle(.secondary)
        }
        UpdateSettings()
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<Preferences, Value>) -> Binding<Value> {
        Binding(get: { (preferences.first ?? Preferences())[keyPath: keyPath] },
                set: { value in
                    let context = model.container.mainContext
                    Preferences.current(in: context)[keyPath: keyPath] = value
                    try? context.save()
                    model.applyAppearance()
                })
    }
}

/// Update checks: on or off, when the last one ran, and one now.
private struct UpdateSettings: View {
    @Bindable private var updates = UpdateChecker.shared

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $updates.automatic)
            LabeledContent("Last Checked") {
                HStack(spacing: Space.sm) {
                    Text(updates.lastChecked.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    Button("Check Now") { updates.checkNow() }
                        .disabled(updates.checking)
                }
            }
        } footer: {
            Text("At launch, BudgieMac asks GitHub for the latest version and tells you when there's a newer one. Nothing about you or your budget is sent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// S-050: the built-in shortcuts, and keys that open accounts.
struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model
    @Query private var preferences: [Preferences]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @State private var recordingFor: Account?

    private var saved: [AccountShortcut] { preferences.first?.accountShortcuts ?? [] }

    var body: some View {
        Section("Account Shortcuts") {
            if saved.isEmpty {
                Text("Give an account a key, like ⌃1, to open it from anywhere in BudgieMac.")
                    .foregroundStyle(.secondary)
            }
            ForEach(saved, id: \.self) { shortcut in
                LabeledContent(accounts.first { $0.uuid == shortcut.accountUUID }?.name ?? "Closed account") {
                    HStack {
                        Text(Self.keys(shortcut).symbols).monospaced()
                        Button("Remove", systemImage: "minus.circle") { model.setShortcut(nil, for: shortcut.accountUUID) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remove this shortcut")
                    }
                }
            }
            Menu("Add Shortcut…") {
                ForEach(accounts.filter { account in !saved.contains { $0.accountUUID == account.uuid } }) { account in
                    Button(account.name) { recordingFor = account }
                }
            }
            .disabled(accounts.count == saved.count)
        }
        Section("Built In") {
            ForEach(Shortcuts.builtIn, id: \.symbols) { shortcut in
                LabeledContent(shortcut.title) { Text(shortcut.symbols).monospaced().foregroundStyle(.secondary) }
            }
        }
        .sheet(item: $recordingFor) { account in
            ShortcutRecorder(account: account, taken: saved.filter { $0.accountUUID != account.uuid }.map { shortcut in
                var keys = Self.keys(shortcut)
                keys.title = accounts.first { $0.uuid == shortcut.accountUUID }?.name ?? "another account"
                return keys
            })
        }
    }

    /// Account shortcuts use ⌃ and a key (Budgie's `ctrl` flag).
    static func keys(_ shortcut: AccountShortcut) -> KeyShortcut {
        KeyShortcut(shortcut.key, shortcut.ctrl ? .control : [], "")
    }
}

/// Press a key with ⌃ to record it; clashes are refused with a reason.
private struct ShortcutRecorder: View {
    let account: Account
    let taken: [KeyShortcut]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pressed: KeyShortcut?
    @FocusState private var focused: Bool

    var body: some View {
        let problem = pressed.flatMap { Shortcuts.problem(with: $0, accountShortcuts: taken) }
        VStack(spacing: Space.lg) {
            Text("Press a key with ⌃ to open “\(account.name)”").font(.headline)
            Text(pressed?.symbols ?? "⌃ …")
                .font(.largeTitle.monospaced())
                .frame(minWidth: 160, minHeight: 64)
                .background(.quaternary, in: .rect(cornerRadius: Space.sm))
                .focusable()
                .focused($focused)
                .onKeyPress(phases: .down) { press in
                    guard let character = press.characters.first, !character.isWhitespace else { return .ignored }
                    var modifiers: KeyShortcut.Modifiers = []
                    if press.modifiers.contains(.control) { modifiers.insert(.control) }
                    if press.modifiers.contains(.option) { modifiers.insert(.option) }
                    if press.modifiers.contains(.command) { modifiers.insert(.command) }
                    if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
                    pressed = KeyShortcut(String(press.key.character), modifiers, account.name)
                    return .handled
                }
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(Palette.moneyOut).font(.callout)
            } else if pressed != nil, pressed?.modifiers != .control {
                Label("Account shortcuts use ⌃ with a key.", systemImage: "info.circle").foregroundStyle(.secondary).font(.callout)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let pressed { model.setShortcut(AccountShortcut(key: pressed.key, ctrl: true, accountUUID: account.uuid), for: account.uuid) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pressed == nil || problem != nil || pressed?.modifiers != .control)
            }
        }
        .padding(Space.xxl)
        .onAppear { focused = true }
    }
}

/// S-054: where backups go, how long they're kept, and restoring one.
struct BackupSettings: View {
    @Environment(AppModel.self) private var model
    @Query private var preferences: [Preferences]
    @State private var backups: [Backups.Backup] = []

    var body: some View {
        let folder = model.backupFolder
        Section {
            LabeledContent("Folder") {
                HStack {
                    Text(folder.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button("Choose…") { model.chooseBackupFolder() }
                }
            }
            Stepper("Keep backups for \(model.backupRetentionDays) days", value: Binding(
                get: { model.backupRetentionDays },
                set: { days in
                    let context = model.container.mainContext
                    Preferences.current(in: context).backupRetentionDays = days
                    try? context.save()
                }), in: 1...365)
            Button("Back Up Now") {
                model.backUp()
                refresh()
            }
        } footer: {
            Text("BudgieMac backs up when you quit. Backups are Budgie data files, so Budgie can open them too.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Backups") {
            if backups.isEmpty {
                Text("No backups yet.").foregroundStyle(.secondary)
            }
            ForEach(backups) { backup in
                LabeledContent {
                    HStack {
                        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([backup.url]) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                        Button("Restore…") { model.restore(backup) }
                    }
                } label: {
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                    Text(ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: preferences.first?.backupFolder) { _, _ in refresh() }
    }

    private func refresh() { backups = Backups.list(model.backupFolder) }
}
