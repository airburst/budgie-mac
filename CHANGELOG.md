# BudgieMac changelog

## 1.1.2

- Forecast chart fills at least half the page
- Add the bama skills to the repo so every clone has them

## 1.1.1

- BudgieMac checks for updates at every launch and shows the update alert; Later reminds you a day on

## 1.1.0

- Install and Relaunch: BudgieMac downloads a new version, checks it, replaces itself and reopens, with no quarantine warning
- BudgieMac tells you when a newer version is on GitHub, with a Download button, and Check for Updates… in the app menu

## 1.0.1

- Publish a release from this Mac with bun run release: picks the version, tests, builds, zips, tags and uploads to GitHub
- Shortcut test reads the glossary table cell by cell, so column padding doesn't break it
- Add a README: what the app does, how to build, test and run it
- Docs clean up
- Recording a scheduled transaction dates it today, and a reconcile under way picks it up and re-tries the auto-match
- Reconcile: tick boxes sit next to the amounts, and the row under the pointer is highlighted
- Use the Budgie piggy bank icon from the Electron app
- Drag accounts in the sidebar into any order, which is remembered
- Forecast chart uses the Net Worth style: a shaded area under a 2 pt line
- Keep the Net Worth hover lookup off the grid lint
- Reports match Budgie's 90-day range, figures are as of today, and Net Worth reads out a month on hover
- Forecast starts from today's balance, shows future register entries on their day, and reads out the balance on hover
- Make every day button in a monthly schedule the same width
- Give BudgieMac its own icon: a budgie on a perch
- Show the version and what's new in About BudgieMac
- Helpful empty states, and money colours that read in dark and light
- Record the M7 architecture review (no refactor needed)
- Settings: appearance, start page, autofill, account shortcuts and backups
- Put every command in the menu bar with its shortcut
- Import transactions from a QIF file with duplicates flagged
- Make the register search self-test check able to fail
- Find a transaction by searching the register
- Export all data as a Budgie data file
- Record the M6 architecture review (no refactor needed)
- Mark Swift Charts grouping as not a layout nudge for grid-lint
- Reports: spending, income vs expenses, net worth, and summary figures
- Record the M5 architecture review (no refactor needed)
- Put the budget's Available column on the 4 pt grid
- Budget with envelopes: templates, assigning, moving money, copying a month
- Record the M4 architecture review (no refactor needed)
- Forecast an account's balance and try what-ifs
- Schedule repeating transactions: list, add, edit, pause, record, skip, delete
- Record the M3 architecture review (no refactor needed)
- Reconcile an account against a statement
- Move counted words to BudgieMacKit; record the M2 review
- Browse, add, edit, rename and delete payees
- Add, rename and delete categories; fix soft delete reading back false
- Browse and search categories
- Pick categories and payees by typing, and move money between accounts
- Hide reconciled or cleared transactions with the register's Filter menu
- Edit or close an account
- Keep every transaction action and its Undo in TransactionActions.swift
- Show every stored day through Day.formatted
- Mark transactions as cleared with a click, Space, or ⌘K
- Delete transactions with the Delete key, Edit > Delete, or the context menu
- Edit a transaction by double-clicking it, pressing Return, or ⌘E
- Add a transaction with ⌘N in a register
- Open an account's register with a running balance on every row
- Add an account with File > New Account… (⇧⌘N)
- See every account and its balance on All Accounts and in the sidebar
- Import Budgie data with File > Import Budgie Data…
- Keep every account, transaction, schedule and budget between launches
- Open BudgieMac with an All Accounts list and the brief's sidebar pages
- Create BudgieMac from the macOS app template

## 1.0.0

The first native Mac version of Budgie.

- Accounts and registers: add, edit, close; transactions with Undo; cleared and reconciled status; search; filters.
- Import and export Budgie data files, so you can switch either way. Import QIF files with duplicates flagged.
- Categories and payees, with type-ahead and payee autofill. Transfers between accounts.
- Reconcile against a statement, with automatic matching and Auto Balance.
- Scheduled transactions with full repeat rules, automatic recording, and a balance forecast.
- Envelope budget with templates, moving money, and copying last month.
- Reports: spending by category, income and expenses, net worth, and summary figures per currency.
- Every command in the menu bar; account shortcuts; backups on quit with restore.

Fixed from Budgie: totals no longer add euros to pounds; Available to Budget counts all income so far; a reconcile uses the same cleared balance as the Accounts page; forecasts start at each schedule's next due date; duplicate category names are refused; payees can be renamed; confirmations say what they will delete.
