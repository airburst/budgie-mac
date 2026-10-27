import BudgieMacKit
import SwiftData
import SwiftUI

/// Which account sheet is open.
enum AccountSheetMode: Identifiable, Hashable {
    case add
    case edit(UUID)

    var id: Self { self }
}

/// S-004 Add Account (File > New Account…, ⇧⌘N) and S-010 Edit Account
/// (Account > Edit Account…, ⌥⌘E). Type and opening balance are fixed after adding.
struct AccountSheet: View {
    let mode: AccountSheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Account> { !$0.deleted }) private var accounts: [Account]
    @State private var draft = AccountDraft()
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var editing: Account? {
        guard case .edit(let uuid) = mode else { return nil }
        return accounts.first { $0.uuid == uuid }
    }

    /// Currencies offered: the draft's own plus the common ones, by code.
    private var currencies: [String] {
        Array(Set(["GBP", "EUR", "USD", draft.currency])).sorted()
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Current Account, Visa…"))
                    .focused($nameFocused)
                if let duplicate = draft.duplicateName(among: accounts.filter { $0 !== editing }.map(\.name)) {
                    Label("Another account is already called “\(duplicate)”.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let editing {
                    LabeledContent("Type", value: editing.type.title)
                } else {
                    Picker("Type", selection: $draft.type) {
                        ForEach(AccountType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                TextField("Account Number (optional)", text: $draft.number)
            }
            Section {
                if let editing {
                    LabeledContent("Opening Balance", value: Money.string(editing.openingBalance, currency: editing.currency))
                } else {
                    TextField("Opening Balance", text: $draft.openingBalance, prompt: Text("0.00"))
                }
                Picker("Currency", selection: $draft.currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text("\(code) – \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
                if draft.type == .creditCard {
                    TextField("Credit Limit", text: $draft.creditLimit, prompt: Text("Optional"))
                }
                TextField("Interest Rate (%)", text: $draft.interestRate, prompt: Text("Optional"))
            } footer: {
                Text("Type and opening balance can't be changed after adding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "Add Account" : "Edit Account")
        .toolbar {
            if let editing {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Close Account…", role: .destructive) {
                        dismiss()
                        model.closeAccount(editing, undoManager: undoManager)
                    }
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add Account" : "Save") {
                    if let editing {
                        model.save(draft, to: editing, undoManager: undoManager)
                    } else {
                        model.add(draft, undoManager: undoManager)
                    }
                    dismiss()
                }
                .disabled(!draft.canAdd())
            }
        }
        .frame(width: 420)
        .fitsContent()
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing { draft = AccountDraft(editing) }
            nameFocused = true
        }
    }
}
