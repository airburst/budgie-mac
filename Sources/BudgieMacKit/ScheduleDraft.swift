import Foundation
import SwiftData

/// S-026 and S-027: what the scheduled-transaction sheet edits.
public struct ScheduleDraft {
    public var account: Account?
    public var payee = ""
    public var category: Category?
    public var withdrawal = ""
    public var deposit = ""
    /// The first (or next) due date.
    public var nextDue = Day.today
    public var recurrence = RecurrenceForm()
    public var transferTo: Account?
    public var autoPost = false
    public var daysInAdvance = 0
    public var notes = ""
    public var active = true

    public init(account: Account? = nil) {
        self.account = account
        recurrence.monthDays = [Day.calendar.component(.day, from: nextDue)]
    }

    public init(_ schedule: ScheduledTransaction, locale: Locale = .current) {
        account = schedule.account
        payee = schedule.payee
        category = schedule.category
        let text = abs(schedule.amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
        if schedule.amount < 0 { withdrawal = text } else { deposit = text }
        nextDue = schedule.nextDueDate ?? Day.today
        recurrence = RecurrenceForm(rrule: schedule.rrule)
        transferTo = schedule.transferToAccount
        autoPost = schedule.autoPost
        daysInAdvance = schedule.daysInAdvance ?? 0
        notes = schedule.notes ?? ""
        active = schedule.active
    }

    /// The signed amount, reusing the transaction rules.
    public func amount(locale: Locale = .current) -> Result<Decimal, TransactionDraft.Problem> {
        var draft = TransactionDraft()
        draft.withdrawal = withdrawal
        draft.deposit = deposit
        return draft.amount(locale: locale)
    }

    public func isValid(locale: Locale = .current) -> Bool {
        account != nil && !payee.trimmingCharacters(in: .whitespaces).isEmpty && amount(locale: locale).isSuccess
            && transferTo !== account
    }

    public func make(in context: ModelContext, locale: Locale = .current) throws(TransactionDraft.Problem) -> ScheduledTransaction {
        let schedule = ScheduledTransaction(account: account, payee: "", amount: 0, rrule: "")
        try apply(to: schedule, locale: locale)
        context.insert(schedule)
        return schedule
    }

    public func apply(to schedule: ScheduledTransaction, locale: Locale = .current) throws(TransactionDraft.Problem) {
        let amount = try amount(locale: locale).get()
        schedule.account = account
        schedule.payee = payee.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        schedule.category = category
        schedule.amount = amount
        schedule.nextDueDate = nextDue
        schedule.rrule = recurrence.rrule
        schedule.transferToAccount = transferTo
        schedule.autoPost = autoPost
        schedule.daysInAdvance = autoPost ? daysInAdvance : nil
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        schedule.notes = notes.isEmpty ? nil : notes
        schedule.active = active
        schedule.updatedAt = .now
    }
}

/// S-031: the eight sort orders and the account filter, saved between launches.
public enum ScheduleSort: String, CaseIterable, Sendable {
    case nextDue, nextDueLatest, payee, payeeZA, amountLowest, amountHighest, account, accountZA

    public var title: String {
        switch self {
        case .nextDue: "Next Due (Soonest First)"
        case .nextDueLatest: "Next Due (Latest First)"
        case .payee: "Payee (A to Z)"
        case .payeeZA: "Payee (Z to A)"
        case .amountLowest: "Amount (Lowest First)"
        case .amountHighest: "Amount (Highest First)"
        case .account: "Account (A to Z)"
        case .accountZA: "Account (Z to A)"
        }
    }

    public func sorted(_ schedules: [ScheduledTransaction]) -> [ScheduledTransaction] {
        func text(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }
        let far = Date.distantFuture
        switch self {
        case .nextDue: return schedules.sorted { ($0.nextDueDate ?? far, $0.payee) < ($1.nextDueDate ?? far, $1.payee) }
        case .nextDueLatest: return schedules.sorted { ($0.nextDueDate ?? far, $0.payee) > ($1.nextDueDate ?? far, $1.payee) }
        case .payee: return schedules.sorted { text($0.payee, $1.payee) }
        case .payeeZA: return schedules.sorted { text($1.payee, $0.payee) }
        case .amountLowest: return schedules.sorted { $0.amount < $1.amount }
        case .amountHighest: return schedules.sorted { $0.amount > $1.amount }
        case .account: return schedules.sorted { text($0.account?.name ?? "", $1.account?.name ?? "") }
        case .accountZA: return schedules.sorted { text($1.account?.name ?? "", $0.account?.name ?? "") }
        }
    }
}

/// The Scheduled page's saved view: sort order and which accounts show.
public struct ScheduleView: Equatable, Sendable {
    public var sort: ScheduleSort = .nextDue
    /// Empty means every account.
    public var accounts: Set<UUID> = []

    public init() {}

    public static let sortKey = "scheduled.sort"
    public static let accountsKey = "scheduled.accounts"

    public init(defaults: UserDefaults) {
        sort = defaults.string(forKey: Self.sortKey).flatMap(ScheduleSort.init) ?? .nextDue
        accounts = Set((defaults.stringArray(forKey: Self.accountsKey) ?? []).compactMap(UUID.init))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(sort.rawValue, forKey: Self.sortKey)
        defaults.set(accounts.map(\.uuidString), forKey: Self.accountsKey)
    }

    public func apply(_ schedules: [ScheduledTransaction]) -> [ScheduledTransaction] {
        let shown = accounts.isEmpty ? schedules : schedules.filter { $0.account.map { accounts.contains($0.uuid) } ?? false }
        return sort.sorted(shown)
    }
}
