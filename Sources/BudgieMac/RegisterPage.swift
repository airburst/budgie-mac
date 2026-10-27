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
    @Query private var preferences: [Preferences]

    init(uuid: UUID) {
        _accounts = Query(filter: #Predicate<Account> { $0.uuid == uuid })
        _transactions = Query(filter: #Predicate<Transaction> { $0.account?.uuid == uuid }, sort: Register.order)
    }

    var body: some View {
        if let account = accounts.first, model.forecastFor == account.uuid {
            ForecastView(account: account)
        } else if let account = accounts.first, let reconcile = Reconcile(pendingOn: account) {
            // A pending statement resumes the reconcile page (S-022).
            ReconcileView(reconcile: reconcile)
                .onAppear { model.prepareReconcile(account) }
        } else if let account = accounts.first {
            register(account)
                .searchable(text: Bindable(model).registerSearch, isPresented: Bindable(model).registerSearching,
                            placement: .toolbar, prompt: "Payee, category, notes or amount")
                .onChange(of: account.uuid) { _, _ in model.registerSearch = "" }
                .navigationTitle(account.name)
                .navigationSubtitle(subtitle(account))
                .toolbar { toolbar }
        } else {
            ContentUnavailableView("No Account", systemImage: "building.columns")
        }
    }

    @ViewBuilder private func register(_ account: Account) -> some View {
        let all = Register.rows(transactions, openingBalance: account.openingBalance)
        let rows = Register.visible(all, hideReconciled: hideReconciled, hideCleared: hideCleared)
            .filter { Register.matches($0.transaction, model.registerSearch) }
        if !all.isEmpty && rows.isEmpty && !model.registerSearch.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: model.registerSearch)
        } else if !all.isEmpty && rows.isEmpty {
            ContentUnavailableView {
                Label("No Transactions Shown", systemImage: "line.3.horizontal.decrease")
            } description: {
                Text("All transactions are hidden by the current filter.")
            } actions: {
                Button("Show All") { setFilter(reconciled: false, cleared: false) }
            }
        } else if rows.isEmpty {
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
                Text(Day.formatted(row.transaction.date))
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
                StatusButton(transaction: row.transaction) {
                    model.toggleCleared([row.transaction], undoManager: undoManager)
                }
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
        // Space marks the selected rows as cleared or uncleared.
        .onKeyPress(.space) {
            guard !model.selectedTransactions.isEmpty else { return .ignored }
            model.toggleCleared(model.selectedTransactionRows, undoManager: undoManager)
            return .handled
        }
    }

    /// "Balance £4,778.58 · Cleared £5,137.22", plus "· Hiding Reconciled" when filtered.
    private func subtitle(_ account: Account) -> String {
        [
            "Balance \(Money.string(account.balance, currency: account.currency))",
            "Cleared \(Money.string(account.clearedBalance, currency: account.currency))",
            Register.filterSummary(hideReconciled: hideReconciled, hideCleared: hideCleared),
        ].compactMap(\.self).joined(separator: " · ")
    }

    private var hideReconciled: Bool { preferences.first?.hideReconciled ?? false }
    private var hideCleared: Bool { preferences.first?.hideCleared ?? false }

    /// Saved in Preferences, so every register uses the same filter.
    private func setFilter(reconciled: Bool, cleared: Bool) {
        let context = model.container.mainContext
        let preferences = Preferences.current(in: context)
        preferences.hideReconciled = reconciled
        preferences.hideCleared = cleared
        try? context.save()
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu {
                Toggle("Hide Reconciled", isOn: Binding(get: { hideReconciled }, set: { setFilter(reconciled: $0, cleared: hideCleared) }))
                Toggle("Hide Cleared", isOn: Binding(get: { hideCleared }, set: { setFilter(reconciled: hideReconciled, cleared: $0) }))
                Divider()
                Button("Show All") { setFilter(reconciled: false, cleared: false) }
                    .disabled(!hideReconciled && !hideCleared)
            } label: {
                if let summary = Register.filterSummary(hideReconciled: hideReconciled, hideCleared: hideCleared) {
                    Label("Filter · \(summary)", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .labelStyle(.titleAndIcon)
                } else {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
            .help(Register.filterSummary(hideReconciled: hideReconciled, hideCleared: hideCleared) ?? "Hide reconciled or cleared transactions")
            Button("Reconcile…", systemImage: "checkmark.seal") { model.reconcileSheet = model.openAccount.map(ReconcileTarget.init) }
                .help("Reconcile this account against a statement")
            Button("Forecast", systemImage: "chart.line.uptrend.xyaxis") { model.forecastFor = model.openAccount }
                .help("Forecast this account's balance from its scheduled transactions")
        }
        ToolbarItem {
            Button("Add Transaction", systemImage: "plus") { model.newTransaction() }
                .help("Add a transaction to this account (⌘N)")
        }
    }

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

/// Icon plus word, so colour is never the only signal. Clicking it marks the
/// row as cleared or uncleared; a reconciled row shows a lock and stays put.
struct StatusButton: View {
    let transaction: Transaction
    let toggle: () -> Void

    var body: some View {
        let status = transaction.status
        Button(action: toggle) {
            Label(status.title, systemImage: symbol(status))
                .foregroundStyle(status == .uncleared ? .secondary : .primary)
        }
        .buttonStyle(.plain)
        .disabled(status == .reconciled)
        .help(help(status))
        .accessibilityLabel("Cleared")
        .accessibilityValue(status == .uncleared ? "off" : "on")
        .accessibilityAddTraits(.isToggle)
    }

    private func help(_ status: TransactionStatus) -> String {
        guard status == .reconciled else { return status == .cleared ? "Mark as uncleared (Space)" : "Mark as cleared (Space)" }
        let day = transaction.account?.lastReconciled.map { Day.formatted($0, .abbreviated) }
        return "Reconciled\(day.map { " on \($0)" } ?? ""). Reconciled transactions can't be marked as uncleared."
    }

    private func symbol(_ status: TransactionStatus) -> String {
        switch status {
        case .uncleared: "circle"
        case .cleared: "checkmark.circle"
        case .reconciled: "lock"
        }
    }
}
