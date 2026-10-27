import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// Everything a person can do to transactions, each with its Undo:
/// new and edit (S-006, S-007), delete (S-008), and clearing (S-009).
extension AppModel {
    /// Transaction > Edit Transaction… (⌘E) for the one selected row.
    var canEditTransaction: Bool { openAccount != nil && selectedTransactions.count == 1 }

    func editSelectedTransaction() {
        if canEditTransaction, let id = selectedTransactions.first { transactionSheet = .edit(id) }
    }

    /// File > New Transaction (⌘N), the toolbar +, or the empty state.
    func newTransaction() {
        if let openAccount { transactionSheet = .add(account: openAccount) }
    }

    /// Adds the transaction, selects it, and offers "Undo Add Transaction".
    @discardableResult
    func addTransaction(_ draft: TransactionDraft, to account: Account, undoManager: UndoManager?) throws(TransactionDraft.Problem) -> Transaction {
        let context = container.mainContext
        let transaction = try draft.add(to: account, in: context)
        // S-024: a row added while reconciling arrives ticked.
        let tick = reconcileFor == account.uuid && transaction.date <= (account.pendingReconcileDate ?? .distantPast)
        if tick { transaction.cleared = true }
        try? context.save()
        // After the save: saving swaps a new row's temporary id for its permanent one.
        if tick { reconcileTicked.insert(transaction.persistentModelID) }
        selectedTransactions = [transaction.persistentModelID]
        undoManager?.registerUndo(withTarget: self) { model in
            model.selectedTransactions.remove(transaction.persistentModelID)
            context.delete(transaction)
            try? context.save()
        }
        undoManager?.setActionName("Add Transaction")
        return transaction
    }

    /// Saves the sheet into the transaction (and its transfer partner), and
    /// offers "Undo Edit Transaction".
    func edit(_ transaction: Transaction, with draft: TransactionDraft, undoManager: UndoManager?) throws(TransactionDraft.Problem) {
        let context = container.mainContext
        let before = TransactionValues(transaction)
        let partner = Transfers.partner(of: transaction, in: context)
        let partnerBefore = partner.map(TransactionValues.init)
        try draft.apply(to: transaction, in: context)
        Transfers.syncPartner(of: transaction, in: context)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { _ in
            before.restore(transaction, in: context)
            if let partner, let partnerBefore { partnerBefore.restore(partner, in: context) }
            try? context.save()
        }
        undoManager?.setActionName("Edit Transaction")
    }
}

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

    /// Asks first, with Cancel as the default (UI/Confirm.swift).
    private func confirmDelete(_ transactions: [Transaction], reconciled: [Transaction], undoManager: UndoManager?) {
        let title: String
        if transactions.count == 1, let one = transactions.first {
            let currency = one.account?.currency ?? "GBP"
            title = "Delete the Reconciled Transaction “\(one.payee)”, \(Day.formatted(one.date, .abbreviated)), \(Money.string(one.amount, currency: currency))?"
        } else {
            title = "Delete \(transactions.count) Transactions, Including \(reconciled.count) Reconciled?"
        }
        let accounts = Set(reconciled.compactMap { $0.account?.name }).sorted()
        Confirm.destructive(title, message: "This changes the reconciled balance of \(accounts.formatted(.list(type: .and))).",
                            button: "Delete") { self.delete(transactions, undoManager: undoManager) }
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
        let rows = selectedTransactionRows
        return rows.isEmpty || Clearing.willClear(rows) ? "Mark as Cleared" : "Mark as Uncleared"
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
