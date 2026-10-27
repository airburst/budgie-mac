import BudgieMacKit
import SwiftData
import SwiftUI

/// S-004: File > New Account… (⇧⌘N), the + under the sidebar, or the empty state.
struct AddAccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Account> { !$0.deleted }) private var accounts: [Account]
    @State private var draft = AccountDraft()
    @FocusState private var nameFocused: Bool

    /// Currencies offered: the draft's own plus the common ones, by code.
    private var currencies: [String] {
        Array(Set(["GBP", "EUR", "USD", draft.currency])).sorted()
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Current Account, Visa…"))
                    .focused($nameFocused)
                if let duplicate = draft.duplicateName(among: accounts.map(\.name)) {
                    Label("Another account is already called “\(duplicate)”.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Picker("Type", selection: $draft.type) {
                    ForEach(AccountType.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Account Number (optional)", text: $draft.number)
            }
            Section {
                TextField("Opening Balance", text: $draft.openingBalance, prompt: Text("0.00"))
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
        .navigationTitle("Add Account")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add Account") {
                    model.add(draft, undoManager: undoManager)
                    dismiss()
                }
                .disabled(!draft.canAdd())
            }
        }
        .frame(width: 420)
        .fitsContent()
        .onAppear { nameFocused = true }
    }
}
