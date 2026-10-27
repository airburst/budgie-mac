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

    /// The app's one model, for the app delegate's quit backup.
    nonisolated(unsafe) static weak var current: AppModel?

    init(container: ModelContainer) {
        self.container = container
        AppModel.current = self
    }

    /// The selected rows in the open register.
    var selectedTransactions = Set<PersistentIdentifier>()
    /// S-055: a QIF file waiting for review.
    var qifReview: QifReview?

    /// S-051: the register's search text, and whether the field is active (⌘F).
    var registerSearch = ""
    var registerSearching = false

    /// The Add or Edit Transaction sheet, when open.
    var transactionSheet: TransactionSheetMode?

    /// The account whose register is open.
    var openAccount: UUID? {
        if case .account(let uuid) = sidebar { uuid } else { nil }
    }

    /// The Add or Edit Scheduled Transaction sheet, when open (S-026).
    var scheduleSheet: ScheduleSheetMode?

    /// The Budget page's month, "2026-10" (S-036).
    var budgetMonth = Budget.thisMonth
    var envelopeSheet: EnvelopeSheetMode?
    var movingMoney = false

    /// The account whose forecast replaces its register (S-034).
    var forecastFor: UUID?
    /// The day the forecast chart reads out, set by hover or click; snapshot mode sets it too.
    var forecastFocus: Date?

    /// Reconcile… sheet for an account (S-021).
    var reconcileSheet: ReconcileTarget?
    /// The reconcile page's ticked rows, for the account in `reconcileFor`.
    var reconcileTicked = Set<PersistentIdentifier>()
    var reconcileFor: UUID?
    /// The ticks came from an exact match to the statement.
    var reconcileAutoMatched = false

    /// The Add or Edit Payee sheet, when open (S-019).
    var payeeSheet: PayeeSheetMode?

    /// The Add or Edit Category sheet, when open (S-016, S-017).
    var categorySheet: CategorySheetMode?

    /// The Add or Edit Account sheet, when open (S-004, S-010).
    var accountSheet: AccountSheetMode?
}
