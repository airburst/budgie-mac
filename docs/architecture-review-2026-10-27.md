# Architecture review, 2026-10-27 (end of M1)

Signal: end of milestone M1. 4,067 lines; largest file `BudgieMacKit/BudgieImport.swift` (410). No file near 600 lines, no duplicate private types, two unrelated fix-log entries. The code is in good shape; the cards below are about locality.

## Calendar days shown in one way  [Strong]

Files: RegisterPage.swift (2 places), TransactionSheet.swift, DeleteTransactions.swift, AccountsPage.swift
Signal: the same `Date.FormatStyle(..., timeZone: UTC)` written four times, and a fifth place that forgot it.
Problem: days are stored at midnight UTC (`Day`), so every display must format in UTC. AccountsPage formats Last Reconciled in the local time zone: west of Greenwich it shows the day before. Each new screen is another chance to forget.
Proposal: in BudgieMacKit,
```swift
public extension Day {
    static func formatted(_ date: Date, _ style: Date.FormatStyle.DateStyle = .numeric) -> String
}
```
Benefits: locality (one place knows days are UTC); the Last Reconciled bug is fixed by construction; a unit test pins it in a time zone west of UTC.
Proof of same behavior: unit tests, self-test, register and accounts snapshots look the same in London.
Plan: 1 commit (add, test, move the five callers).

## Transaction actions in one file  [Strong]

Files: Models.swift (add, edit), DeleteTransactions.swift (delete, clearing, an NSApplication helper)
Signal: S-006 to S-009 touched the same actions across two files; the file name `DeleteTransactions.swift` no longer says what is in it.
Problem: to change how undo works for transactions you read two files, and the window helper hides in a delete file.
Proposal: `TransactionActions.swift` with `extension AppModel` for new, add, edit, delete, clearing and their undo; `NSApplication.mainAppWindow` moves to `UI/WindowBehavior.swift`. Pure move, no interface change.
Benefits: locality for every M2 transaction story (transfers, payees).
Proof of same behavior: self-test (26 checks) and unit tests pass unchanged.
Plan: 1 commit.

## Destructive confirmation  [Worth exploring]

Files: ImportFlow.swift, DeleteTransactions.swift
Two NSAlerts built the same way (Cancel first and default, destructive second). A third copy (Close Account…, S-010) would justify `ConfirmDestructive(title:message:action:)`. Wait for it.

## Balances computed on every draw  [Speculative]

Account.balance sums `transactions` each time the sidebar, table and subtitle draw. Fine at 2,000 rows (self-test); measure with a real Budgie export before caching.

Top recommendation: both Strong cards, the day format first because it fixes a bug.
