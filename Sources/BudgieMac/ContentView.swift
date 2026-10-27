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
        .sheet(item: Bindable(model).accountSheet) { mode in
            // No .noInitialFocus(): this sheet opens with focus in Name (S-004).
            NavigationStack { AccountSheet(mode: mode) }
        }
        .sheet(item: Bindable(model).transactionSheet) { mode in
            NavigationStack { TransactionSheet(mode: mode) }
        }
        .modifier(ImportFlowModifier())
        .task {
            SeedData.insertIfRequested(into: model)
            // S-015: a first launch with no data gets Budgie's default categories.
            if DefaultCategories.seedIfEmpty(model.container.mainContext) > 0 { try? model.container.mainContext.save() }
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.sidebar ?? .page(.accounts) {
        case .page(.accounts):
            AccountsPage()
        case .page(.categories):
            CategoriesPage()
        case .page(.payees):
            PayeesPage()
        case .page(let page):
            ContentUnavailableView(page.title, systemImage: page.symbol)
                .navigationTitle(page.title)
        case .account(let uuid):
            RegisterPage(uuid: uuid)
        }
    }
}
