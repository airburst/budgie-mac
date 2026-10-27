import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// S-008: Delete key, Edit > Delete, or the context menu. Asks only when a
/// selected transaction is reconciled; otherwise Undo is the safety net.
extension AppModel {
    func deleteSelectedTransactions(undoManager: UndoManager?) {
        let selected = selectedTransactionRows
        guard !selected.isEmpty else { return }
        let reconciled = selected.filter(\.reconciled)
        if reconciled.isEmpty {
            delete(selected, undoManager: undoManager)
        } else {
            confirmDelete(selected, reconciled: reconciled, undoManager: undoManager)
        }
    }

    func delete(_ transactions: [Transaction], undoManager: UndoManager?) {
        let context = container.mainContext
        let count = transactions.count
        selectedTransactions.subtract(transactions.map(\.persistentModelID))
        let records = TransactionDeletion.delete(transactions, in: context)
        try? context.save()
        let name = count == 1 ? "Delete Transaction" : "Delete \(count) Transactions"
        registerRestore(records, name: name, undoManager: undoManager)
        AccessibilityNotification.Announcement(count == 1 ? "Transaction deleted" : "\(count) transactions deleted").post()
    }

    /// Undo recreates the transactions; Redo deletes them again.
    private func registerRestore(_ records: [TransactionDeletion.Record], name: String, undoManager: UndoManager?) {
        undoManager?.registerUndo(withTarget: self) { model in
            let context = model.container.mainContext
            let restored = TransactionDeletion.restore(records, in: context)
            try? context.save()
            undoManager?.registerUndo(withTarget: model) { model in
                model.delete(restored, undoManager: undoManager)
            }
            undoManager?.setActionName(name)
        }
        undoManager?.setActionName(name)
    }

    /// An NSAlert, so Cancel is the default and Return never deletes.
    private func confirmDelete(_ transactions: [Transaction], reconciled: [Transaction], undoManager: UndoManager?) {
        guard let window = NSApp.mainAppWindow else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if transactions.count == 1, let one = transactions.first {
            let currency = one.account?.currency ?? "GBP"
            let day = Day.formatted(one.date, .abbreviated)
            alert.messageText = "Delete the Reconciled Transaction “\(one.payee)”, \(day), \(Money.string(one.amount, currency: currency))?"
        } else {
            alert.messageText = "Delete \(transactions.count) Transactions, Including \(reconciled.count) Reconciled?"
        }
        let accounts = Set(reconciled.compactMap { $0.account?.name }).sorted()
        alert.informativeText = "This changes the reconciled balance of \(accounts.formatted(.list(type: .and)))."
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { self.delete(transactions, undoManager: undoManager) }
        }
    }
}

/// S-009: Mark as Cleared (⌘K), Space, or a click on the status icon.
extension AppModel {
    /// The selected rows that still exist. `model(for:)` would hand back a
    /// deleted row, and reading it crashes, so only registered, live rows count.
    var selectedTransactionRows: [Transaction] {
        let context = container.mainContext
        return selectedTransactions.compactMap { id -> Transaction? in
            guard let row: Transaction = context.registeredModel(for: id), !row.isDeleted, row.modelContext != nil else { return nil }
            return row
        }
    }

    /// "Mark as Cleared" when any selected row is uncleared, else "Mark as Uncleared".
    var clearingTitle: String {
        Clearing.willClear(selectedTransactionRows) ? "Mark as Cleared" : "Mark as Uncleared"
    }

    func toggleCleared(_ transactions: [Transaction], undoManager: UndoManager?) {
        let name = Clearing.willClear(transactions) ? "Mark as Cleared" : "Mark as Uncleared"
        let changed = Clearing.toggle(transactions)
        guard !changed.isEmpty else { return }
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in
            model.toggleCleared(changed, undoManager: undoManager)
        }
        undoManager?.setActionName(name)
    }
}

extension NSApplication {
    /// The main window, even while the app isn't active (snapshots, self-test).
    var mainAppWindow: NSWindow? {
        mainWindow ?? windows.first { $0.canBecomeMain && !$0.isSheet && $0.isVisible }
    }
}
