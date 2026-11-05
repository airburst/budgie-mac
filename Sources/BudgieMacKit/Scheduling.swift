import Foundation
import SwiftData

// M4: scheduled transactions.

public extension ScheduledTransaction {
    var rule: RRule? { RRule(rrule) }

    /// "Monthly", "Every 2 weeks", "Once" … (S-025).
    var frequencyLabel: String { rule?.label ?? rrule }

    /// Due dates from the stored next due date up to `end`, honouring COUNT
    /// and UNTIL. Empty for a paused or finished schedule.
    func occurrences(through end: Date) -> [Date] {
        guard active, let start = nextDueDate, let rule else { return [] }
        var dates: [Date] = []
        var date: Date? = start
        var remaining = rule.count ?? Int.max
        while let current = date, current <= end, remaining > 0 {
            if let until = rule.until, current > until { break }
            dates.append(current)
            remaining -= 1
            date = rule.next(after: current, anchor: current)
        }
        return dates
    }
}

public enum Scheduling {
    /// Moves the schedule to its next date. COUNT goes down by one; when
    /// nothing is left the schedule is deleted, as Budgie does. Returns the
    /// new next due date, or nil when the schedule ended.
    @discardableResult
    public static func advance(_ schedule: ScheduledTransaction, in context: ModelContext) -> Date? {
        guard var rule = schedule.rule, let current = schedule.nextDueDate else {
            context.delete(schedule)
            return nil
        }
        if let count = rule.count {
            guard count > 1 else {
                context.delete(schedule)
                return nil
            }
            rule.count = count - 1
            schedule.rrule = rule.string
        }
        guard let next = rule.next(after: current, anchor: current) else {
            context.delete(schedule)
            return nil
        }
        schedule.nextDueDate = next
        schedule.updatedAt = .now
        return next
    }

    /// The Record sheet's starting point: the schedule's payee, amount,
    /// category, transfer and notes, dated on its due date unless given a date.
    public static func draft(for schedule: ScheduledTransaction, on date: Date? = nil, locale: Locale = .current) -> TransactionDraft {
        var draft = TransactionDraft(date: date ?? schedule.nextDueDate ?? Day.today)
        draft.payee = schedule.payee
        draft.category = schedule.category
        let text = abs(schedule.amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
        if schedule.amount < 0 { draft.withdrawal = text } else { draft.deposit = text }
        draft.notes = schedule.notes ?? ""
        draft.transferAccount = schedule.transferToAccount
        return draft
    }

    /// Records the due occurrence (a transaction, or a transfer pair) and
    /// moves the schedule on (S-028).
    @discardableResult
    public static func record(_ schedule: ScheduledTransaction, as draft: TransactionDraft? = nil,
                              in context: ModelContext, locale: Locale = .current) throws(TransactionDraft.Problem) -> Transaction? {
        guard let account = schedule.account else { return nil }
        let transaction = try (draft ?? Scheduling.draft(for: schedule, locale: locale)).add(to: account, in: context, locale: locale)
        advance(schedule, in: context)
        return transaction
    }

    /// Skips the due occurrence without recording anything (S-029).
    @discardableResult
    public static func skip(_ schedule: ScheduledTransaction, in context: ModelContext) -> Date? {
        advance(schedule, in: context)
    }

    /// S-033: records every active auto-post occurrence due within its
    /// days-in-advance window, including missed ones. Running it twice posts
    /// nothing twice, because each record moves the due date on.
    @discardableResult
    public static func autoPost(today: Date = Day.today, in context: ModelContext, locale: Locale = .current) -> Int {
        let schedules = (try? context.fetch(FetchDescriptor<ScheduledTransaction>())) ?? []
        var posted = 0
        for schedule in schedules where schedule.active && schedule.autoPost {
            let window = Day.calendar.date(byAdding: .day, value: max(0, schedule.daysInAdvance ?? 0), to: today)!
            var guardrail = 0
            while !schedule.isDeleted, schedule.modelContext != nil, let due = schedule.nextDueDate, due <= window, guardrail < 400 {
                guard (try? record(schedule, in: context, locale: locale)) != nil else { break }
                posted += 1
                guardrail += 1
            }
        }
        return posted
    }

    public struct DueSoon: Equatable, Sendable {
        public var income: Decimal = 0
        public var outgoing: Decimal = 0
        public var count = 0
    }

    /// S-032: active schedules due from today up to 7 days ahead.
    public static func dueSoon(_ schedules: [ScheduledTransaction], today: Date = Day.today) -> DueSoon {
        let end = Day.calendar.date(byAdding: .day, value: 7, to: today)!
        var summary = DueSoon()
        for schedule in schedules {
            for date in schedule.occurrences(through: end) where date >= today {
                summary.count += 1
                if schedule.amount >= 0 { summary.income += schedule.amount } else { summary.outgoing += -schedule.amount }
            }
        }
        return summary
    }
}

// MARK: - Forecast (S-034, S-035)

public struct ForecastRow: Identifiable, Hashable, Sendable {
    /// Where a row comes from: a schedule, or a register entry dated after today.
    public enum Source: Hashable, Sendable {
        case scheduled(PersistentIdentifier)
        case transaction(PersistentIdentifier)
    }

    public let id: String
    public let date: Date
    public let payee: String
    /// Signed for this account: transfers into it are deposits.
    public let amount: Decimal
    public let categoryPath: String?
    public let notes: String?
    public let isTransfer: Bool
    public let source: Source

    public var isScheduled: Bool {
        if case .scheduled = source { return true }
        return false
    }
}

/// The balance after one day of the forecast, for the chart.
public struct ForecastPoint: Hashable, Sendable {
    public let date: Date
    public let balance: Decimal
}

public enum Forecast {
    /// The end of the month three months ahead, as Budgie (S-034).
    public static func defaultEnd(today: Date = Day.today) -> Date {
        let calendar = Day.calendar
        let ahead = calendar.date(byAdding: .month, value: 3, to: today)!
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: ahead))!
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
    }

    /// Where the forecast starts: the opening balance plus every transaction
    /// dated today or earlier. Later entries come in as rows on their own day.
    public static func startBalance(of account: Account, today: Date = Day.today) -> Decimal {
        account.balance(on: today)
    }

    /// Projected rows for one account after today: register entries dated
    /// after today, and each active schedule from its stored next due date.
    public static func rows(for account: Account, schedules: [ScheduledTransaction], through end: Date,
                            today: Date = Day.today) -> [ForecastRow] {
        var rows: [ForecastRow] = account.transactions.filter { $0.date > today && $0.date <= end }.map { t in
            ForecastRow(id: "real-\(t.uuid.uuidString)", date: t.date, payee: t.payee, amount: t.amount,
                        categoryPath: t.category?.path, notes: t.notes, isTransfer: t.transferUUID != nil,
                        source: .transaction(t.persistentModelID))
        }
        for schedule in schedules {
            let outOf = schedule.account === account
            let into = schedule.transferToAccount === account && !outOf
            guard outOf || into else { continue }
            let amount = into ? -schedule.amount : schedule.amount
            for date in schedule.occurrences(through: end) where date > today {
                rows.append(ForecastRow(id: "\(schedule.uuid.uuidString)-\(Day.string(date))", date: date, payee: schedule.payee,
                                        amount: amount, categoryPath: schedule.category?.path, notes: schedule.notes,
                                        isTransfer: schedule.transferToAccount != nil, source: .scheduled(schedule.persistentModelID)))
            }
        }
        return rows.sorted { ($0.date, $0.isScheduled ? 1 : 0, $0.payee) < ($1.date, $1.isScheduled ? 1 : 0, $1.payee) }
    }

    /// The projected balance after each row, from the balance at the start.
    /// Excluded rows keep the balance before them and change nothing stored.
    public static func balances(_ rows: [ForecastRow], start: Decimal, excluded: Set<String> = []) -> [String: Decimal] {
        var balance = start
        var result: [String: Decimal] = [:]
        for row in rows {
            if !excluded.contains(row.id) { balance += row.amount }
            result[row.id] = balance
        }
        return result
    }

    /// One point for today, one per day with rows (the balance at the end of
    /// that day), and one at the end date, so the line spans the whole range.
    public static func points(_ rows: [ForecastRow], balances: [String: Decimal], start: Decimal,
                              today: Date = Day.today, end: Date) -> [ForecastPoint] {
        var points = [ForecastPoint(date: today, balance: start)]
        for row in rows {
            let balance = balances[row.id] ?? start
            if points.last?.date == row.date { points.removeLast() }
            points.append(ForecastPoint(date: row.date, balance: balance))
        }
        if let last = points.last, last.date < end { points.append(ForecastPoint(date: end, balance: last.balance)) }
        return points
    }
}
