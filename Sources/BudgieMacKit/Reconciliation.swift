import Foundation
import SwiftData

/// M3: matching an account's transactions to a bank statement.
public struct Reconcile {
    public let account: Account
    public let statementDate: Date
    public let statementBalance: Decimal

    public init(account: Account, statementDate: Date, statementBalance: Decimal) {
        self.account = account
        self.statementDate = statementDate
        self.statementBalance = statementBalance
    }

    /// The pending statement saved on the account, if a reconcile is under way.
    public init?(pendingOn account: Account) {
        guard let date = account.pendingReconcileDate, let balance = account.pendingReconcileBalance else { return nil }
        self.init(account: account, statementDate: date, statementBalance: balance)
    }

    /// Not yet reconciled, dated on or before the statement, oldest first.
    public var eligible: [Transaction] {
        account.transactions
            .filter { !$0.reconciled && $0.date <= statementDate }
            .sorted { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }

    /// Where this statement starts: the opening balance plus everything already reconciled.
    public var openingBalance: Decimal {
        account.transactions.reduce(account.openingBalance) { $0 + ($1.reconciled ? $1.amount : 0) }
    }

    /// Opening balance plus the ticked rows. With ticked = cleared this is the
    /// account's cleared balance up to the statement date: one definition everywhere.
    public func clearedBalance(ticked: Set<PersistentIdentifier>) -> Decimal {
        eligible.reduce(openingBalance) { $0 + (ticked.contains($1.persistentModelID) ? $1.amount : 0) }
    }

    public func difference(ticked: Set<PersistentIdentifier>) -> Decimal {
        statementBalance - clearedBalance(ticked: ticked)
    }

    public func isBalanced(ticked: Set<PersistentIdentifier>) -> Bool {
        difference(ticked: ticked) == 0
    }

    /// What starts ticked: a set of rows that adds up to the statement exactly
    /// when there is one (and says so), otherwise the cleared rows.
    public func initialTicks() -> (ticked: Set<PersistentIdentifier>, autoMatched: Bool) {
        let rows = eligible
        let target = statementBalance - openingBalance
        if target != 0, let picked = SubsetSum.find(rows.map(\.amount), target: target) {
            return (Set(picked.map { rows[$0].persistentModelID }), true)
        }
        return (Set(rows.filter(\.cleared).map(\.persistentModelID)), false)
    }

    /// Saves the statement on the account so the reconcile can be resumed (S-021).
    @discardableResult
    public static func start(_ account: Account, statementDate: Date, statementBalance: Decimal) -> Reconcile {
        account.pendingReconcileDate = statementDate
        account.pendingReconcileBalance = statementBalance
        account.updatedAt = .now
        return Reconcile(account: account, statementDate: statementDate, statementBalance: statementBalance)
    }

    /// Forgets the pending statement.
    public static func stop(_ account: Account) {
        account.pendingReconcileDate = nil
        account.pendingReconcileBalance = nil
    }

    public enum Problem: Error, Equatable { case notBalanced }

    /// Marks the ticked rows reconciled, saves a checkpoint, clears the pending
    /// statement. Refused unless the difference is zero (S-022).
    @discardableResult
    public func finish(ticked: Set<PersistentIdentifier>, in context: ModelContext) throws(Problem) -> AccountReconciliation {
        guard isBalanced(ticked: ticked) else { throw .notBalanced }
        for transaction in eligible where ticked.contains(transaction.persistentModelID) {
            transaction.cleared = true
            transaction.reconciled = true
            transaction.updatedAt = .now
        }
        let checkpoint = AccountReconciliation(account: account, date: statementDate, balance: statementBalance)
        context.insert(checkpoint)
        Reconcile.stop(account)
        return checkpoint
    }
}

/// A port of Budgie's `src/lib/subset-sum.ts`: indices of amounts that add up
/// to the target exactly, searched with pruning and a work budget.
public enum SubsetSum {
    static let maxItems = 30
    static let budget = 500_000

    public static func find(_ amounts: [Decimal], target: Decimal) -> [Int]? {
        guard target != 0, !amounts.isEmpty, amounts.count <= maxItems else { return nil }
        func cents(_ value: Decimal) -> Int {
            var scaled = value * 100, rounded = Decimal()
            NSDecimalRound(&rounded, &scaled, 0, .plain)
            return NSDecimalNumber(decimal: rounded).intValue
        }
        let values = amounts.map(cents)
        let goal = cents(target)
        let n = values.count
        var minRemaining = Array(repeating: 0, count: n + 1)
        var maxRemaining = Array(repeating: 0, count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            minRemaining[i] = minRemaining[i + 1] + min(0, values[i])
            maxRemaining[i] = maxRemaining[i + 1] + max(0, values[i])
        }
        var iterations = 0
        var chosen: [Int] = []
        func search(_ i: Int, _ remaining: Int) -> Bool {
            if remaining == 0 { return true }
            iterations += 1
            if iterations > budget || i == n { return false }
            if remaining > maxRemaining[i] || remaining < minRemaining[i] { return false }
            chosen.append(i)
            if search(i + 1, remaining - values[i]) { return true }
            chosen.removeLast()
            return search(i + 1, remaining)
        }
        return search(0, goal) ? chosen : nil
    }
}
