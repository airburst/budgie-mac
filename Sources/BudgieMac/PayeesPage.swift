import BudgieMacKit
import SwiftData
import SwiftUI

/// S-018: payees with their default category and amount.
struct PayeesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Payee.name) private var payees: [Payee]
    @State private var search = ""
    @State private var selection = Set<Payee.ID>()

    private var shown: [Payee] {
        let text = search.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? payees : payees.filter { $0.name.localizedStandardContains(text) }
    }

    var body: some View {
        Group {
            if payees.isEmpty {
                ContentUnavailableView {
                    Label("No Payees", systemImage: "person.2")
                } description: {
                    Text("Payees are added when you save a transaction. Add one here to give it a default category and amount.")
                } actions: {
                    Button("Add Payee…") { model.payeeSheet = .add }
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                table
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search Payees")
        .toolbar {
            ToolbarItem {
                Button("Add Payee", systemImage: "plus") { model.payeeSheet = .add }
                    .help("Add a payee")
            }
        }
        .sheet(item: Bindable(model).payeeSheet) { mode in
            NavigationStack { PayeeSheet(mode: mode) }
        }
        .navigationTitle("Payees")
    }

    private var table: some View {
        Table(shown, selection: $selection) {
            TableColumn("Name") { payee in
                Text(payee.name).lineLimit(1).help(payee.name)
            }
            .width(min: 160, ideal: 260)
            TableColumn("Default Category") { payee in
                if let category = payee.category {
                    CategoryPill(category: category)
                }
            }
            TableColumn("Default Amount") { payee in
                if let amount = payee.amount {
                    MoneyText(amount: amount, currency: Locale.current.currency?.identifier ?? "GBP")
                }
            }
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: Payee.ID.self) { ids in
            if let payee = payees.first(where: { ids.contains($0.id) }) {
                Button("Edit Payee…") { model.payeeSheet = .edit(payee.persistentModelID) }
                Divider()
                Button("Delete…", role: .destructive) { model.deletePayee(payee, undoManager: undoManager) }
            }
        } primaryAction: { ids in
            if let payee = payees.first(where: { ids.contains($0.id) }) { model.payeeSheet = .edit(payee.persistentModelID) }
        }
        .onDeleteCommand {
            if let payee = payees.first(where: { selection.contains($0.id) }) { model.deletePayee(payee, undoManager: undoManager) }
        }
    }
}

enum PayeeSheetMode: Identifiable, Hashable {
    case add
    case edit(PersistentIdentifier)

    var id: Self { self }
}

/// S-019: add a payee, or change its name, default category and amount.
struct PayeeSheet: View {
    let mode: PayeeSheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query private var payees: [Payee]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @State private var draft = PayeeDraft()
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var editing: Payee? {
        if case .edit(let id) = mode { return payees.first { $0.persistentModelID == id } }
        return nil
    }

    var body: some View {
        Form {
            TextField("Name", text: $draft.name)
                .focused($nameFocused)
            if let target = PayeeEditing.mergeTarget(for: draft, editing: editing, in: payees) {
                Label(editing == nil ? "There's already a payee called “\(target.name)”." : "Saving merges this payee into “\(target.name)”.",
                      systemImage: "arrow.triangle.merge")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Picker("Default Category", selection: $draft.category) {
                Text("None").tag(Category?.none)
                ForEach(Suggestions.categories(categories, matching: "")) { category in
                    Text(category.path).tag(Category?.some(category))
                }
            }
            TextField("Default Amount", text: $draft.amount, prompt: Text("-12.50 for money out"))
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "Add Payee" : "Edit Payee")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Payee" : "Save") {
                    if let editing {
                        model.save(draft, to: editing, undoManager: undoManager)
                    } else {
                        model.add(draft, undoManager: undoManager)
                    }
                    dismiss()
                }
                .disabled(!draft.isValid() || (editing == nil && PayeeEditing.mergeTarget(for: draft, editing: nil, in: payees) != nil))
            }
        }
        .frame(width: 400)
        .fitsContent()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing { draft = PayeeDraft(editing) }
            nameFocused = true
        }
    }
}
