import Foundation
import Testing
@testable import BudgieMacKit

/// S-025 and S-026: repeat rules.
@Suite("Recurrence")
struct RecurrenceTests {
    private func day(_ text: String) -> Date { Day.parse(text)! }

    @Test("Frequency labels come from the rule", arguments: [
        ("FREQ=DAILY;COUNT=1", "Once"),
        ("FREQ=DAILY", "Daily"),
        ("FREQ=DAILY;INTERVAL=3", "Every 3 days"),
        ("FREQ=WEEKLY;BYDAY=MO", "Weekly"),
        ("FREQ=WEEKLY;INTERVAL=2;BYDAY=FR", "Every 2 weeks"),
        ("FREQ=MONTHLY;BYMONTHDAY=1", "Monthly"),
        ("FREQ=MONTHLY;INTERVAL=3", "Every 3 months"),
        ("FREQ=MONTHLY;BYDAY=-1FR", "Last Friday monthly"),
        ("FREQ=YEARLY", "Yearly"),
    ])
    func labels(_ text: String, label: String) {
        #expect(RRule(text)?.label == label)
    }

    @Test("Next occurrences", arguments: [
        ("FREQ=MONTHLY;BYMONTHDAY=1", "2026-10-01", "2026-11-01"),
        ("FREQ=MONTHLY;BYMONTHDAY=-1", "2026-01-31", "2026-02-28"),
        ("FREQ=MONTHLY;BYMONTHDAY=31", "2026-01-31", "2026-03-31"),
        ("FREQ=MONTHLY;BYMONTHDAY=1,15", "2026-10-01", "2026-10-15"),
        ("FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=10", "2026-10-10", "2026-12-10"),
        ("FREQ=WEEKLY;BYDAY=MO,TH", "2026-10-26", "2026-10-29"),
        ("FREQ=WEEKLY;INTERVAL=2;BYDAY=FR", "2026-10-30", "2026-11-13"),
        ("FREQ=MONTHLY;BYDAY=-1FR", "2026-10-30", "2026-11-27"),
        ("FREQ=MONTHLY;BYDAY=1MO", "2026-10-05", "2026-11-02"),
        ("FREQ=DAILY;INTERVAL=3", "2026-10-27", "2026-10-30"),
        ("FREQ=YEARLY", "2026-02-14", "2027-02-14"),
        ("FREQ=MONTHLY", "2026-10-15", "2026-11-15"),
    ])
    func next(_ text: String, from: String, expected: String) throws {
        let rule = try #require(RRule(text))
        #expect(rule.next(after: day(from), anchor: day(from)).map(Day.string) == expected)
    }

    @Test("UNTIL ends a rule")
    func until() throws {
        let rule = try #require(RRule("FREQ=MONTHLY;BYMONTHDAY=1;UNTIL=20261015T000000Z"))
        #expect(rule.next(after: day("2026-10-01"), anchor: day("2026-10-01")) == nil)
    }

    @Test("The form writes a rule that parses back into the same form", arguments: [
        "FREQ=DAILY;COUNT=1",
        "FREQ=DAILY;INTERVAL=2",
        "FREQ=WEEKLY;BYDAY=MO,WE",
        "FREQ=MONTHLY;BYDAY=-1FR",
        "FREQ=MONTHLY;BYDAY=2TU",
        "FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=1,15,-1",
        "FREQ=MONTHLY;BYMONTHDAY=28;COUNT=6",
        "FREQ=YEARLY;UNTIL=20301231T000000Z",
    ])
    func roundTrip(_ text: String) {
        let form = RecurrenceForm(rrule: text)
        #expect(form.rrule == text)
        #expect(RecurrenceForm(rrule: form.rrule) == form)
    }
}
