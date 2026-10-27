import BudgieMacKit
import SwiftData
import SwiftUI

/// Which transaction sheet is open: adding to an account, or editing one transaction.
enum TransactionSheetMode: Identifiable, Hashable {
    case add(account: UUID)
    case edit(PersistentIdentifier)

    var id: Self { self }
}

/// S-006 (Add Transaction) and S-007 (Edit Transaction): one sheet for both.
struct TransactionSheet: View {
    let mode: TransactionSheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Category> { !$0.deleted }) private var categories: [Category]
    @State private var draft = TransactionDraft()
    @State private var problem: TransactionDraft.Problem?
    @State private var loaded = false
    @FocusState private var payeeFocused: Bool

    private var editing: Transaction? {
        if case .edit(let id) = mode { return context.model(for: id) as? Transaction }
        return nil
    }

    var body: some View {
        Form {
            if let editing {
                EditWarnings(transaction: editing)
            }
            Section {
                DatePicker("Date", selection: $draft.date, displayedComponents: .date)
                    // Days are stored at midnight UTC; show them in UTC so they never shift.
                    .environment(\.timeZone, TimeZone(identifier: "UTC")!)
                if draft.isFarFromToday {
                    Label("That's more than a year from today.", systemImage: "calendar.badge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                TextField("Payee", text: $draft.payee, prompt: Text("Corner Grocer, Amazon…"))
                    .focused($payeeFocused)
                Picker("Category", selection: $draft.category) {
                    Text("None").tag(Category?.none)
                    ForEach(categories.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { category in
                        Text(category.path).tag(Category?.some(category))
                    }
                }
            }
            Section {
                TextField("Withdrawal", text: $draft.withdrawal, prompt: Text("0.00"))
                    .onChange(of: draft.withdrawal) { _, new in
                        if !new.isEmpty { draft.deposit = "" }
                        problem = nil
                    }
                TextField("Deposit", text: $draft.deposit, prompt: Text("0.00"))
                    .onChange(of: draft.deposit) { _, new in
                        if !new.isEmpty { draft.withdrawal = "" }
                        problem = nil
                    }
                if let problem {
                    Label(problem.message, systemImage: "exclamationmark.circle")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            Section {
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...)
                Toggle("Cleared", isOn: $draft.cleared)
                    .disabled(editing?.reconciled == true)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "Add Transaction" : "Edit Transaction")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Transaction" : "Save", action: save)
            }
        }
        .frame(width: 440)
        .fitsContent()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing { draft = TransactionDraft(editing) }
            payeeFocused = true
        }
    }

    private func save() {
        do {
            switch mode {
            case .add(let uuid):
                guard let account = try context.fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.uuid == uuid })).first else { return }
                try model.addTransaction(draft, to: account, undoManager: undoManager)
            case .edit:
                guard let editing else { return }
                try model.edit(editing, with: draft, undoManager: undoManager)
            }
            dismiss()
        } catch let error as TransactionDraft.Problem {
            problem = error
        } catch {}
    }
}

/// S-007: what else an edit changes, shown at the top of the sheet.
private struct EditWarnings: View {
    let transaction: Transaction
    @Environment(\.modelContext) private var context

    var body: some View {
        let reconciledOn = transaction.reconciled ? transaction.account?.lastReconciled : nil
        let partner = Transfers.partner(of: transaction, in: context)
        if reconciledOn != nil || partner != nil {
            Section {
                if let reconciledOn {
                    Label("This transaction is reconciled. Changing the amount or account will unbalance the reconciliation of \(reconciledOn.formatted(Self.day)).",
                          systemImage: "lock")
                }
                if let name = partner?.account?.name {
                    Label("Changes also apply to the matching transfer in \(name).", systemImage: "arrow.left.arrow.right")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private static let day = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)
}
