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
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @Query private var payees: [Payee]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @Query private var preferences: [Preferences]
    @State private var draft = TransactionDraft()
    /// What's typed in Category; it becomes `draft.category` when it names one.
    @State private var categoryText = ""
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
                    .environment(\.timeZone, Day.calendar.timeZone)
                if draft.isFarFromToday {
                    Label("That's more than a year from today.", systemImage: "calendar.badge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // S-013: known payees as suggestions; picking one fills in its defaults.
                TextField("Payee", text: $draft.payee, prompt: Text("Corner Grocer, Amazon…"))
                    .focused($payeeFocused)
                    .textInputSuggestions {
                        ForEach(Suggestions.payees(payees, matching: draft.payee)) { payee in
                            Text(payee.name).textInputCompletion(payee.name)
                        }
                    }
                    .onChange(of: draft.payee) { _, name in
                        if let payee = Suggestions.payee(named: name, in: payees), payee.name == name {
                            draft.fill(from: payee, autofill: preferences.first?.autofillPayees ?? true)
                            if let category = draft.category { categoryText = category.path }
                        }
                    }
                // S-012: type part of a category; matches show "Parent > Child".
                TextField("Category", text: $categoryText, prompt: Text("None"))
                    .textInputSuggestions {
                        ForEach(Suggestions.categories(categories, matching: categoryText).prefix(12)) { category in
                            Text(category.path).textInputCompletion(category.path)
                        }
                    }
                    .onChange(of: categoryText) { _, text in
                        draft.category = Suggestions.category(named: text, in: categories)
                    }
                if !categoryText.trimmingCharacters(in: .whitespaces).isEmpty, draft.category == nil {
                    Label("“\(categoryText.trimmingCharacters(in: .whitespaces))” will be added as a new category.", systemImage: "plus.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                // S-014: a transfer moves the money to or from another of your accounts.
                if let editing {
                    if let partner = Transfers.partner(of: editing, in: context), let name = partner.account?.name {
                        LabeledContent("Transfer", value: editing.amount < 0 ? "To \(name)" : "From \(name)")
                    }
                } else {
                    Picker("Transfer", selection: $draft.transferAccount) {
                        Text("None").tag(Account?.none)
                        ForEach(accounts.filter { $0.uuid != addingTo }) { account in
                            Text(account.name).tag(Account?.some(account))
                        }
                    }
                    .help("Move the money between this account and another of your accounts. A withdrawal goes to it; a deposit comes from it.")
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
            categoryText = draft.category?.path ?? ""
            payeeFocused = true
        }
    }

    private var addingTo: UUID? {
        if case .add(let uuid) = mode { uuid } else { nil }
    }

    private func save() {
        // A category name that matches nothing is added, as in Budgie.
        let typed = categoryText.trimmingCharacters(in: .whitespaces)
        if draft.category == nil, !typed.isEmpty, draft.amount().isSuccess {
            let category = Category(name: typed)
            context.insert(category)
            draft.category = category
        }
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
                    Label("This transaction is reconciled. Changing the amount or account will unbalance the reconciliation of \(Day.formatted(reconciledOn, .abbreviated)).",
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
}
