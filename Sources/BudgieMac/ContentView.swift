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
        .sheet(item: Bindable(model).transactionSheet) { mode in
            NavigationStack { TransactionSheet(mode: mode) }
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
            RegisterPage(uuid: uuid)
        }
    }
}
