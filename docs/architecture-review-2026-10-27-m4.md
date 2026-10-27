# Architecture review, end of M4

Sources: 6,263 lines. Largest: BudgieImport (410), Schema (344), Snapshot (288), Recurrence (235), SelfTest (232). No Strong candidates; nothing refactored.

- Recurrence engine (Recurrence.swift) is deep: a small interface (`RRule`, `RecurrenceForm`, `next(after:anchor:)`) over day-by-day evaluation, fully unit tested. Keep it.
- Snapshot.swift and SelfTest.swift each grow by a block per feature. Same plan as before: split into per-feature files (`Snapshot+Scheduled.swift` …) when either passes 400 lines.
- Forecast and the 7-day summary walk occurrences day by day; fine at personal scale (6 schedules × 3 months). Measure if someone forecasts years ahead.

Top recommendation: none this milestone.
