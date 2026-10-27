import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// M4: scheduled transactions and the forecast.
@MainActor
@Suite("Scheduling")
struct SchedulingTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }
    let uk = Locale(identifier: "en_GB")
    private func day(_ text: String) -> Date { Day.parse(text)! }

    private func schedule(_ rrule: String, due: String, amount: Decimal = -1150, account: Account? = nil) -> ScheduledTransaction {
        let owner = account ?? Account(name: "Bank")
        if account == nil { context.insert(owner) }
        let schedule = ScheduledTransaction(account: owner, payee: "Rent", amount: amount, rrule: rrule)
        schedule.nextDueDate = day(due)
        context.insert(schedule)
        return schedule
    }

    @Test("Recording creates a transaction and moves the due date on")
    func record() throws {
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-11-01")
        let made = try #require(try Scheduling.record(rent, in: context, locale: uk))
        #expect(made.amount == -1150 && Day.string(made.date) == "2026-11-01")
        #expect(rent.nextDueDate.map(Day.string) == "2026-12-01")
    }

    @Test("Recording a transfer schedule makes a transfer pair")
    func recordTransfer() throws {
        let current = Account(name: "Current"), saver = Account(name: "Saver")
        [current, saver].forEach(context.insert)
        let saving = schedule("FREQ=WEEKLY;BYDAY=FR", due: "2026-10-30", amount: -50, account: current)
        saving.transferToAccount = saver
        let made = try #require(try Scheduling.record(saving, in: context, locale: uk))
        #expect(Transfers.partner(of: made, in: context)?.account === saver)
        #expect(saver.balance == 50)
    }

    @Test("Recording the final occurrence ends the schedule")
    func finalOccurrence() throws {
        let twice = schedule("FREQ=MONTHLY;BYMONTHDAY=1;COUNT=2", due: "2026-11-01")
        try Scheduling.record(twice, in: context, locale: uk)
        #expect(twice.rrule.contains("COUNT=1"))
        try Scheduling.record(twice, in: context, locale: uk)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ScheduledTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    @Test("Skipping moves the due date on and records nothing")
    func skip() throws {
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-11-01")
        Scheduling.skip(rent, in: context)
        #expect(rent.nextDueDate.map(Day.string) == "2026-12-01")
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test("Deleting a schedule keeps what it recorded")
    func deleteKeepsTransactions() throws {
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-11-01")
        try Scheduling.record(rent, in: context, locale: uk)
        context.delete(rent)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test("Auto-post records missed and upcoming occurrences once")
    func autoPost() throws {
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-09-01")
        rent.autoPost = true
        rent.daysInAdvance = 5
        let paused = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-09-01")
        paused.autoPost = true
        paused.active = false
        #expect(Scheduling.autoPost(today: day("2026-10-27"), in: context, locale: uk) == 3)
        #expect(rent.nextDueDate.map(Day.string) == "2026-12-01")
        #expect(Scheduling.autoPost(today: day("2026-10-27"), in: context, locale: uk) == 0)
    }

    @Test("Due soon counts only active schedules within 7 days")
    func dueSoon() {
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-11-01")
        let pay = schedule("FREQ=WEEKLY;BYDAY=FR", due: "2026-10-30", amount: 500)
        let paused = schedule("FREQ=DAILY", due: "2026-10-28")
        paused.active = false
        let later = schedule("FREQ=MONTHLY", due: "2026-12-01")
        let summary = Scheduling.dueSoon([rent, pay, paused, later], today: day("2026-10-27"))
        #expect(summary == Scheduling.DueSoon(income: 500, outgoing: 1150, count: 2))
    }

    @Test("The forecast starts at the stored next due date and counts transfers in as deposits")
    func forecast() {
        let current = Account(name: "Current", openingBalance: 1000), saver = Account(name: "Saver")
        [current, saver].forEach(context.insert)
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-12-01", account: current)
        let toSaver = schedule("FREQ=MONTHLY;BYMONTHDAY=15", due: "2026-11-15", amount: -100, account: current)
        toSaver.transferToAccount = saver
        let end = day("2027-01-20")
        let rows = Forecast.rows(for: current, schedules: [rent, toSaver], through: end)
        #expect(rows.map { Day.string($0.date) } == ["2026-11-15", "2026-12-01", "2026-12-15", "2027-01-01", "2027-01-15"])
        let saverRows = Forecast.rows(for: saver, schedules: [rent, toSaver], through: end)
        #expect(saverRows.allSatisfy { $0.amount == 100 } && saverRows.count == 3)

        let balances = Forecast.balances(rows, start: 1000)
        #expect(balances[rows.last!.id] == -1600, "\(String(describing: balances[rows.last!.id])) rows \(rows.map(\.amount))")
        let without = Forecast.balances(rows, start: 1000, excluded: [rows[1].id])
        #expect(without[rows[0].id] == 900 && without[rows[1].id] == 900 && without[rows.last!.id] == 1000 - 300 - 1150)
        #expect(rent.nextDueDate.map(Day.string) == "2026-12-01")
        #expect(Day.string(Forecast.defaultEnd(today: day("2026-10-27"))) == "2027-01-27")
    }

    @Test("A paused schedule is left out of the forecast")
    func pausedForecast() {
        let current = Account(name: "Current")
        context.insert(current)
        let rent = schedule("FREQ=MONTHLY;BYMONTHDAY=1", due: "2026-11-01", account: current)
        rent.active = false
        #expect(Forecast.rows(for: current, schedules: [rent], through: day("2027-01-01")).isEmpty)
    }
}

@MainActor
@Suite("Schedule form and view")
struct ScheduleFormTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("Picking a transfer sets the to account")
    func transfer() throws {
        let current = Account(name: "Current"), saver = Account(name: "Saver")
        [current, saver].forEach(context.insert)
        var draft = ScheduleDraft(account: current)
        draft.payee = "Savings"
        draft.withdrawal = "50"
        draft.transferTo = saver
        draft.recurrence.frequency = .weekly
        draft.recurrence.weekdays = [4]
        let schedule = try draft.make(in: context)
        #expect(schedule.transferToAccount === saver && schedule.amount == -50 && schedule.rrule == "FREQ=WEEKLY;BYDAY=FR")
        #expect(ScheduleDraft(schedule).transferTo === saver)
        draft.transferTo = current
        #expect(!draft.isValid())
    }

    @Test("Sort and filter are remembered between launches")
    func remembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "schedule-view-\(UUID())"))
        var view = ScheduleView()
        view.sort = .amountHighest
        let account = UUID()
        view.accounts = [account]
        view.save(to: defaults)
        #expect(ScheduleView(defaults: defaults) == view)
    }

    @Test("Eight sort orders")
    func sorts() {
        let a = Account(name: "A"), b = Account(name: "B")
        let one = ScheduledTransaction(account: b, payee: "Rent", amount: -1150, rrule: "FREQ=MONTHLY")
        one.nextDueDate = Day.parse("2026-11-01")
        let two = ScheduledTransaction(account: a, payee: "Pay", amount: 2000, rrule: "FREQ=MONTHLY")
        two.nextDueDate = Day.parse("2026-10-30")
        #expect(ScheduleSort.allCases.count == 8)
        #expect(ScheduleSort.nextDue.sorted([one, two]).first === two)
        #expect(ScheduleSort.payee.sorted([one, two]).first === two)
        #expect(ScheduleSort.amountLowest.sorted([one, two]).first === one)
        #expect(ScheduleSort.accountZA.sorted([one, two]).first === one)
    }
}
