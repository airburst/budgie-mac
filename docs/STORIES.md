# BudgieMac stories

Names on screen come from `docs/GLOSSARY.md`.

BudgieMac is a native macOS rebuild of Budgie (`/Users/mark/dev/budgie`), a
local-first personal finance app. Source of truth for behaviour:
`docs/screens/INDEX.md` (screens) and the Budgie source (read-only).

Ground rules for every story:

- Money is stored as `Decimal`, never `Double`. Amounts always show as
  currency with sign first and thousands separators ("-£1,150.00").
- Account numbers are masked ("•• 4321") everywhere except the account form.
- Dates show in the user's locale format.
- Known Budgie defects are fixed, not copied. They are called out with
  "Fixes:" in the story.

## M1 Core loop: track money in accounts

The app does one job end to end: you can bring your Budgie data over, see
your accounts, and keep a register up to date. Data survives a restart.

### S-001 Keep data between launches
As the user, I quit and reopen the app and everything I entered is still there.
Screens: none (no UI)
Acceptance:
- [unit] Account, Transaction, Category, Payee, ScheduledTransaction, Envelope, EnvelopeCategory, BudgetAllocation, BudgetTransfer, AccountReconciliation and Preferences round-trip through the store with every field from `schema.ts`.
- [unit] Amounts are `Decimal`; 0.1 + 0.2 stored and read back equals 0.3 exactly.
- [unit] Deleting an account or category is a soft delete (`deleted = true`) and hides it from lists.
- [self] The self-test writes a transaction, reloads the store and finds it.
Status: done

### S-002 Import my data from Budgie
As the user, I choose File > Import Budgie Data… and pick a Budgie data file, and all my accounts, transactions, schedules and budget appear.
Screens: 59-settings-advanced.png
Depends: S-001
Acceptance:
- [unit] A Budgie portable data package (format version 1, `src/services/portable-data.ts`) imports with the same row counts per table as the source.
- [unit] Transfer pairs keep their link, and categories keep their parents.
- [unit] An unsupported format version is refused with a message naming the version.
- [snap] A confirmation says that importing replaces all data in BudgieMac, with a destructive "Replace All Data" button and Cancel as the default.
- [manual] Import a real export from the Budgie web app; balances on the Accounts page match Budgie to the penny.
UX:
- Flow: File > Import Budgie Data…, or "Import from Budgie…" in the All Accounts empty state -> open panel (Budgie data files only) -> if BudgieMac already has data, a confirmation -> progress sheet -> All Accounts with a banner of what was imported
- Surface: open panel, then a confirmation dialog (destroys data and can't be undone), then a sheet with a progress bar only if it takes longer than half a second
- States: empty BudgieMac imports with no confirmation; loading "Importing 1,234 transactions…" with a bar and no Cancel, because the import is all or nothing; error alert "Unable to import "file.json"" plus the reason ("This file was made by a newer Budgie (format 2). Update BudgieMac to import it."); done: an inline banner at the top of All Accounts, "Imported 7 accounts and 1,234 transactions from Budgie.", with a close button
- Words: menu "Import Budgie Data…"; confirmation title "Replace All Data with This Budgie File?", message "Your 7 accounts and 1,234 transactions in BudgieMac will be replaced. This can't be undone. Export your data first if you want a copy.", buttons "Replace All Data" (destructive) and "Cancel" (default)
- Access: the open panel and the confirmation work by keyboard (Escape cancels both); the banner is announced to VoiceOver when it appears
Status: done (the [manual] check with a real Budgie export is still to do; no progress sheet yet, since imports finish at once)

### S-003 See all my accounts and their balances
As the user, I open the app and see every account with its balance in the sidebar, and a table of accounts with totals on the Accounts page.
Screens: 10-home.png, 70-dark-home.png
Depends: S-001
Acceptance:
- [snap] The sidebar lists open accounts with their balances, green when positive and red when negative.
- [snap] The Accounts page shows a total card and a table: name, type and masked number, Balance, Cleared balance, Last reconciled (date or "Never"), Remaining credit (credit cards with a limit only).
- [unit] Balance = opening balance + all transactions; Cleared balance = opening balance + cleared transactions; Remaining credit = limit + balance.
- [unit] Totals are added up per currency. A EUR account is never added to the GBP total (Fixes: non-GBP accounts summed as GBP).
UX:
- Flow: launch or ⌘1, or click "All Accounts" at the top of the sidebar -> totals card and accounts table -> double-click a row or select an account in the sidebar to open it
- Surface: sidebar page (a place people come back to); sidebar = "All Accounts", an "Accounts" section with one row per open account, then Scheduled, Budget, Reports, Categories, Payees
- States: empty "No Accounts" / "Add an account to start tracking your money, or bring everything over from Budgie." with "Add Account…" (primary) and "Import from Budgie…"; too much: account names truncate in the middle with the full name as a tooltip; balances use monospaced digits so they line up
- Words: page title "All Accounts"; card "Total Balance" with the note "Sum of account balances, not cash you can spend" (one line per currency); columns "Account", "Balance", "Cleared Balance", "Last Reconciled", "Remaining Credit"; "Never" when not reconciled
- Context menu on an account (sidebar and table): "Open", "Edit Account…", "Reconcile…", "Close Account…"
- Access: negative amounts show a minus sign as well as red; VoiceOver reads a sidebar row as "Everyday Current, balance £4,778.58"; ↑/↓ move through the sidebar and Return opens
Status: done (context menu has Open; Edit Account…, Reconcile… and Close Account… arrive with S-010 and the reconcile story)

### S-004 Add an account
As the user, I click Add Account, fill in name, type, number, opening balance and currency, and the account appears in the sidebar.
Screens: 22-account-add.png
Depends: S-003
Acceptance:
- [snap] The New Account sheet has Name, Type (Bank, Credit card, Loan, Investment, Cash), Account number (optional), Opening balance, Currency; Credit card also shows Credit limit.
- [snap] Interest rate is offered for every account type (Fixes: interest rate only for card and loan).
- [self] Add Account stays disabled until Name is filled; Return adds the account and Escape cancels.
- [unit] A new account's opening balance is stored as given and its currency defaults to GBP.
UX:
- Flow: File > New Account… (⇧⌘N), the + button at the bottom of the sidebar, or the empty state -> sheet with focus in Name -> Return adds -> the new account is selected in the sidebar, its register is open, and ⌘Z offers "Undo Add Account"
- Surface: sheet (one short task that must finish or cancel)
- States: Type defaults to Bank and Currency to the Mac's region (GBP); Opening balance defaults to 0.00; Credit Card shows Credit limit; Interest rate is optional for every type; inline note under Name "Another account is already called "Wallet"." (a warning only: adding is still allowed); a footnote under Opening balance "Type and opening balance can't be changed after adding."
- Words: title "Add Account"; labels "Name", "Type", "Account Number (optional)", "Opening Balance", "Currency", "Credit Limit", "Interest Rate (%)"; buttons "Add Account" (default) and "Cancel"; + tooltip "Add an account (⇧⌘N)"
- Access: Tab moves in label order; Type is a pop-up button that can be chosen by typing; every field has a VoiceOver label that matches its visible label
Status: done

### S-005 Open an account's register
As the user, I select an account in the sidebar and see its transactions with a running balance.
Screens: 11-account-register.png, 12-account-credit-card.png, 71-dark-register.png
Depends: S-003
Acceptance:
- [snap] The register is a table with columns Date, Payee, Category, Amount, Balance, Status, oldest first, and a toolbar with Add, Filter, Reconcile and Forecast.
- [snap] Withdrawals show in red, deposits in green, and category as a pill.
- [unit] The running balance is correct on every row, and the Balance column shows it on every row (Budgie showed it only on uncleared rows).
- [self] With 2,000 transactions the register opens in under 300 ms.
UX:
- Flow: select an account in the sidebar (or a custom account shortcut, S-050) -> register scrolled to the newest transaction at the bottom, with nothing selected -> ↑/↓ select, Return edits, Space marks as cleared
- Surface: sidebar page with a Table; the window title is the account name, and the subtitle shows "Balance £4,778.58 · Cleared £5,137.22"
- Toolbar: "Add Transaction" (+), Filter menu (shows "Hiding Reconciled" when on), "Reconcile…", "Forecast", and search (S-051)
- States: empty "No Transactions" / "Add the first transaction for Everyday Current." with "Add Transaction"; filtered-to-nothing "All transactions are hidden by the current filter." with "Show All"; too much: payee and notes truncate with a tooltip, and 10,000 rows scroll smoothly (lazy Table)
- Words: columns "Date", "Payee", "Category", "Amount", "Balance", "Status"; status shows "Uncleared", "Cleared" or "Reconciled" with an icon (empty circle, checkmark circle, lock)
- Access: colour is never the only signal (minus sign, status icon and word); VoiceOver reads a row as "10 August 2026, Corner Grocer, Groceries, minus £70.20, balance £5,082.22, cleared"
Status: done (Filter, Reconcile… and Forecast are in the toolbar but disabled until S-011, reconciliation and forecast; Add Transaction is wired in S-006; the 300 ms check times the fetch and running balance, not drawing)

### S-006 Add a transaction
As the user, I press Command-N in a register, enter date, payee, category, withdrawal or deposit, notes and cleared, and the row appears in the register.
Screens: 26-transaction-add-empty.png, 27c-transaction-add-date-picker.png, 75-dark-transaction-add.png
Depends: S-005
Acceptance:
- [snap] The sheet has Date (defaults to today), Payee, Category, Withdrawal, Deposit, Notes and Cleared.
- [unit] A withdrawal saves as a negative amount and a deposit as a positive one; filling both is refused.
- [unit] Saving a transaction with a new payee name creates a Payee.
- [self] Return saves, Escape cancels, and the account balance updates at once.
UX:
- Flow: ⌘N, the toolbar +, File > New Transaction, or the empty state -> sheet with focus in Payee, Date today, Account = the open account -> type the payee (S-013 fills in the rest) -> Tab to Withdrawal or Deposit -> Return adds -> sheet closes, the new row is selected and scrolled into view, and ⌘Z offers "Undo Add Transaction"
- Surface: sheet (one short task); ⌘N again right away starts the next one, so entering a statement's worth stays fast
- States: typing in Withdrawal clears Deposit and the reverse; inline error under the amounts "Enter a withdrawal or a deposit." when Return is pressed with both empty; a date more than a year from today shows an inline note "That's more than a year from today." (adding still allowed)
- Words: title "Add Transaction"; labels "Date", "Payee", "Category", "Withdrawal", "Deposit", "Notes", "Cleared"; buttons "Add Transaction" (default) and "Cancel"; + tooltip "Add a transaction to this account (⌘N)"
- Access: the date field works by keyboard (↑/↓ change the focused part); Tab order Date -> Payee -> Category -> Withdrawal -> Deposit -> Notes -> Cleared; VoiceOver labels match the visible labels
Status: done

### S-007 Edit a transaction
As the user, I double-click a transaction (or select it and press Return) and change any field.
Screens: 28-transaction-details.png, 29-transaction-edit.png
Depends: S-006
Acceptance:
- [snap] The edit sheet opens prefilled; category shows its full path ("Household > Groceries").
- [self] Changing the amount updates the running balance and the account totals.
- [unit] Editing one half of a transfer updates the other half.
UX:
- Flow: double-click a row, select it and press Return, or Edit Transaction… (⌘E) in the context menu -> the same sheet prefilled, focus in Payee -> Return saves -> the row updates in place, and ⌘Z offers "Undo Edit Transaction"
- Surface: sheet; Budgie's read-only "Transaction Details" step is dropped because the row already shows those details
- States: editing a reconciled transaction shows an inline warning at the top: "This transaction is reconciled. Changing the amount or account will unbalance the reconciliation of 22 Sep 2026."; editing one half of a transfer shows "Changes also apply to the matching transfer in Rainy Day Saver."
- Words: title "Edit Transaction"; buttons "Save" (default) and "Cancel"; closing with edits asks nothing, because Cancel is intentional and ⌘Z covers mistakes after Save
- Access: same as S-006
Status: done

### S-008 Delete a transaction
As the user, I select a transaction and press Delete, confirm, and it is gone.
Screens: 30-transaction-delete-confirm.png
Depends: S-006
Acceptance:
- [self] Deleting asks nothing, because ⌘Z ("Undo Delete Transaction") restores it, including both halves of a transfer.
- [snap] Deleting a reconciled transaction asks first, and the question names the payee, date and amount (Fixes: the confirmation doesn't say which transaction).
- [unit] Deleting one half of a transfer deletes both halves.
UX:
- Flow: select one or more rows -> Delete key, Edit > Delete, or "Delete" in the context menu -> rows are removed and the balance updates -> ⌘Z offers "Undo Delete Transaction" ("Undo Delete 3 Transactions")
- Surface: none for normal transactions (Undo makes a confirmation unnecessary); a confirmation dialog only when a selected transaction is reconciled
- States: confirmation title "Delete the Reconciled Transaction "Corner Grocer", 10 Aug 2026, -£70.20?" with the message "This changes the reconciled balance of Everyday Current."; for several rows: "Delete 3 Transactions, Including 1 Reconciled?"
- Words: buttons "Delete" (destructive) and "Cancel" (default); menu item "Delete"
- Access: the Delete key works whenever the table has focus; VoiceOver announces "3 transactions deleted"
Status: done

### S-009 Mark a transaction as cleared
As the user, I click the cleared checkbox on a row (or press Space with the row selected) and its status changes.
Screens: 11-account-register.png
Depends: S-005
Acceptance:
- [snap] Cleared, uncleared and reconciled rows look different in light and dark mode (Fixes: unticked checkboxes render as bright white boxes in dark mode).
- [unit] The cleared balance changes by the row's amount.
- [unit] A reconciled transaction cannot be uncleared from the register.
UX:
- Flow: click the status icon in a row, or select rows and press Space, or choose Transaction > Mark as Cleared (⌘K) -> the status icon and word change, and the cleared balance in the subtitle updates in the same frame -> ⌘Z offers "Undo Mark as Cleared"
- Surface: inline (one value on a row that's already on screen)
- States: a reconciled row shows a lock, and clicking it does nothing; its tooltip says "Reconciled on 22 Sep 2026. Reconciled transactions can't be marked as uncleared."; mixed selection: the menu says "Mark as Cleared" when any selected row is uncleared
- Words: "Mark as Cleared", "Mark as Uncleared"; status icon tooltip "Mark as cleared (Space)"
- Access: the status cell is a toggle with VoiceOver label "Cleared" and value "on" or "off"; Space works on several selected rows; colour plus icon plus word
Status: done

## M2 Organize: categories, payees, transfers

### S-010 Edit or close an account
As the user, I edit an account's name, number, currency, interest rate or credit limit, or close it.
Screens: 23-account-edit.png
Depends: S-004
Acceptance:
- [snap] Type and opening balance show but can't be edited.
- [snap] "Close account" asks for confirmation and removes the account from the sidebar; its transactions stay.
- [unit] A closed account is left out of totals but its transactions remain in reports for past dates.
Status: done (past-date reports are checked again in M6)

### S-011 Hide reconciled or cleared transactions
As the user, I use the Filter menu in the register to hide reconciled or cleared rows.
Screens: 25-register-filter.png
Depends: S-005
Acceptance:
- [snap] The filter control shows which filters are on ("Hiding reconciled").
- [unit] The filter choices are saved in preferences and apply to every register.
Status: done

### S-012 Pick a category by typing
As the user, I type part of a category name in the transaction sheet and choose from the matches, shown with their parents.
Screens: 27b-transaction-add-category-picker.png
Depends: S-006
Acceptance:
- [snap] Matches show "Parent > Child"; parents with children can't be picked on their own if Budgie forbids it (check the source).
- [self] Arrow keys move through the matches and Return picks one.
Status: done (native type-ahead: arrows and Return are AppKit's own; check the suggestion list by hand)

### S-013 Fill in a transaction from its payee
As the user, I type the start of a payee name, accept a suggestion with Tab, and its default category and amount fill in.
Screens: 27-transaction-add-payee-autocomplete.png, 20-settings.png
Depends: S-006, S-018
Acceptance:
- [snap] Suggestions list known payees whose name contains the typed text.
- [unit] With autofill on, picking a payee sets its default category and amount only when those fields are empty.
- [unit] With autofill off, only the name fills in.
- [self] Return in the payee field accepts the suggestion and does not save the sheet.
Status: done (Return accepting the suggestion is AppKit's own; check by hand)

### S-014 Move money between two accounts
As the user, I add a transfer from one account to another and both registers show it.
Screens: 26-transaction-add-empty.png, 27b-transaction-add-category-picker.png
Depends: S-006
Acceptance:
- [snap] The transaction sheet has a clear way to make a transfer, chosen in UX (Budgie uses a "Transfer > account" category; a separate "Transfer to" field may be clearer).
- [unit] A transfer creates two linked transactions with opposite amounts.
- [unit] Transfers are left out of spending and of income vs expenses in reports.
Status: done (UX: a Transfer field in the sheet; reports leave transfers out from M6 via Transaction.isTransfer)

### S-015 Browse and search categories
As the user, I open Categories and see the category tree, and I can filter it by typing.
Screens: 18-categories.png, 05-categories-empty.png, 55-category-search.png
Depends: S-001
Acceptance:
- [snap] Parents show their number of sub-categories, and children are indented under their parent.
- [unit] A search keeps a match's parent visible for context.
- [unit] A first launch with no data seeds Budgie's default category tree.
Status: done

### S-016 Add a category or sub-category
As the user, I add a top-level category or a sub-category under a parent, and choose Expense, Income or Transfer.
Screens: 53-category-new.png, 54-category-add-sub.png
Depends: S-015
Acceptance:
- [snap] The Type choice offers Expense, Income and Transfer (Fixes: no Transfer type in the form).
- [unit] A name that matches a sibling's (ignoring case) is refused (Fixes: duplicate category names allowed).
Status: done

### S-017 Rename or delete a category
As the user, I edit a category's name and type, or delete it.
Screens: 18-categories.png
Depends: S-015
Acceptance:
- [snap] Delete is turned off for a parent with children, and its help text says why.
- [unit] Deleting a category used by transactions asks for confirmation; those transactions become uncategorised.
Status: done

### S-018 Browse and search payees
As the user, I open Payees and see each payee with its default category and amount.
Screens: 19-payees.png, 06-payees-empty.png
Depends: S-001
Acceptance:
- [snap] Amounts use the standard currency format (Fixes: "+2850.00" and "−55.00" with no £ sign).
- [snap] The empty state explains that payees are added when you save a transaction.
Status: done

### S-019 Add, edit or rename a payee
As the user, I create a payee or change its name, default category and default amount.
Screens: 56-payee-new.png, 57-payee-details.png, 58-payee-edit.png
Depends: S-018
Acceptance:
- [snap] Name can be edited (Fixes: payees can't be renamed).
- [unit] Renaming offers to update existing transactions with the old name; renaming to an existing name merges the two.
Status: done

### S-020 Delete a payee
As the user, I delete a payee I no longer use.
Screens: 19-payees.png
Depends: S-018
Acceptance:
- [unit] Deleting a payee keeps the payee text on past transactions.
- [snap] The confirmation names the payee.
Status: done

## M3 Reconcile

### S-021 Start reconciling an account
As the user, I choose Reconcile and enter the statement date and ending balance.
Screens: 24-account-reconcile-dialog.png, 31-register-reconcile-dialog.png, 62-reconcile-dialog-filled.png
Depends: S-009
Acceptance:
- [snap] The sheet shows the last reconcile's date and balance, and Next is turned off until a balance is entered.
- [unit] Next saves the pending statement on the account.
Status: done

### S-022 Match transactions to the statement and finish
As the user, I tick transactions until the difference is zero, then press Finish.
Screens: 63-reconcile-page.png, 13-reconcile.png
Depends: S-021
Acceptance:
- [snap] Summary tiles show Opening balance, Cleared balance, Statement balance and Difference; the footer shows the selected count and the Difference.
- [unit] Ticked items start as the cleared ones, or as a subset that adds up to the statement amount when one exists (port `subset-sum.ts`).
- [unit] Finish marks ticked items reconciled and saves a checkpoint; it is turned off unless Difference = 0.
- [self] Return finishes when balanced; Escape leaves and keeps the pending statement.
- [unit] Reopening an account with a pending statement resumes the reconcile page.
- [unit] "Cleared balance" uses the same definition here and on the Accounts page (Fixes: two different cleared balances).
Status: done (Escape goes to All Accounts and keeps the statement; Stop Reconciling forgets it)

### S-023 Balance a reconcile with an adjustment
As the user, I press Auto Balance and add an adjustment transaction for the difference.
Screens: 63-reconcile-page.png
Depends: S-022
Acceptance:
- [snap] The transaction sheet opens prefilled with the difference and a "Reconciliation adjustment" payee.
- [unit] After saving, the difference is zero.
Status: done

### S-024 Fix a transaction while reconciling
As the user, I add or edit a transaction from the reconcile page without leaving it.
Screens: 63-reconcile-page.png
Depends: S-022
Acceptance:
- [self] Command-N on the reconcile page adds a transaction, and the new row arrives ticked.
- [unit] Editing an amount updates the Difference.
Status: done

## M4 Time: scheduled payments and forecast

### S-025 See all scheduled payments
As the user, I open Scheduled and see every recurring payment with its next due date, amount, frequency and account.
Screens: 15-scheduled.png, 04-scheduled-empty.png, 72-dark-scheduled.png
Depends: S-001
Acceptance:
- [snap] Paused schedules are marked clearly.
- [unit] The frequency label is worked out from the RRULE (Monthly, Every 2 weeks, Yearly …).
- [snap] The page is called "Scheduled" and its items "scheduled transactions" everywhere (Fixes: "Subscriptions" vs "Scheduled Transactions" vs "Scheduled Payment").
Status: done

### S-026 Add a scheduled payment
As the user, I set up a recurring payment or income with account, payee, category, amount, first date, frequency, day rules, end condition and auto-post.
Screens: 35-scheduled-add.png
Depends: S-025
Acceptance:
- [snap] Weekly shows a weekday picker; monthly shows a 1–31 + Last day grid; the end condition is Never, On date or After N times.
- [unit] The form writes a valid RFC 5545 RRULE, and it parses back into the same form state.
- [unit] Picking a transfer sets the "to" account.
Status: done

### S-027 Edit, pause or resume a scheduled payment
As the user, I change a schedule, or pause and resume it.
Screens: 36-scheduled-edit.png
Depends: S-026
Acceptance:
- [snap] The form has an Active/Paused control (Fixes: no pause/resume control).
- [unit] A paused schedule is left out of the forecast, auto-post and the 7-day summary.
Status: done

### S-028 Record a scheduled payment
As the user, I record a due payment, adjust it if needed, and it posts to the register.
Screens: 37-scheduled-record-payment.png, 34-scheduled-details.png
Depends: S-026
Acceptance:
- [snap] The sheet is prefilled from the schedule; the date defaults to the due date.
- [unit] Recording creates a transaction (or a transfer pair) and moves the next due date to the next occurrence.
- [unit] Recording the final occurrence ends the schedule.
Status: done

### S-029 Skip a scheduled payment
As the user, I skip one occurrence without recording anything.
Screens: 34-scheduled-details.png
Depends: S-026
Acceptance:
- [snap] The confirmation names the date being skipped and the next date.
- [unit] Skipping moves the next due date on and creates no transaction.
Status: done

### S-030 Delete a scheduled payment
As the user, I delete a schedule after confirming.
Screens: 40-scheduled-delete-confirm.png
Depends: S-025
Acceptance:
- [snap] The confirmation names the schedule.
- [unit] Transactions already recorded from it remain.
Status: done

### S-031 Filter and sort scheduled payments
As the user, I show only some accounts and sort by next due, payee, amount or account.
Screens: 38-scheduled-account-filter.png, 39-scheduled-sort.png
Depends: S-025
Acceptance:
- [snap] View menu and toolbar offer the eight sort orders and an account filter.
- [unit] Sort and filter are remembered between launches.
Status: done (sort and account filter are in the toolbar; a View menu copy comes with S-049)

### S-032 See what's due soon
As the user, I see a month calendar with due dates marked and a "Due in next 7 days" summary.
Screens: 15-scheduled.png
Depends: S-025
Acceptance:
- [snap] Days with a due payment show a dot; clicking a day selects its schedules.
- [unit] The 7-day income, outgoing and count include only active schedules due from today up to 7 days ahead.
Status: done

### S-033 Post scheduled payments automatically
As the user, schedules marked auto-post record themselves N days before they are due when I open the app.
Screens: none (no UI)
Depends: S-028
Acceptance:
- [unit] At launch every active auto-post schedule due within its days-in-advance window is recorded once, including any missed occurrences.
- [unit] Running it twice posts nothing twice.
Status: done

### S-034 Forecast an account's balance
As the user, I open Forecast on an account and see a chart and list of its projected balance up to an end date.
Screens: 14-forecast.png
Depends: S-026, S-005
Acceptance:
- [snap] A line chart with a zero line, and a list of projected rows with their projected balance.
- [unit] Projections start at each schedule's stored next due date (Fixes: forecast ignores the stored next due date).
- [unit] Transfers into the account count as deposits.
- [unit] The end date defaults to three months ahead and can be changed.
Status: done

### S-035 Try out a forecast without changing data
As the user, I untick projected rows to see the balance without them, and look at a row's details.
Screens: 32-forecast-row-details.png, 33-forecast-help.png
Depends: S-034
Acceptance:
- [unit] Excluding a row changes later projected balances only, never stored data.
- [snap] Row details show date, amount, projected balance, status, source, category and memo.
- [snap] Help explains the chart and the include toggles (hover help or a help popover).
Status: done

## M5 Budget: envelopes

### S-036 See this month's budget
As the user, I open Budget and see Available to Budget and each envelope's assigned, spent and available amounts for a month, and step between months.
Screens: 16-budget.png, 47-budget-prev-month.png, 73-dark-budget.png
Depends: S-001
Acceptance:
- [unit] Available to Budget counts all income received up to the month, minus all amounts assigned up to the month, minus overspending (Fixes: only the current month's income was counted).
- [unit] Available per envelope = rolled over + assigned + spending + money moved in − money moved out (port `budget-computations.ts` and its tests).
- [snap] Progress shows how much of the money available is spent, and turns red only when available is below zero (Fixes: bars ignore moved money).
Status: done

### S-037 Start budgeting from a template
As the user, with no envelopes I pick Starter, Detailed or Minimal, or start from scratch.
Screens: 02-budget-empty.png
Depends: S-036
Acceptance:
- [snap] Three template cards list their envelopes.
- [unit] A template creates its envelopes and maps the matching default categories.
Status: done

### S-038 Add an envelope
As the user, I name an envelope and choose the categories it tracks.
Screens: 41-budget-add-envelope.png
Depends: S-036
Acceptance:
- [snap] The categories are grouped by parent; ones already in another envelope are turned off and name that envelope.
- [unit] A category can belong to only one envelope.
Status: done

### S-039 Edit or delete an envelope
As the user, I change an envelope's name or categories, or delete it.
Screens: 42-budget-edit-envelope.png
Depends: S-038
Acceptance:
- [snap] Delete asks for confirmation; closing with unsaved edits asks "Discard changes?".
- [unit] Deleting an envelope frees its categories and keeps past months' totals.
Status: done

### S-040 Assign money to an envelope
As the user, I click an envelope's assigned amount, type a new one and press Return.
Screens: 46-budget-assign-inline.png
Depends: S-036
Acceptance:
- [self] Return saves, Escape cancels, and Tab moves to the next envelope's amount.
- [unit] Available to Budget and the envelope's available update together.
Status: done (Return, Escape and Tab are the text field's own; check by hand)

### S-041 Move money between envelopes
As the user, I move an amount from one envelope to another for the month.
Screens: 44-budget-move-money.png
Depends: S-036
Acceptance:
- [snap] From, To, Amount and Notes; Move is turned off until From ≠ To and Amount > 0.
- [unit] Both envelopes' available change by the amount; Available to Budget does not change.
Status: done

### S-042 Copy last month's budget
As the user, I fill this month's empty assignments from last month.
Screens: 45-budget-fill-confirm.png
Depends: S-040
Acceptance:
- [snap] The confirm button is a normal default button, not destructive (Fixes: "Fill" styled destructive).
- [unit] Only envelopes with no assignment this month are filled.
Status: done

### S-043 Reorder envelopes
As the user, I drag an envelope to a new position, or use Move Up and Move Down.
Screens: 43-budget-more-actions.png
Depends: S-036
Acceptance:
- [self] Drag and the context menu both save a new sort order.
- [snap] Move Up is turned off on the first row.
Status: done (drag and Move Up/Down; check drag by hand)

## M6 Reports

### S-044 See spending by category
As the user, I open Reports and see a donut of spending by category with the top five and Other.
Screens: 17-reports.png, 51-reports-show-values.png, 03-reports-empty.png, 74-dark-reports.png
Depends: S-001
Acceptance:
- [snap] The donut has the total in the middle, a legend, and a values table with percentages.
- [unit] Transfers and income are left out; categories roll up to their parent or not, matching Budgie (check `useReportsData.ts`).
- [snap] An empty period shows "No spending in this period".
Status: done (charts use the Mac's currency; figures are per currency)

### S-045 Compare income and expenses by month
As the user, I see grouped bars of income and expenses per month.
Screens: 17-reports.png
Depends: S-044
Acceptance:
- [unit] Monthly totals leave out transfers.
- [snap] The values table lists each month's income, expenses and difference.
Status: done

### S-046 See my net worth over time
As the user, I see a line or area chart of net worth by month.
Screens: 17-reports.png, 17-reports-full.png, 52-reports-net-worth.png
Depends: S-044
Acceptance:
- [snap] An area chart scaled to the data, with a signed headline "-£573.48" (Fixes: tall bars and a "£-" sign).
- [unit] Net worth per month = sum of account balances at the end of that month, converted only within one currency.
Status: done

### S-047 Filter reports by period and accounts
As the user, I choose a date range preset and which accounts to include.
Screens: 48-reports-date-range.png, 49-reports-accounts.png
Depends: S-044
Acceptance:
- [snap] Presets: Last 30, 60 and 90 days, This month, Last month, This year; account multi-select with All.
- [snap] The account picker shows no "No accounts found" text when accounts are listed (Fixes: a false empty message).
Status: done

### S-048 See summary figures
As the user, I see Total Assets, Total Debt, Monthly Surplus and Saving Rate under the charts.
Screens: 17-reports.png
Depends: S-044
Acceptance:
- [unit] Totals are given per currency (Fixes: EUR summed as GBP).
- [unit] Saving rate = surplus ÷ income for the latest complete month in range, shown as "—" when there's no income.
Status: done

## M7 Mac: menus, keyboard, settings, files

### S-049 Use the app from the menu bar
As the user, every command is in a standard Mac menu with a shortcut, so I never hunt for a gear icon.
Screens: 21-settings-menu.png
Depends: S-006
Acceptance:
- [snap] File: New Transaction ⌘N, New Account ⇧⌘N, Import Budgie Data…, Export Budgie Data…, Import QIF… Edit: Undo/Redo, Delete. View: All Accounts ⌘1, Scheduled ⌘2, Budget ⌘3, Reports ⌘4, Categories, Payees, register filters. Account: Reconcile… ⌘R, Forecast ⇧⌘F, Edit Account…, Close Account…. Transaction: Edit Transaction… ⌘E, Mark as Cleared/Uncleared ⌘K, Delete ⌫. Window and Help as standard.
- [self] Every menu item is turned off when it can't apply (for example Reconcile with no account selected).
- [unit] The Budgie single-key shortcuts (A, S, B, F, R) are replaced by these and listed in GLOSSARY.
Status: done (Delete in the Transaction menu is ⌘⌫, because a plain ⌫ menu shortcut would steal backspace from text fields; plain ⌫ deletes in the register)

### S-050 Jump to an account with my own shortcut
As the user, I assign a key to an account in Settings and press it to open that account.
Screens: 60-settings-shortcuts.png
Depends: S-049, S-052
Acceptance:
- [snap] The Shortcuts tab lists the built-in shortcuts and my account shortcuts, with record and remove.
- [unit] A shortcut that clashes with a menu shortcut is refused.
Status: todo

### S-051 Find a transaction by searching
As the user, I press ⌘F in a register and type to filter by payee, category, notes or amount.
Screens: 11-account-register.png
Depends: S-005
Acceptance:
- [self] Search narrows the register as I type; Escape clears it.
- [unit] Typing "55" matches -£55.00.
Status: done (⌘F is wired with the menus in S-049; Escape clearing is the search field's own)

### S-052 Choose appearance, start page and autofill
As the user, I open Settings (⌘,) and set the theme, the page to open on launch, and payee autofill.
Screens: 20-settings.png
Depends: S-001
Acceptance:
- [snap] General pane: Appearance (System, Light, Dark), Open on launch (pages and accounts), "Fill in category and amount from payee".
- [unit] Every preference persists and applies at once.
Status: todo

### S-053 Export my data
As the user, I export everything to a file that Budgie or BudgieMac can import.
Screens: 59-settings-advanced.png
Depends: S-002
Acceptance:
- [unit] The export is a Budgie portable package v1; importing it back gives identical data.
- [manual] The export imports into the Budgie web app without errors.
Status: done (verified with Budgie's own parsePortableData; the [manual] import into the Budgie web app is still to do)

### S-054 Back up and restore automatically
As the user, BudgieMac backs up my data on quit and I can restore any backup.
Screens: none (Electron-only feature; snapshot page "Settings > Backups" and "Restore sheet")
Depends: S-001
Acceptance:
- [unit] A backup is written on quit; backups older than the retention period (default 30 days) are deleted.
- [snap] The Backups pane shows the folder, retention, Back Up Now and a list of backups to restore.
- [self] Restoring asks for confirmation, then reloads the data without needing a relaunch.
Status: todo

### S-055 Import transactions from a QIF file
As the user, I choose File > Import QIF…, review the rows with duplicates flagged, and import the ones I tick.
Screens: none (Electron-only feature; snapshot page "QIF review sheet")
Depends: S-006
Acceptance:
- [unit] Port `qif-parser.ts` and `qif-matcher.ts` with their tests; duplicates are matched by date, amount and payee.
- [snap] The review sheet shows a New or Duplicate badge, Date, Payee, Withdrawal, Deposit and a checkbox per row.
- [self] Dropping a .qif file on a register opens the same review.
Status: done (duplicates match Budgie's rule, amount within 3 days, preferring the same payee; check dropping a file by hand)

## M8 Polish

### S-056 See helpful empty states
As the user, on a fresh install every page tells me what to do first.
Screens: 01-home-empty.png, 04-scheduled-empty.png, 06-payees-empty.png, 03-reports-empty.png
Depends: S-003
Acceptance:
- [snap] Accounts, register, Scheduled, Payees and Reports each have an empty state with one primary action.
Status: todo

### S-057 Use the app in dark mode
As the user, every page reads well in dark mode.
Screens: 70-dark-home.png, 71-dark-register.png, 72-dark-scheduled.png, 73-dark-budget.png, 74-dark-reports.png, 75-dark-transaction-add.png
Depends: S-052
Acceptance:
- [snap] Every snapshot page is checked in light and dark mode; money colours meet 4.5:1 contrast in both.
Status: todo

### S-058 See the version and what's new
As the user, I choose BudgieMac > About and see the version with a link to the changelog.
Screens: 61-about.png
Acceptance:
- [snap] The standard About panel shows the version, build number and a link to the changelog.
Status: todo

### S-059 Recognise the app in the Dock
As the user, BudgieMac has its own icon, not Budgie's.
Screens: none (snapshot: Dock and Finder icon)
Acceptance:
- [snap] A Liquid Glass icon looks right in every appearance (made with the app-icon skill).
Status: todo

## Later

- Show a chart full window (50-reports-fullscreen.png, 52-reports-net-worth.png): native windows already resize; add only if wanted.
- Sync between Macs through iCloud (Budgie's sync plan, `docs/SYNC_ENGINE_PLAN.md`).
- A quick-add panel with a global shortcut, and a menu bar balance item.
- Shortcuts app actions ("Add transaction", "Balance of account").
- A command line tool or MCP server so agents can read and add transactions.
- Exchange rates to combine totals across currencies.

## Dropped

- Web app and PWA install, offline service worker and the "new version ready" banner: BudgieMac is Mac-only.
- Phone and narrow layouts (80-narrow-register.png, 81-phone-home.png): the Mac sidebar collapses on its own; no drawer, hamburger or card layout.
- The gear menu (21-settings-menu.png): replaced by the menu bar in S-049.
- Electron auto-update through GitHub releases: a personal build updates by reinstalling.
- Moving the data folder: macOS keeps app data in Application Support; backups (S-054) cover moving to a new Mac.
- `10-home-full.png` and `20-settings-full.png`: duplicates of 10 and 20.
