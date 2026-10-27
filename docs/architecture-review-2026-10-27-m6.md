# Architecture review, end of M6

No Strong candidates; nothing refactored. Reports.swift keeps every number behind small pure functions with tests; ReportsPage only draws. Chart colours live in one place (`ChartColors`), validated with the dataviz script for light and dark.

Watch: `Reports.netWorth` sums each account's transactions per month (accounts × months × transactions). Fine for a year of personal data; precompute month-end balances if This Year with 10,000+ transactions feels slow.
