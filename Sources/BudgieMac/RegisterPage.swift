import BudgieMacKit
import SwiftData
import SwiftUI

/// S-005: an account's register. Window title is the account name, the
/// subtitle its balances; transactions oldest first with a running balance.
struct RegisterPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Query private var accounts: [Account]
    @Query private var transactions: [Transaction]

    init(uuid: UUID) {
        _accounts = Query(filter: #Predicate<Account> { $0.uuid == uuid })
        _transactions = Query(filter: #Predicate<Transaction> { $0.account?.uuid == uuid }, sort: Register.order)
    }

    var body: some View {
        if let account = accounts.first {
            register(account)
                .navigationTitle(account.name)
                .navigationSubtitle("Balance \(Money.string(account.balance, currency: account.currency)) · Cleared \(Money.string(account.clearedBalance, currency: account.currency))")
                .toolbar { toolbar }
        } else {
            ContentUnavailableView("No Account", systemImage: "building.columns")
        }
    }

    @ViewBuilder private func register(_ account: Account) -> some View {
        let rows = Register.rows(transactions, openingBalance: account.openingBalance)
        if rows.isEmpty {
            ContentUnavailableView {
                Label("No Transactions", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Add the first transaction for \(account.name).")
            } actions: {
                Button("Add Transaction") { model.newTransaction() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollViewReader { proxy in
                table(rows, currency: account.currency)
                    .onAppear { proxy.scrollTo(rows.last?.id, anchor: .bottom) }
                    .onChange(of: model.selectedTransactions) { _, selected in
                        if let id = selected.first { proxy.scrollTo(id) }
                    }
            }
        }
    }

    private func table(_ rows: [RegisterRow], currency: String) -> some View {
        @Bindable var model = model
        return Table(rows, selection: $model.selectedTransactions) {
            TableColumn("Date") { row in
                Text(row.transaction.date.formatted(Self.dayFormat))
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 96)
            TableColumn("Payee") { row in
                Text(row.transaction.payee)
                    .lineLimit(1)
                    .help(row.transaction.notes.map { "\(row.transaction.payee)\n\($0)" } ?? row.transaction.payee)
            }
            .width(min: 140, ideal: 220)
            TableColumn("Category") { row in
                if let category = row.transaction.category {
                    CategoryPill(category: category)
                }
            }
            .width(min: 100, ideal: 160)
            TableColumn("Amount") { row in
                MoneyText(amount: row.transaction.amount, currency: currency)
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            TableColumn("Balance") { row in
                Text(Money.string(row.balance, currency: currency))
                    .monospacedDigit()
            }
            .width(min: 90, ideal: 110)
            .alignment(.trailing)
            TableColumn("Status") { row in
                StatusLabel(status: row.transaction.status)
            }
            .width(min: 100, ideal: 110)
        }
        .contextMenu(forSelectionType: RegisterRow.ID.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button("Edit Transaction…") { model.transactionSheet = .edit(id) }
                    .keyboardShortcut("e")
            }
            if !ids.isEmpty {
                Divider()
                Button("Delete", role: .destructive) {
                    model.selectedTransactions = ids
                    model.deleteSelectedTransactions(undoManager: undoManager)
                }
            }
        } primaryAction: { ids in
            // Double-click or Return edits.
            if ids.count == 1, let id = ids.first { model.transactionSheet = .edit(id) }
        }
        // The Delete key and Edit > Delete.
        .onDeleteCommand { model.deleteSelectedTransactions(undoManager: undoManager) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu("Filter", systemImage: "line.3.horizontal.decrease") {}
                .disabled(true)
                .help("Hide reconciled or cleared transactions (coming with S-011)")
            Button("Reconcile…", systemImage: "checkmark.seal") {}
                .disabled(true)
                .help("Reconcile this account against a statement (coming with reconciliation)")
            Button("Forecast", systemImage: "chart.line.uptrend.xyaxis") {}
                .disabled(true)
                .help("Forecast this account's balance (coming with M3)")
        }
        ToolbarItem {
            Button("Add Transaction", systemImage: "plus") { model.newTransaction() }
                .help("Add a transaction to this account (⌘N)")
        }
    }

    /// "10/08/2026" in the user's locale.
    static let dayFormat = Date.FormatStyle(date: .numeric, time: .omitted, timeZone: TimeZone(identifier: "UTC")!)
}

/// The category as a pill, with its full path as a tooltip.
struct CategoryPill: View {
    let category: Category

    var body: some View {
        Text(category.name)
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(.quaternary, in: .capsule)
            .help(category.path)
    }
}

/// Icon plus word, so colour is never the only signal.
struct StatusLabel: View {
    let status: TransactionStatus

    var body: some View {
        Label(status.title, systemImage: symbol)
            .foregroundStyle(status == .uncleared ? .secondary : .primary)
    }

    private var symbol: String {
        switch status {
        case .uncleared: "circle"
        case .cleared: "checkmark.circle"
        case .reconciled: "lock"
        }
    }
}
