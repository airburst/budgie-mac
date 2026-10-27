# Architecture review, end of M3

Sources: 4,986 lines; no file over 410. No Strong candidates; nothing refactored.

## PersistentIdentifier handling  [Worth exploring]

Two fix-log entries in this area (a deleted row read through `model(for:)`, a new row's temporary id kept before saving). A third would justify a small `RowRef` wrapper in the app that saves before it hands out an id and resolves only live rows. Until then the rules in docs/FIXLOG.md and `selectedTransactionRows` cover it.

## Snapshot.swift  [Worth exploring]

253 lines and a block per feature. Same plan as the M2 review: a table of named captures when it passes 400.

Top recommendation: none this milestone.
