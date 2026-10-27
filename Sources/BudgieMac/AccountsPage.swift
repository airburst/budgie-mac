import BudgieMacKit
import SwiftData
import SwiftUI

/// S-003: the Total Balance card and a table of open accounts.
struct AccountsPage: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Account> { !$0.deleted }, sort: \Account.name)
    private var accounts: [Account]
    @State private var selection = Set<Account.ID>()

    var body: some View {
        Group {
            if accounts.isEmpty {
                empty
            } else {
                VStack(spacing: 0) {
                    TotalCard(totals: Money.totals(accounts))
                        .padding(Space.margin)
                    table
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let banner = model.importFlow.banner {
                ImportBanner(text: banner) { model.importFlow.banner = nil }
            }
        }
        .navigationTitle("All Accounts")
    }

    private var table: some View {
        Table(accounts, selection: $selection) {
            TableColumn("Account") { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(account.name)
                    Text([account.type.title, account.maskedNumber].compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("Balance") { account in
                MoneyText(amount: account.balance, currency: account.currency)
            }
            .alignment(.trailing)
            TableColumn("Cleared Balance") { account in
                MoneyText(amount: account.clearedBalance, currency: account.currency)
            }
            .alignment(.trailing)
            TableColumn("Last Reconciled") { account in
                Text(account.lastReconciled.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Never")
                    .foregroundStyle(account.lastReconciled == nil ? .secondary : .primary)
            }
            TableColumn("Remaining Credit") { account in
                if let remaining = account.remainingCredit {
                    MoneyText(amount: remaining, currency: account.currency)
                }
            }
            .alignment(.trailing)
        }
        .contextMenu(forSelectionType: Account.ID.self) { ids in
            if let account = accounts.first(where: { ids.contains($0.id) }) {
                Button("Open") { model.sidebar = .account(account.uuid) }
            }
        } primaryAction: { ids in
            if let account = accounts.first(where: { ids.contains($0.id) }) {
                model.sidebar = .account(account.uuid)
            }
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("No Accounts", systemImage: "building.columns")
        } description: {
            Text("Add an account to start tracking your money, or bring everything over from Budgie.")
        } actions: {
            Button("Add Account…") { model.isAddingAccount = true }
                .buttonStyle(.borderedProminent)
            Button("Import from Budgie…") { model.importFlow.chooseFile() }
        }
    }
}

/// "Total Balance", one line per currency, and what the number means.
private struct TotalCard: View {
    let totals: [Money.Total]

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Total Balance")
                    .font(.headline)
                ForEach(totals, id: \.currency) { total in
                    MoneyText(amount: total.amount, currency: total.currency)
                        .font(.title.weight(.semibold))
                }
                Text("Sum of account balances, not cash you can spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.sm)
        }
    }
}
