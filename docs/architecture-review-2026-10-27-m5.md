# Architecture review, end of M5

Sources ~7,000 lines; no file over 410. No Strong candidates; nothing refactored.

- Budget.swift keeps the whole computation behind `Budget.summary(for:...)`, precomputing per-month sums once; the page passes its @Query arrays so SwiftUI redraws on any change. Deep and tested.
- The fix log gained a test-writing rule (Decimal literal arithmetic in #expect). Not a code area.
- SelfTest.swift is approaching 300 lines; split per milestone (SelfTest+Budget.swift …) when it passes 400.

Top recommendation: none.
