import BudgieMacKit
import SwiftData
import SwiftUI

/// The account a Reconcile… sheet is for.
struct ReconcileTarget: Identifiable, Hashable {
    let account: UUID
    var id: UUID { account }
}

/// S-021: Reconcile… asks for the statement date and ending balance.
struct ReconcileStartSheet: View {
    let accountID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [Account]
    @State private var date = Day.today
    @State private var balance = ""
    @FocusState private var balanceFocused: Bool

    init(accountID: UUID) {
        self.accountID = accountID
        _accounts = Query(filter: #Predicate<Account> { $0.uuid == accountID })
    }

    private var parsed: Decimal? {
        balance.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Money.parse(balance)
    }

    var body: some View {
        Form {
            if let account = accounts.first {
                Section {
                    if let last = account.reconciliations.max(by: { $0.date < $1.date }) {
                        LabeledContent("Last Reconciled", value: "\(Day.formatted(last.date, .abbreviated)) · \(Money.string(last.balance, currency: account.currency))")
                    } else {
                        LabeledContent("Last Reconciled", value: "Never")
                    }
                }
                Section {
                    DatePicker("Statement Date", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, Day.calendar.timeZone)
                    TextField("Ending Balance", text: $balance, prompt: Text("From your statement"))
                        .focused($balanceFocused)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reconcile \(accounts.first?.name ?? "")")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    if let account = accounts.first, let parsed {
                        model.startReconcile(account, date: date, balance: parsed)
                        dismiss()
                    }
                }
                .disabled(parsed == nil)
            }
        }
        .frame(width: 400)
        .fitsContent()
        .onAppear {
            if let account = accounts.first, let pending = account.pendingReconcileBalance {
                balance = pending.formatted(.number.grouping(.never))
                date = account.pendingReconcileDate ?? date
            }
            balanceFocused = true
        }
    }
}

/// S-022 to S-024: tick transactions until the difference is zero, then Finish.
struct ReconcileView: View {
    let reconcile: Reconcile
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let account = reconcile.account
        let currency = account.currency
        let ticked = model.reconcileTicked
        let rows = reconcile.eligible
        let difference = reconcile.difference(ticked: ticked)
        VStack(spacing: 0) {
            HStack(spacing: Space.md) {
                Tile(title: "Opening Balance", value: Money.string(reconcile.openingBalance, currency: currency))
                Tile(title: "Cleared Balance", value: Money.string(reconcile.clearedBalance(ticked: ticked), currency: currency))
                Tile(title: "Statement Balance", value: Money.string(reconcile.statementBalance, currency: currency))
                Tile(title: "Difference", value: Money.string(difference, currency: currency),
                     note: difference == 0 ? "Balanced" : "Not balanced", highlight: difference == 0 ? Palette.moneyIn : Palette.moneyOut)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.margin)
            if model.reconcileAutoMatched {
                Label("Ticked \(Words.count(ticked.count, "transaction")) that add up to the statement.", systemImage: "wand.and.stars")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.margin)
                    .padding(.bottom, Space.sm)
            }
            Table(rows) {
                TableColumn("") { transaction in
                    Toggle("Matched", isOn: Binding(
                        get: { ticked.contains(transaction.persistentModelID) },
                        set: { model.setTicked(transaction, $0) }))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                .width(24)
                TableColumn("Date") { Text(Day.formatted($0.date)).monospacedDigit() }
                    .width(min: 80, ideal: 96)
                TableColumn("Payee") { Text($0.payee).lineLimit(1) }
                TableColumn("Category") { transaction in
                    if let category = transaction.category { CategoryPill(category: category) }
                }
                TableColumn("Amount") { MoneyText(amount: $0.amount, currency: currency) }
                    .width(min: 90, ideal: 110)
                    .alignment(.trailing)
            }
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if let id = ids.first {
                    Button("Edit Transaction…") { model.transactionSheet = .edit(id) }
                }
            } primaryAction: { ids in
                if let id = ids.first { model.transactionSheet = .edit(id) }
            }
            footer(difference: difference, count: ticked.count, currency: currency)
        }
        .navigationTitle("Reconcile \(account.name)")
        .navigationSubtitle("Statement \(Day.formatted(reconcile.statementDate)) · \(Money.string(reconcile.statementBalance, currency: currency))")
        .toolbar {
            ToolbarItemGroup {
                Button("Auto Balance", systemImage: "plusminus") {
                    model.transactionSheet = .adjust(account: account.uuid, amount: difference)
                }
                .disabled(difference == 0)
                .help("Add an adjustment for the difference")
                Button("Add Transaction", systemImage: "plus") { model.newTransaction() }
                    .help("Add a transaction to this account (⌘N)")
            }
        }
        .onExitCommand { model.sidebar = .page(.accounts) }
    }

    private func footer(difference: Decimal, count: Int, currency: String) -> some View {
        HStack(spacing: Space.md) {
            Text("\(count) selected")
            Text("Difference \(Text(Money.string(difference, currency: currency)).foregroundStyle(difference == 0 ? Palette.moneyIn : Palette.moneyOut))")
            Spacer()
            Button("Stop Reconciling") { model.stopReconcile(reconcile.account) }
                .help("Forget this statement; ticked transactions stay cleared")
            Button("Finish") { model.finishReconcile(reconcile, undoManager: undoManager) }
                .keyboardShortcut(.defaultAction)
                .disabled(difference != 0)
        }
        .monospacedDigit()
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.md)
        .background(.bar)
    }
}

private struct Tile: View {
    let title: String
    let value: String
    var note: String?
    var highlight: Color?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(highlight ?? .primary)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.xs)
        }
    }
}
