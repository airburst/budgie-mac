import BudgieMacKit
import SwiftData
import SwiftUI

/// All Accounts, an Accounts section with one row per open account, then the other pages.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Query(filter: #Predicate<Account> { !$0.deleted }, sort: \Account.name)
    private var accounts: [Account]

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            pageRow(.accounts)
            Section("Accounts") {
                ForEach(accounts) { account in
                    SidebarAccountRow(account: account)
                        .tag(SidebarSelection.account(account.uuid))
                        .contextMenu {
                            Button("Open") { model.sidebar = .account(account.uuid) }
                        }
                }
            }
            Section {
                ForEach(SidebarItem.allCases.filter { $0 != .accounts }) { pageRow($0) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Add Account", systemImage: "plus") { model.isAddingAccount = true }
                    .buttonStyle(.borderless)
                    .help("Add an account (⇧⌘N)")
                Spacer()
            }
            .padding(Space.md)
        }
    }

    private func pageRow(_ page: SidebarItem) -> some View {
        Label(page.title, systemImage: page.symbol)
            .tag(SidebarSelection.page(page))
    }
}

private struct SidebarAccountRow: View {
    let account: Account

    var body: some View {
        let balance = account.balance
        let text = Money.string(balance, currency: account.currency)
        Label {
            HStack(spacing: Space.sm) {
                Text(account.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Space.xs)
                MoneyText(amount: balance, currency: account.currency)
                    .font(.callout)
            }
        } icon: {
            Image(systemName: account.type.symbol)
        }
        .help(account.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(account.name), balance \(text)")
    }
}

/// An amount with its sign, in monospaced digits: green when positive, red when negative.
struct MoneyText: View {
    let amount: Decimal
    let currency: String

    var body: some View {
        Text(Money.string(amount, currency: currency))
            .monospacedDigit()
            .foregroundStyle(amount < 0 ? Palette.moneyOut : amount > 0 ? Palette.moneyIn : Color.primary)
    }
}
