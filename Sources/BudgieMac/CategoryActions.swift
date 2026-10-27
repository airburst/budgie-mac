import BudgieMacKit
import SwiftData
import SwiftUI

/// Everything a person can do to categories, each with its Undo (S-016, S-017).
extension AppModel {
    /// Adds or saves; false when the draft is refused.
    func save(_ draft: CategoryDraft, editing: Category?, undoManager: UndoManager?) -> Bool {
        let context = container.mainContext
        do {
            if let editing {
                let before = CategoryDraft(editing)
                try draft.apply(to: editing, in: context)
                undoManager?.registerUndo(withTarget: self) { model in
                    _ = model.save(before, editing: editing, undoManager: undoManager)
                }
                undoManager?.setActionName("Edit Category")
            } else {
                let category = try draft.add(in: context)
                undoManager?.registerUndo(withTarget: self) { _ in
                    context.delete(category)
                    try? context.save()
                }
                undoManager?.setActionName(draft.parent == nil ? "Add Category" : "Add Sub-category")
            }
            try? context.save()
            return true
        } catch {
            return false
        }
    }

    /// Asks first when transactions use it; they become uncategorised.
    func deleteCategory(_ category: Category, undoManager: UndoManager?) {
        guard CategoryDeletion.blocked(category) == nil else { return }
        let used = CategoryDeletion.usage(category)
        if used == 0 {
            setDeleted(category, undoManager: undoManager)
        } else {
            Confirm.destructive("Delete “\(category.name)”?",
                                message: "\(ImportFlow.count(used, "transaction")) use it and will become uncategorised.",
                                button: "Delete") { self.setDeleted(category, undoManager: undoManager) }
        }
    }

    func setDeleted(_ category: Category, undoManager: UndoManager?) {
        let context = container.mainContext
        let lost = CategoryDeletion.delete(category)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { _ in
            CategoryDeletion.restore(category, to: lost)
            try? context.save()
        }
        undoManager?.setActionName("Delete Category")
    }
}
