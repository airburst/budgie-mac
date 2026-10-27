import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

/// Everything a person can do to scheduled transactions (S-026 to S-030).
extension AppModel {
    func save(_ draft: ScheduleDraft, editing: ScheduledTransaction?, undoManager: UndoManager?) {
        let context = container.mainContext
        if let editing {
            let before = ScheduleDraft(editing)
            try? draft.apply(to: editing)
            undoManager?.registerUndo(withTarget: self) { model in model.save(before, editing: editing, undoManager: undoManager) }
            undoManager?.setActionName("Edit Scheduled Transaction")
        } else if let schedule = try? draft.make(in: context) {
            undoManager?.registerUndo(withTarget: self) { _ in
                context.delete(schedule)
                try? context.save()
            }
            undoManager?.setActionName("Add Scheduled Transaction")
        }
        try? context.save()
    }

    func setActive(_ schedule: ScheduledTransaction, _ active: Bool, undoManager: UndoManager?) {
        schedule.active = active
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in model.setActive(schedule, !active, undoManager: undoManager) }
        undoManager?.setActionName(active ? "Resume" : "Pause")
    }

    /// S-028: records the sheet's transaction and moves the schedule on.
    func record(_ schedule: ScheduledTransaction, as draft: TransactionDraft) throws(TransactionDraft.Problem) {
        try Scheduling.record(schedule, as: draft, in: container.mainContext)
        try? container.mainContext.save()
    }

    /// S-029: asks, naming the skipped date and the next one.
    func skip(_ schedule: ScheduledTransaction) {
        guard let window = NSApp.mainAppWindow, let due = schedule.nextDueDate else { return }
        let next = schedule.occurrences(through: Day.calendar.date(byAdding: .year, value: 6, to: due)!).dropFirst().first
        let alert = NSAlert()
        alert.messageText = "Skip “\(schedule.payee)” on \(Day.formatted(due, .abbreviated))?"
        alert.informativeText = next.map { "Nothing is recorded. It will next be due on \(Day.formatted($0, .abbreviated))." }
            ?? "Nothing is recorded. This was its last date, so the scheduled transaction ends."
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Scheduling.skip(schedule, in: self.container.mainContext)
            try? self.container.mainContext.save()
        }
    }

    /// S-030: asks, naming it. What it already recorded stays.
    func deleteSchedule(_ schedule: ScheduledTransaction) {
        Confirm.destructive("Delete the Scheduled Transaction “\(schedule.payee)”?",
                            message: "Transactions it already recorded stay in their registers.",
                            button: "Delete") {
            self.container.mainContext.delete(schedule)
            try? self.container.mainContext.save()
        }
    }

    /// S-033: at launch, auto-post schedules record themselves.
    func autoPostScheduled() {
        let context = container.mainContext
        if Scheduling.autoPost(in: context) > 0 { try? context.save() }
    }
}
