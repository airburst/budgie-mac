# BudgieMac architecture

## Targets

- `BudgieMacKit` (library, no SwiftUI): the SwiftData models (`Schema.swift`), money and day rules (`Balances.swift`, `Day`), drafts that validate what sheets edit (`AccountDraft`, `TransactionDraft`), the register's running balance, transfers, deletion records for Undo, clearing, and the Budgie import. Everything here has unit tests in `Tests/BudgieMacKitTests`, which run without the app.
- `BudgieMac` (app): windows, menus, views, and `AppModel`. Depends on `BudgieMacKit`; never the other way.

## Layers in the app

- `App.swift`: scenes, menu commands, the store location.
- `Models.swift`: `AppModel` (sidebar selection, open sheets, selected rows) and the sidebar pages.
- Actions with Undo: `extension AppModel` in `TransactionActions.swift`, `AccountActions.swift`, `CategoryActions.swift` and `PayeeActions.swift`. Views call these; they never edit models and register Undo themselves.
- Destructive confirmations: `UI/Confirm.swift`.
- Pages and sheets: `AccountsPage`, `RegisterPage`, `CategoriesPage`, `PayeesPage`, `Sidebar`, `AccountSheet`, `TransactionSheet`, `CategorySheet`, `ImportFlow`. Each sheet's open state is an optional mode on `AppModel`, so snapshot mode can open it.
- Agent hooks: `SelfTest.swift`, `Snapshot.swift`, `SeedData.swift` (all refuse to run without `APP_STORE` in /tmp).

## Rules that hold everywhere

- Money is `Decimal`; shown with `Money.string`, typed amounts read with `Money.parse`.
- Days are midnight UTC; shown with `Day.formatted` only.
- Destructive confirmations are `NSAlert` sheets with Cancel first and default.
- A stored `PersistentIdentifier` is read through `selectedTransactionRows`, which skips deleted rows.
- Soft delete is `softDeleted`, never `deleted` (Core Data's own key).
- Counted words ("3 transactions") come from `Words.count`.
- `Transaction` and `Category` clash with SwiftUI and ObjectiveC names: the app has typealiases in `Models.swift`, tests declare a private one.

## Seams

- The store: `BudgieSchema.container(url:)` and `BudgieSchema.inMemory()` (tests).
- Undo: every action takes an `UndoManager?`, so tests pass their own.
