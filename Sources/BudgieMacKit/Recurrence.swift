import Foundation

/// The RFC 5545 repeat rules Budgie writes (`buildRRule.ts`): FREQ, INTERVAL,
/// BYDAY (with an optional position, like 1MO or -1FR), BYMONTHDAY (-1 is the
/// last day), UNTIL and COUNT. As in Budgie, a rule is read from the schedule's
/// current due date, so INTERVAL counts from there. COUNT is the number of
/// occurrences left, counting the current one; BudgieMac lowers it on each
/// record or skip, so the final occurrence ends the schedule.
public struct RRule: Equatable, Sendable {
    public enum Frequency: String, Sendable { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

    /// RFC weekday codes, Monday first.
    public static let weekdays = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
    /// The app's words are English (docs/GLOSSARY.md), so these don't follow the locale.
    public static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    public struct Weekday: Equatable, Hashable, Sendable {
        /// 0 = Monday … 6 = Sunday.
        public var day: Int
        /// 1…5 for first…fifth, -1 for last; nil for every.
        public var position: Int?

        public init(day: Int, position: Int? = nil) {
            self.day = day
            self.position = position
        }
    }

    public var frequency: Frequency
    public var interval = 1
    public var weekdays: [Weekday] = []
    public var monthDays: [Int] = []
    public var until: Date?
    public var count: Int?

    public init(frequency: Frequency) {
        self.frequency = frequency
    }

    public init?(_ text: String) {
        var parts: [String: String] = [:]
        for pair in text.replacingOccurrences(of: "RRULE:", with: "").split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { parts[kv[0].uppercased()] = kv[1] }
        }
        guard let freq = parts["FREQ"].flatMap({ Frequency(rawValue: $0.uppercased()) }) else { return nil }
        frequency = freq
        interval = parts["INTERVAL"].flatMap(Int.init) ?? 1
        weekdays = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { token in
            let code = String(token.suffix(2)).uppercased()
            guard let day = RRule.weekdays.firstIndex(of: code) else { return nil }
            let prefix = token.dropLast(2)
            return Weekday(day: day, position: prefix.isEmpty ? nil : Int(prefix.replacingOccurrences(of: "+", with: "")))
        }
        monthDays = (parts["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }
        count = parts["COUNT"].flatMap(Int.init)
        until = parts["UNTIL"].flatMap { value in
            let digits = value.prefix(8)
            guard digits.count == 8 else { return nil }
            return Day.parse("\(digits.prefix(4))-\(digits.dropFirst(4).prefix(2))-\(digits.suffix(2))")
        }
    }

    public var string: String {
        var parts = ["FREQ=\(frequency.rawValue)"]
        if interval > 1 { parts.append("INTERVAL=\(interval)") }
        if !weekdays.isEmpty {
            parts.append("BYDAY=" + weekdays.map { ($0.position.map(String.init) ?? "") + RRule.weekdays[$0.day] }.joined(separator: ","))
        }
        if !monthDays.isEmpty { parts.append("BYMONTHDAY=" + monthDays.map(String.init).joined(separator: ",")) }
        if let until { parts.append("UNTIL=" + Day.string(until).replacingOccurrences(of: "-", with: "") + "T000000Z") }
        if let count { parts.append("COUNT=\(count)") }
        return parts.joined(separator: ";")
    }

    /// "Once" is written as DAILY with COUNT=1 (Budgie's encoding).
    public var isOnce: Bool { frequency == .daily && count == 1 }

    /// "Once", "Monthly", "Every 2 weeks", "Last Friday monthly", …
    public var label: String {
        if isOnce { return "Once" }
        if frequency == .monthly, let first = weekdays.first, let position = first.position {
            let ordinal = [1: "First", 2: "Second", 3: "Third", 4: "Fourth", 5: "Fifth", -1: "Last"][position] ?? "First"
            return "\(ordinal) \(RRule.dayNames[first.day]) monthly"
        }
        let units = [Frequency.daily: ("Daily", "days"), .weekly: ("Weekly", "weeks"), .monthly: ("Monthly", "months"), .yearly: ("Yearly", "years")]
        let (single, plural) = units[frequency]!
        return interval > 1 ? "Every \(interval) \(plural)" : single
    }

    // MARK: - Occurrences

    /// The next occurrence on or after `day` (or strictly after, when
    /// `inclusive` is false), reading the rule from `anchor`. Nil when the rule
    /// has run out (UNTIL passed). COUNT is the caller's to track.
    public func next(after day: Date, anchor: Date, inclusive: Bool = false) -> Date? {
        let calendar = Day.calendar
        var candidate = inclusive ? day : calendar.date(byAdding: .day, value: 1, to: day)!
        for _ in 0..<(366 * 6) {
            if let until, candidate > until { return nil }
            if candidate >= anchor, matches(candidate, anchor: anchor) { return candidate }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate)!
        }
        return nil
    }

    func matches(_ day: Date, anchor: Date) -> Bool {
        let calendar = Day.calendar
        let d = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        let a = calendar.dateComponents([.year, .month, .day, .weekday], from: anchor)
        let weekday = (d.weekday! + 5) % 7 // Monday = 0
        switch frequency {
        case .daily:
            let days = calendar.dateComponents([.day], from: anchor, to: day).day!
            return days % interval == 0
        case .weekly:
            let anchorMonday = calendar.date(byAdding: .day, value: -((a.weekday! + 5) % 7), to: anchor)!
            let weeks = calendar.dateComponents([.day], from: anchorMonday, to: day).day! / 7
            guard weeks % interval == 0 else { return false }
            let days = weekdays.isEmpty ? [(a.weekday! + 5) % 7] : weekdays.map(\.day)
            return days.contains(weekday)
        case .monthly:
            let months = (d.year! - a.year!) * 12 + (d.month! - a.month!)
            guard months % interval == 0 else { return false }
            let length = calendar.range(of: .day, in: .month, for: day)!.count
            if !weekdays.isEmpty {
                return weekdays.contains { wd in
                    guard wd.day == weekday else { return false }
                    guard let position = wd.position else { return true }
                    let nth = (d.day! - 1) / 7 + 1
                    let fromEnd = (length - d.day!) / 7 + 1
                    return position > 0 ? nth == position : fromEnd == -position
                }
            }
            let days = monthDays.isEmpty ? [a.day!] : monthDays
            return days.contains { $0 > 0 ? $0 == d.day! : length + $0 + 1 == d.day! }
        case .yearly:
            let years = d.year! - a.year!
            return years % interval == 0 && d.month == a.month && d.day == a.day
        }
    }
}

/// The scheduled-transaction form's repeat fields, as in Budgie's
/// `RecurrenceConfig`; `rrule` and `init(rrule:)` round-trip.
public struct RecurrenceForm: Equatable, Sendable {
    public enum Frequency: String, CaseIterable, Sendable { case once = "Once", daily = "Daily", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly" }
    public enum WeekPosition: Int, CaseIterable, Sendable { case every = 0, first = 1, second = 2, third = 3, fourth = 4, fifth = 5, last = -1 }
    public enum End: String, CaseIterable, Sendable { case never = "Never", onDate = "On Date", afterCount = "After" }

    public var frequency: Frequency = .monthly
    /// Every N days or months.
    public var interval = 1
    /// Weekly: which weekdays (0 = Monday), and whether every week or the Nth in the month.
    public var weekdays: Set<Int> = []
    public var weekPosition: WeekPosition = .every
    /// Monthly: days 1…31, -1 for the last day.
    public var monthDays: Set<Int> = []
    public var end: End = .never
    public var endDate = Day.today
    public var endCount = 12

    public init() {}

    public var rrule: String {
        var rule: RRule
        switch frequency {
        case .once:
            rule = RRule(frequency: .daily)
            rule.count = 1
            return rule.string
        case .daily:
            rule = RRule(frequency: .daily)
            rule.interval = max(1, interval)
        case .weekly:
            let days = weekdays.sorted()
            if weekPosition == .every {
                rule = RRule(frequency: .weekly)
                rule.interval = max(1, interval)
                rule.weekdays = days.map { RRule.Weekday(day: $0) }
            } else {
                rule = RRule(frequency: .monthly)
                rule.weekdays = days.map { RRule.Weekday(day: $0, position: weekPosition.rawValue) }
            }
        case .monthly:
            rule = RRule(frequency: .monthly)
            rule.interval = max(1, interval)
            rule.monthDays = monthDays.sorted { ($0 < 0 ? 99 : $0) < ($1 < 0 ? 99 : $1) }
        case .yearly:
            rule = RRule(frequency: .yearly)
            rule.interval = max(1, interval)
        }
        switch end {
        case .never: break
        case .onDate: rule.until = endDate
        case .afterCount: rule.count = max(1, endCount)
        }
        return rule.string
    }

    public init(rrule text: String) {
        guard let rule = RRule(text) else { return }
        if rule.isOnce {
            frequency = .once
            return
        }
        if let until = rule.until {
            end = .onDate
            endDate = until
        } else if let count = rule.count {
            end = .afterCount
            endCount = count
        }
        interval = rule.interval
        switch rule.frequency {
        case .daily:
            frequency = .daily
        case .weekly:
            frequency = .weekly
            weekdays = Set(rule.weekdays.map(\.day))
        case .monthly:
            if let position = rule.weekdays.first?.position {
                frequency = .weekly
                weekPosition = WeekPosition(rawValue: position) ?? .first
                weekdays = Set(rule.weekdays.map(\.day))
                interval = 1
            } else {
                frequency = .monthly
                monthDays = Set(rule.monthDays)
            }
        case .yearly:
            frequency = .yearly
        }
    }
}
