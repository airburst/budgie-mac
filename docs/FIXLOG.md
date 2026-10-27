# Fix log

## Crash on quit after deleting a selected transaction (S-009)
Symptom: "This model instance was invalidated because its backing data could no longer be found" when the Transaction menu redrew after a selected row was deleted.
Cause: `ModelContext.model(for:)` returns an instance even for a deleted row; reading any property of it traps.
Fix: `AppModel.selectedTransactionRows` uses `registeredModel(for:)` and skips rows that are deleted or have no context.
Rule: never read a model you got from a stored `PersistentIdentifier` without checking it still exists; go through `selectedTransactionRows`.

## Unit tests trapped inside SwiftData (S-001)
Symptom: the test runner died with signal 5 and no message.
Cause: a helper returned `container.mainContext` and let the `ModelContainer` go; a context without its container traps.
Fix: tests keep every container they open.
Rule: always keep the `ModelContainer` alive as long as any of its contexts.

## Last Reconciled showed the day before west of Greenwich (M1 review)
Symptom: All Accounts formatted Last Reconciled in the local time zone; days are stored at midnight UTC, so in the Americas it read one day early.
Cause: each screen built its own date format, and one forgot the UTC time zone.
Fix: `Day.formatted(_:_:)` in BudgieMacKit is the only way days are shown.
Rule: show stored days with `Day.formatted`, never `Date.formatted` directly.

## Soft delete read back as false after a save (S-017)
Symptom: deleting a category (or closing an account) set the flag, but after `context.save()` the property read `false` until the next fetch; the self-test caught it.
Cause: the attribute was called `deleted`, which is also Core Data's own `NSManagedObject.deleted` key under SwiftData.
Fix: renamed to `softDeleted` with `@Attribute(originalName: "deleted")` so existing stores migrate; a unit test reads it back after a save.
Rule: never name a SwiftData attribute after an NSManagedObject property (`deleted`, `inserted`, `updated`, `faulted`, `entity`, `objectID`, `description`).

## A row added while reconciling didn't stay ticked (S-024)
Symptom: the self-test found the new row missing from the ticked set.
Cause: its `persistentModelID` was stored before `context.save()`; saving replaces a new model's temporary id with a permanent one.
Fix: store ids of new models only after saving.
Rule: never keep a new model's `persistentModelID` from before its first save.

## Correct Decimal results failed their tests (M4, M5)
Symptom: `#expect(total == 4000 - 700 - 50)` failed while `#expect(total == 3250)` passed for the same value.
Cause: an arithmetic expression of integer literals beside a `Decimal` in `#expect` doesn't type-check the way it reads (it isn't evaluated as Decimal arithmetic).
Fix: write the expected amount as one literal, or build it with `Decimal(string:)`.
Rule: in tests, never compare a `Decimal` with arithmetic on bare literals; write the expected value out.

## Importing or restoring over existing budget data failed (found by the S-054 self-test)
Symptom: restoring a backup left the data unchanged; Core Data logged "Batch delete failed due to mandatory OTO nullify inverse on BudgetAllocation/envelope". The same path is S-002's import, so importing a Budgie file over a BudgieMac with envelopes would also have failed.
Cause: `BudgieImport.deleteEverything` used `context.delete(model:)`, a store-level batch delete that Core Data refuses when related rows exist. The S-002 unit test only replaced a lone account in memory.
Fix: delete row by row through the context; a regression test imports twice over a full store on disk.
Rule: never use `ModelContext.delete(model:)` on models with relationships; test replace-all paths on a full store on disk.

## Forecast counted future register entries as already paid (2026-10-27)

Symptom: the forecast started from the account's full balance, so a register entry dated 20 Nov (-£1,799) lowered the line from today instead of on 20 Nov. It started £1,869 below Budgie's forecast for the same data.
Cause: `ForecastView` started from `Account.balance`, which sums every transaction whatever its date, and listed only scheduled rows. Budgie starts from the opening balance plus transactions dated today or earlier, and adds later register entries as rows. It also skips scheduled dates on or before today.
Fix: `Forecast.startBalance(of:today:)`, register rows dated after today in `Forecast.rows`, overdue schedule dates skipped, and a test with a future-dated entry.
Rule: anything that projects balances forward starts from the balance as of today, never from `Account.balance`.
