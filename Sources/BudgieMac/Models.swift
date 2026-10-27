import Foundation
import SwiftData
import BudgieMacKit


// SwiftUI and ObjectiveC have their own `Transaction` and `Category`; in this
// module the names mean the data model.
typealias Transaction = BudgieMacKit.Transaction
typealias Category = BudgieMacKit.Category

/// The sidebar pages. Snapshot mode walks through every case.
enum SidebarItem: String, CaseIterable, Identifiable {
    case accounts, scheduled, budget, reports, categories, payees

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts: "All Accounts"
        case .scheduled: "Scheduled"
        case .budget: "Budget"
        case .reports: "Reports"
        case .categories: "Categories"
        case .payees: "Payees"
        }
    }

    var symbol: String {
        switch self {
        case .accounts: "building.columns"
        case .scheduled: "calendar"
        case .budget: "envelope"
        case .reports: "chart.bar"
        case .categories: "folder"
        case .payees: "person.2"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarItem? = .accounts
    var selection: PersistentIdentifier?
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    func addAccount(name: String = "") {
        let account = Account(name: AccountName.clean(name))
        container.mainContext.insert(account)
        sidebar = .accounts
        selection = account.id
    }
}
