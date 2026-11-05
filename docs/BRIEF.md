# BudgieMac

A native Mac app for one person to track accounts, scheduled bills and an envelope budget, with all data kept on the Mac.

Bundle id: `net.fairhursts.budgiemac` (decided by the agent, from budget.fairhursts.net). Installs next to the Electron `Budgie.app`, not over it.

## Replaces

Budgie (Electron + React + SQLite, `/Users/mark/dev/budgie`), used on the desktop and at budget.fairhursts.net. BudgieMac opens Budgie's export file, so you can switch with no data loss and switch back.

## Main jobs

1. Keep each account's register up to date: add, edit and mark transactions as cleared, then reconcile them against the statement.
2. Stay ahead of what's coming: record or skip scheduled transactions and forecast an account's balance.
3. Give every pound a job: assign money to envelopes each month and see what's still available.
4. Look back: spending by category, income vs expenses, and net worth.

## Data

- Account: name, type (bank, credit card, loan, investment, cash), number, opening balance, currency, interest rate, credit limit, closed, pending reconciliation
- Transaction: account, date, payee, signed amount (`Decimal`), category, notes, cleared, reconciled, linked transfer
- Category: name, parent (two levels), type (expense, income, transfer)
- Payee: name, default category, default amount
- Scheduled transaction: account, payee, amount, category, repeat rule (RFC 5545 RRULE), next due, auto-record N days ahead, active, transfer-to account
- Envelope, envelope categories, monthly assigned amount, money moved between envelopes
- Reconciliation: account, statement date, statement balance
- Preferences: appearance, open on launch, payee autofill, account shortcuts, backup folder and retention

That's more than the usual two to four types, because it's a straight port of a working data model, and every type is needed by M1–M5 (see `STORIES.md`).

## Shape

A single window with a sidebar: All Accounts, one row per account, Scheduled, Budget, Reports, Categories, Payees. Edits happen in sheets, and Settings is its own window. Needs macOS 26 or later. SwiftData store in Application Support, works offline, no accounts.

## System hooks

A full menu bar with Command shortcuts (S-049), import and export of Budgie data files, QIF import with drag and drop onto a register, and a backup on quit. Nothing beyond the app's own window in version one.

## Reference

Budgie itself; see `docs/screens/INDEX.md` (71 screens) and `docs/GLOSSARY.md` for names.

## Look

Native Mac: sidebar, toolbar, `Table`, sheets and the system accent colour (decided by the agent). Budgie's look is generic web UI, so it's not cloned. Two colours are kept from Budgie on purpose: green for money in and red for money out, always paired with a sign or icon. A Liquid Glass icon of its own (S-059).

## Not in version one

- Sync between Macs (later: iCloud) and the web/PWA version
- Exchange rates: totals are shown per currency instead
- Quick-add panel, menu bar item, Shortcuts actions, CLI/MCP
- Phone and narrow layouts, auto-update, moving the data folder
