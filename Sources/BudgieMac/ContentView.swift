import BudgieMacKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .sheet(isPresented: Bindable(model).isAddingAccount) {
            // No .noInitialFocus(): this sheet opens with focus in Name (S-004).
            NavigationStack { AddAccountSheet() }
        }
        .modifier(ImportFlowModifier())
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.sidebar ?? .page(.accounts) {
        case .page(.accounts):
            AccountsPage()
        case .page(let page):
            ContentUnavailableView(page.title, systemImage: page.symbol)
                .navigationTitle(page.title)
        case .account(let uuid):
            AccountDetail(uuid: uuid)
        }
    }
}

/// An account's page. The register comes with S-005.
private struct AccountDetail: View {
    @Query private var accounts: [Account]

    init(uuid: UUID) {
        _accounts = Query(filter: #Predicate<Account> { $0.uuid == uuid })
    }

    var body: some View {
        if let account = accounts.first {
            ContentUnavailableView(account.name, systemImage: account.type.symbol)
                .navigationTitle(account.name)
        } else {
            ContentUnavailableView("No Account", systemImage: "building.columns")
        }
    }
}
