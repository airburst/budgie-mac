import BudgieMacKit
import SwiftData
import SwiftUI

/// S-049: every command in a standard menu with its shortcut (see
/// `Shortcuts.builtIn` and docs/GLOSSARY.md), turned off when it can't apply.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Transaction") { model.newTransaction() }
                .keyboardShortcut("n")
                .disabled(model.openAccount == nil)
            Button("New Account…") { model.accountSheet = .add }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import Budgie Data…") { model.importFlow.chooseFile() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Budgie Data…") { model.exportData() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Divider()
            Button("Import QIF…") { model.chooseQifFile() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Register") { model.registerSearching = true }
                .keyboardShortcut("f")
                .disabled(model.openAccount == nil || model.forecastFor != nil)
        }

        CommandGroup(before: .sidebar) {
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, page in
                Button(page.title) { model.sidebar = .page(page) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            RegisterFilterCommands(model: model)
            Divider()
        }

        CommandMenu("Account") {
            AccountCommands(model: model)
        }
        CommandMenu("Transaction") {
            TransactionCommands(model: model)
        }
    }
}

/// View > Hide Reconciled / Hide Cleared, saved in Preferences (S-011).
private struct RegisterFilterCommands: View {
    let model: AppModel
    @Query private var preferences: [Preferences]

    var body: some View {
        Toggle("Hide Reconciled", isOn: binding(\.hideReconciled))
            .disabled(model.openAccount == nil)
        Toggle("Hide Cleared", isOn: binding(\.hideCleared))
            .disabled(model.openAccount == nil)
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { preferences.first?[keyPath: keyPath] ?? false },
                set: { on in
                    let context = model.container.mainContext
                    Preferences.current(in: context)[keyPath: keyPath] = on
                    try? context.save()
                })
    }
}

/// Transaction: Edit ⌘E, Mark as Cleared ⌘K, Delete ⌘⌫ (plain ⌫ works in the register).
private struct TransactionCommands: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let rows = model.selectedTransactionRows
        Button("Edit Transaction…") { model.editSelectedTransaction() }
            .keyboardShortcut("e")
            .disabled(!model.canEditTransaction)
        Button(model.clearingTitle) { model.toggleCleared(rows, undoManager: undoManager) }
            .keyboardShortcut("k")
            .disabled(model.openAccount == nil || rows.isEmpty || rows.allSatisfy(\.reconciled))
        Divider()
        Button(rows.count > 1 ? "Delete \(rows.count) Transactions" : "Delete Transaction") {
            model.deleteSelectedTransactions(undoManager: undoManager)
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(model.openAccount == nil || rows.isEmpty)
    }
}
