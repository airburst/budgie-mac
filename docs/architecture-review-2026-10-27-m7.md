# Architecture review, end of M7

Sources 8,666 lines; largest BudgieImport (415), Schema (344), Snapshot (334), SelfTest (320). No Strong candidates.

- The fix log now has two entries about SwiftData behaviour under real stores (batch delete, `deleted` key). Both rules are recorded; tests now use stores on disk for replace-all paths.
- BudgieImport and BudgieExport mirror each other field by field; a field added to the schema must be added to both. The export round-trip test catches a missed field only when the fixture has it, so new fields need a fixture value too.
- Snapshot.swift and SelfTest.swift: split per feature when either passes 400.
