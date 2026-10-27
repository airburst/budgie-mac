import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            AccountList(page: model.sidebar ?? .accounts)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320)
        } detail: {
            AccountDetail()
        }
        .task {
            SeedData.insertIfRequested(into: model)
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(SidebarItem.allCases, selection: $model.sidebar) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 212)
    }
}

struct AccountList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.createdAt, order: .reverse) private var accounts: [Account]
    let page: SidebarItem

    /// Only All Accounts lists anything yet; the other pages come with their stories.
    private var visible: [Account] {
        page == .accounts ? accounts : []
    }

    var body: some View {
        @Bindable var model = model
        List(visible, selection: $model.selection) { account in
            Label(account.name, systemImage: account.isClosed ? "lock" : "building.columns")
                .tag(account.id)
                .contextMenu {
                    Button("Delete", role: .destructive) { context.delete(account) }
                }
        }
        .overlay {
            if visible.isEmpty {
                if page == .accounts {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: page.symbol,
                        description: Text("Press Command-N to add one.")
                    )
                } else {
                    ContentUnavailableView(page.title, systemImage: page.symbol)
                }
            }
        }
        .navigationTitle(page.title)
        .toolbar {
            ToolbarItem {
                Button("New Account", systemImage: "plus") { model.addAccount() }
                    .help("Add an account (Command-N)")
            }
        }
    }
}

struct AccountDetail: View {
    @Environment(AppModel.self) private var model
    @Query private var accounts: [Account]

    var body: some View {
        if let account = accounts.first(where: { $0.id == model.selection }) {
            @Bindable var account = account
            Form {
                TextField("Name", text: $account.name)
                Toggle("Closed", isOn: $account.isClosed)
                TextField("Notes", text: $account.notes, axis: .vertical)
                    .lineLimit(4...)
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView("No Selection", systemImage: "sidebar.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
