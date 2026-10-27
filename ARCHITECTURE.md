# BudgieMac architecture

## Targets

- `BudgieMacKit` (library, no SwiftUI): the SwiftData models (`Schema.swift`), money and day rules (`Balances.swift`, `Day`), drafts that validate what sheets edit (`AccountDraft`, `TransactionDraft`), the register's running balance, transfers, deletion records for Undo, clearing, and the Budgie import. Everything here has unit tests in `Tests/BudgieMacKitTests`, which run without the app.
- `BudgieMac` (app): windows, menus, views, and `AppModel`. Depends on `BudgieMacKit`; never the other way.

## Layers in the app

- `App.swift`: scenes, menu commands, the store location.
- `Models.swift`: `AppModel` (sidebar selection, open sheets, selected rows) and the sidebar pages.
- Actions with Undo: `extension AppModel` in `TransactionActions.swift` (transactions) and `Models.swift` (`add` account). Views call these; they never edit models and register Undo themselves.
- Pages and sheets: `AccountsPage`, `RegisterPage`, `Sidebar`, `AddAccountSheet`, `TransactionSheet`, `ImportFlow`.
- Agent hooks: `SelfTest.swift`, `Snapshot.swift`, `SeedData.swift` (all refuse to run without `APP_STORE` in /tmp).

## Rules that hold everywhere

- Money is `Decimal`; shown with `Money.string`, typed amounts read with `Money.parse`.
- Days are midnight UTC; shown with `Day.formatted` only.
- Destructive confirmations are `NSAlert` sheets with Cancel first and default.
- A stored `PersistentIdentifier` is read through `selectedTransactionRows`, which skips deleted rows.
- `Transaction` and `Category` clash with SwiftUI and ObjectiveC names: the app has typealiases in `Models.swift`, tests declare a private one.

## Seams

- The store: `BudgieSchema.container(url:)` and `BudgieSchema.inMemory()` (tests).
- Undo: every action takes an `UndoManager?`, so tests pass their own.
