import Foundation
import Observation
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

/// What the sidebar has selected: a page, or one account (its register).
enum SidebarSelection: Hashable {
    case page(SidebarItem)
    case account(UUID)
}

extension AccountType {
    var title: String {
        switch self {
        case .bank: "Bank"
        case .creditCard: "Credit Card"
        case .loan: "Loan"
        case .investment: "Investment"
        case .cash: "Cash"
        }
    }

    var symbol: String {
        switch self {
        case .bank: "building.columns"
        case .creditCard: "creditcard"
        case .loan: "percent"
        case .investment: "chart.line.uptrend.xyaxis"
        case .cash: "banknote"
        }
    }
}

/// App-wide state that menus, toolbars, and views share.
@Observable
final class AppModel {
    let container: ModelContainer
    var sidebar: SidebarSelection? = .page(.accounts)
    let importFlow = ImportFlow()
    /// Settings reopens on the last tab. Test and snapshot runs leave it alone.
    var settingsTab: SettingsTab = SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.tab") ?? "") ?? .general {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(settingsTab.rawValue, forKey: "settings.tab") } }
    }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Shows the Add Account sheet (S-004).
    var isAddingAccount = false

    /// Adds the account, opens it, and offers "Undo Add Account".
    @discardableResult
    func add(_ draft: AccountDraft, undoManager: UndoManager?) -> Account {
        let account = draft.makeAccount()
        let context = container.mainContext
        context.insert(account)
        try? context.save()
        sidebar = .account(account.uuid)
        undoManager?.registerUndo(withTarget: self) { model in
            if model.sidebar == .account(account.uuid) { model.sidebar = .page(.accounts) }
            context.delete(account)
            try? context.save()
        }
        undoManager?.setActionName("Add Account")
        return account
    }
}
