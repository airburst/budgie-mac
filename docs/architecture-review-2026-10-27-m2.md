# Architecture review, end of M2

Sources: 4,534 lines; largest `BudgieImport.swift` (410). No duplicate private types. Fix log: 4 entries, all in different areas; the last (Core Data's `deleted` key) has its rule recorded.

## Counted words live in ImportFlow  [Strong]

Files: ImportFlow.swift, AccountActions.swift, CategoryActions.swift, PayeeActions.swift
Signal: four features call `ImportFlow.count(_:_:)` for "3 transactions".
Problem: a plural helper inside the import flow; a feature that never imports reaches into it.
Proposal: `Words.count(_:_:)` in BudgieMacKit, with a test. Pure move.
Plan: 1 commit.

## Snapshot.swift grows by a block per story  [Worth exploring]

Files: Snapshot.swift (234 lines), five copies of "end every sheet".
A table of named captures (`[(key, setUp, tearDown)]`) would keep it flat. Revisit when it passes 400 lines; for now add a `dismissSheets()` helper the next time it's touched.

## Balances computed on every draw  [Speculative]

Unchanged from the M1 review: measure with a real export first.

Top recommendation: the Words move.
