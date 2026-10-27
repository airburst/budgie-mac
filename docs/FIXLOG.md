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
