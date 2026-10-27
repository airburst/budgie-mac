import BudgieMacKit
import SwiftData
import SwiftUI

/// M3: reconciling, with the ticked rows held on AppModel.
extension AppModel {
    func startReconcile(_ account: Account, date: Date, balance: Decimal) {
        Reconcile.start(account, statementDate: date, statementBalance: balance)
        try? container.mainContext.save()
        reconcileFor = nil
        prepareReconcile(account)
        sidebar = .account(account.uuid)
    }

    /// Sets up the ticks the first time the reconcile page shows for an account,
    /// including after a relaunch (S-022: reopening resumes).
    func prepareReconcile(_ account: Account) {
        guard reconcileFor != account.uuid, let reconcile = Reconcile(pendingOn: account) else { return }
        let (ticked, matched) = reconcile.initialTicks()
        reconcileTicked = ticked
        reconcileAutoMatched = matched
        reconcileFor = account.uuid
    }

    /// Ticking marks the row cleared, as in Budgie, so the choice survives leaving.
    func setTicked(_ transaction: Transaction, _ on: Bool) {
        if on { reconcileTicked.insert(transaction.persistentModelID) } else { reconcileTicked.remove(transaction.persistentModelID) }
        reconcileAutoMatched = false
        transaction.cleared = on
        try? container.mainContext.save()
    }

    func finishReconcile(_ reconcile: Reconcile, undoManager: UndoManager?) {
        guard (try? reconcile.finish(ticked: reconcileTicked, in: container.mainContext)) != nil else { return }
        try? container.mainContext.save()
        reconcileFor = nil
        reconcileTicked = []
        AccessibilityNotification.Announcement("\(reconcile.account.name) reconciled").post()
    }

    func stopReconcile(_ account: Account) {
        Reconcile.stop(account)
        try? container.mainContext.save()
        reconcileFor = nil
        reconcileTicked = []
    }
}
