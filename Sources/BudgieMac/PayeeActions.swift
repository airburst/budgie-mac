import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// Everything a person can do to payees (S-019, S-020).
extension AppModel {
    func add(_ draft: PayeeDraft, undoManager: UndoManager?) {
        let context = container.mainContext
        let payee = PayeeEditing.add(draft, in: context)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { _ in
            context.delete(payee)
            try? context.save()
        }
        undoManager?.setActionName("Add Payee")
    }

    /// A new name asks whether past transactions should change too.
    func save(_ draft: PayeeDraft, to payee: Payee, undoManager: UndoManager?) {
        let context = container.mainContext
        let used = PayeeEditing.transactions(named: payee.name, in: context).count
        guard draft.cleanName != payee.name, used > 0, let window = NSApp.mainAppWindow else {
            finishSave(draft, to: payee, updating: false)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Also Rename \(Words.count(used, "Past Transaction").capitalized)?"
        alert.informativeText = "\(Words.count(used, "transaction")) say “\(payee.name)”. They can say “\(draft.cleanName)” instead."
        alert.addButton(withTitle: "Rename Transactions")
        alert.addButton(withTitle: "Keep Old Name")
        alert.beginSheetModal(for: window) { response in
            self.finishSave(draft, to: payee, updating: response == .alertFirstButtonReturn)
        }
    }

    private func finishSave(_ draft: PayeeDraft, to payee: Payee, updating: Bool) {
        let context = container.mainContext
        PayeeEditing.save(draft, to: payee, updatingTransactions: updating, in: context)
        try? context.save()
    }

    /// Asks, naming the payee. Past transactions keep the text. Undo brings it back.
    func deletePayee(_ payee: Payee, undoManager: UndoManager?) {
        Confirm.destructive("Delete the Payee “\(payee.name)”?",
                            message: "Past transactions keep the name “\(payee.name)”.",
                            button: "Delete") {
            let context = self.container.mainContext
            let draft = PayeeDraft(payee)
            context.delete(payee)
            try? context.save()
            undoManager?.registerUndo(withTarget: self) { model in
                model.add(draft, undoManager: nil)
            }
            undoManager?.setActionName("Delete Payee")
        }
    }
}
