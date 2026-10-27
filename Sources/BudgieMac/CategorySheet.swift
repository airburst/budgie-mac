import BudgieMacKit
import SwiftData
import SwiftUI

enum CategorySheetMode: Identifiable, Hashable {
    /// A top-level category, or a sub-category under the given parent.
    case add(parent: PersistentIdentifier?)
    case edit(PersistentIdentifier)

    var id: Self { self }
}

/// S-016 Add Category / Add Sub-category, S-017 Edit Category.
struct CategorySheet: View {
    let mode: CategorySheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query private var categories: [Category]
    @State private var draft = CategoryDraft()
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var editing: Category? {
        if case .edit(let id) = mode { return categories.first { $0.persistentModelID == id } }
        return nil
    }

    private var title: String {
        if editing != nil { return "Edit Category" }
        return draft.parent == nil ? "Add Category" : "Add Sub-category"
    }

    var body: some View {
        let problem = draft.problem(among: categories, editing: editing)
        Form {
            if let parent = draft.parent {
                LabeledContent("Parent", value: parent.name)
            }
            TextField("Name", text: $draft.name)
                .focused($nameFocused)
            if case .duplicate = problem {
                Label(problem?.message ?? "", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Picker("Type", selection: $draft.kind) {
                Text("Expense").tag(CategoryKind.expense)
                Text("Income").tag(CategoryKind.income)
                Text("Transfer").tag(CategoryKind.transfer)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? title : "Save") {
                    if model.save(draft, editing: editing, undoManager: undoManager) { dismiss() }
                }
                .disabled(problem != nil)
            }
        }
        .frame(width: 380)
        .fitsContent()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            switch mode {
            case .edit:
                if let editing { draft = CategoryDraft(editing) }
            case .add(let parentID):
                draft = CategoryDraft(parent: parentID.flatMap { id in categories.first { $0.persistentModelID == id } })
            }
            nameFocused = true
        }
    }
}
