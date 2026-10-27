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

    /// The selected rows in the open register.
    var selectedTransactions = Set<PersistentIdentifier>()
    /// The Add or Edit Transaction sheet, when open.
    var transactionSheet: TransactionSheetMode?

    /// The account whose register is open.
    var openAccount: UUID? {
        if case .account(let uuid) = sidebar { uuid } else { nil }
    }

    /// Transaction > Edit Transaction… (⌘E) for the one selected row.
    var canEditTransaction: Bool { openAccount != nil && selectedTransactions.count == 1 }

    func editSelectedTransaction() {
        if canEditTransaction, let id = selectedTransactions.first { transactionSheet = .edit(id) }
    }

    /// File > New Transaction (⌘N), the toolbar +, or the empty state.
    func newTransaction() {
        if let openAccount { transactionSheet = .add(account: openAccount) }
    }

    /// Adds the transaction, selects it, and offers "Undo Add Transaction".
    @discardableResult
    func addTransaction(_ draft: TransactionDraft, to account: Account, undoManager: UndoManager?) throws(TransactionDraft.Problem) -> Transaction {
        let context = container.mainContext
        let transaction = try draft.add(to: account, in: context)
        try? context.save()
        selectedTransactions = [transaction.persistentModelID]
        undoManager?.registerUndo(withTarget: self) { model in
            model.selectedTransactions.remove(transaction.persistentModelID)
            context.delete(transaction)
            try? context.save()
        }
        undoManager?.setActionName("Add Transaction")
        return transaction
    }

    /// Saves the sheet into the transaction (and its transfer partner), and
    /// offers "Undo Edit Transaction".
    func edit(_ transaction: Transaction, with draft: TransactionDraft, undoManager: UndoManager?) throws(TransactionDraft.Problem) {
        let context = container.mainContext
        let before = TransactionValues(transaction)
        let partner = Transfers.partner(of: transaction, in: context)
        let partnerBefore = partner.map(TransactionValues.init)
        try draft.apply(to: transaction, in: context)
        Transfers.syncPartner(of: transaction, in: context)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { _ in
            before.restore(transaction, in: context)
            if let partner, let partnerBefore { partnerBefore.restore(partner, in: context) }
            try? context.save()
        }
        undoManager?.setActionName("Edit Transaction")
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
