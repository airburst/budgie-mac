import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

enum EnvelopeSheetMode: Identifiable, Hashable {
    case add
    case edit(PersistentIdentifier)

    var id: Self { self }
}

/// S-038 Add Envelope and S-039 Edit Envelope: a name and the categories it tracks.
struct EnvelopeSheet: View {
    let mode: EnvelopeSheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query private var envelopes: [Envelope]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @State private var name = ""
    @State private var chosen = Set<PersistentIdentifier>()
    @State private var original: (String, Set<PersistentIdentifier>) = ("", [])
    @State private var loaded = false

    private var editing: Envelope? {
        if case .edit(let id) = mode { return envelopes.first { $0.persistentModelID == id } }
        return nil
    }

    private var changed: Bool { name != original.0 || chosen != original.1 }

    var body: some View {
        let others = envelopes.filter { $0 !== editing && $0.active }
        let budgetable = categories.filter { $0.kind != .income }
        Form {
            TextField("Name", text: $name, prompt: Text("Groceries, Bills…"))
            Section("Categories") {
                ForEach(CategoryTree.nodes(budgetable)) { node in
                    categoryToggle(node.category, others: others)
                    ForEach(node.children ?? []) { child in
                        categoryToggle(child.category, others: others)
                            .padding(.leading, Space.xl)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "Add Envelope" : "Edit Envelope")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Envelope" : "Save") {
                    let picked = categories.filter { chosen.contains($0.persistentModelID) }
                    model.saveEnvelope(name: name, categories: picked, editing: editing, undoManager: undoManager)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(width: 420, height: 560)
        .interactiveDismissDisabled(changed)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing {
                name = editing.name
                chosen = Set(editing.categories.compactMap { $0.category?.persistentModelID })
            }
            original = (name, chosen)
        }
    }

    /// Categories in another envelope are off, and say which.
    private func categoryToggle(_ category: Category, others: [Envelope]) -> some View {
        let owner = Envelopes.owner(of: category, in: others)
        return Toggle(isOn: Binding(
            get: { chosen.contains(category.persistentModelID) },
            set: { on in if on { chosen.insert(category.persistentModelID) } else { chosen.remove(category.persistentModelID) } })) {
            HStack {
                Text(category.name)
                if let owner {
                    Text("In \(owner.name)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(owner != nil)
    }

    /// Closing with edits asks "Discard changes?" (S-039).
    private func cancel() {
        guard changed, let window = NSApp.keyWindow else { dismiss(); return }
        let alert = NSAlert()
        alert.messageText = "Discard Changes?"
        alert.informativeText = "Your changes to this envelope will be lost."
        alert.addButton(withTitle: "Keep Editing")
        let discard = alert.addButton(withTitle: "Discard Changes")
        discard.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { dismiss() }
        }
    }
}

/// S-041: From, To, Amount and Notes. Move is off until From ≠ To and Amount > 0.
struct MoveMoneySheet: View {
    let envelopes: [Envelope]
    let month: String
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @State private var from: Envelope?
    @State private var to: Envelope?
    @State private var amount = ""
    @State private var notes = ""

    private var parsed: Decimal? { Money.parse(amount).flatMap { $0 > 0 ? $0 : nil } }

    var body: some View {
        Form {
            Picker("From", selection: $from) {
                Text("Choose…").tag(Envelope?.none)
                ForEach(envelopes) { Text($0.name).tag(Envelope?.some($0)) }
            }
            Picker("To", selection: $to) {
                Text("Choose…").tag(Envelope?.none)
                ForEach(envelopes) { Text($0.name).tag(Envelope?.some($0)) }
            }
            TextField("Amount", text: $amount, prompt: Text("0.00"))
            TextField("Notes", text: $notes, prompt: Text("Optional"))
        }
        .formStyle(.grouped)
        .navigationTitle("Move Money")
        .navigationSubtitle(Budget.title(of: month))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Move") {
                    if let from, let to, let parsed {
                        model.moveMoney(parsed, from: from, to: to, in: month, notes: notes, undoManager: undoManager)
                    }
                    dismiss()
                }
                .disabled(from == nil || to == nil || from === to || parsed == nil)
            }
        }
        .frame(width: 380)
        .fitsContent()
    }
}

/// Everything a person can do to the budget (S-037 to S-043), with Undo.
extension AppModel {
    func assign(_ amount: Decimal, to envelope: Envelope, in month: String, undoManager: UndoManager?) {
        let context = container.mainContext
        let before = Budget.assigned(to: envelope, in: month) ?? 0
        Budget.assign(amount, to: envelope, in: month, context: context)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { model in model.assign(before, to: envelope, in: month, undoManager: undoManager) }
        undoManager?.setActionName("Assign")
    }

    func moveMoney(_ amount: Decimal, from: Envelope, to: Envelope, in month: String, notes: String, undoManager: UndoManager?) {
        let context = container.mainContext
        guard let move = Budget.move(amount, from: from, to: to, in: month, notes: notes.isEmpty ? nil : notes, context: context) else { return }
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { _ in
            context.delete(move)
            try? context.save()
        }
        undoManager?.setActionName("Move Money")
    }

    /// S-042: a normal confirmation (not destructive), then fills empty envelopes.
    func copyLastMonth(into month: String, envelopes: [Envelope]) {
        guard let window = NSApp.mainAppWindow else { return }
        let previous = Budget.month(month, adding: -1)
        let alert = NSAlert()
        alert.messageText = "Copy \(Budget.title(of: previous)) into \(Budget.title(of: month))?"
        alert.informativeText = "Envelopes with nothing assigned this month get last month's amount. Envelopes you've already assigned stay as they are."
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Budget.copyLastMonth(into: month, envelopes: envelopes, context: self.container.mainContext)
            try? self.container.mainContext.save()
        }
    }

    func applyTemplate(_ template: Envelopes.Template, categories: [Category]) {
        Envelopes.apply(template, categories: categories, context: container.mainContext)
        try? container.mainContext.save()
    }

    func saveEnvelope(name: String, categories: [Category], editing: Envelope?, undoManager: UndoManager?) {
        let context = container.mainContext
        let all = (try? context.fetch(FetchDescriptor<Envelope>())) ?? []
        let envelope: Envelope
        if let editing {
            envelope = editing
            envelope.name = name.trimmingCharacters(in: .whitespaces)
            envelope.updatedAt = .now
        } else {
            envelope = Envelope(name: name.trimmingCharacters(in: .whitespaces), sortOrder: (all.map(\.sortOrder).max() ?? -1) + 1)
            context.insert(envelope)
        }
        Envelopes.setCategories(categories, for: envelope, all: all, context: context)
        try? context.save()
    }

    /// S-039: asks; frees its categories and keeps past months' totals.
    func deleteEnvelope(_ envelope: Envelope) {
        Confirm.destructive("Delete the Envelope “\(envelope.name)”?",
                            message: "Its categories become free for other envelopes. Past months keep their totals.",
                            button: "Delete") {
            Envelopes.delete(envelope, context: self.container.mainContext)
            try? self.container.mainContext.save()
        }
    }

    func reorder(_ envelopes: [Envelope], undoManager: UndoManager?) {
        let before = envelopes.sorted { $0.sortOrder < $1.sortOrder }
        Envelopes.reorder(envelopes)
        try? container.mainContext.save()
        undoManager?.registerUndo(withTarget: self) { model in model.reorder(before, undoManager: undoManager) }
        undoManager?.setActionName("Reorder Envelopes")
    }
}
