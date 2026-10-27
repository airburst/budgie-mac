# Budgie screen index

Source app: Budgie web build (PWA), captured with Playwright at 1440x900 (2x) unless noted. Data is fake seeded sample data; "today" in every capture is 27/10/2026. Dates are shown as DD/MM/YYYY and money as GBP.

Shell on every desktop screen: a top bar with four centred nav tabs (Accounts, Subscriptions, Budget, Reports) and a settings gear at the right. Accounts and account registers also show a left accounts sidebar (lg width and up). Forms, details and confirmations open as centred modal dialogs over a blurred page (bottom drawers on phones).

Skipped as duplicates: `10-home-full.png` (same size, same content and same tree as `10-home.png`) and `20-settings-full.png` (byte-identical to `20-settings.png`). `17-reports-full.png` differs and is indexed.

## 01-home-empty.png

Page: Accounts (home), empty state, before seeding. Reached from: app launch at `#/`.
Layout: fully blank white page; the tree holds only the notifications region. Captured before the app finished rendering, so it shows nothing.
Elements: none visible. Source (`AccountsList.tsx`) shows the real empty state as the text "No accounts yet. Add your first account to get started." with the Add account button.
Actions: none visible.
Shortcuts seen: none.

## 02-budget-empty.png

Page: Budget onboarding (no envelopes yet). Reached from: top nav > Budget.
Layout: page title "Budget"; centred heading "Get started with budgeting" with an explanation (assign every pound; aim for Available to Budget = £0); three template cards in a row; "Create from scratch" button below.
Elements: template card (name, description, envelope list): Starter (5 envelopes: Bills, Food, Transport, Personal, Savings); Detailed (8: Mortgage/Rent, Utilities, Insurance, Food, Transport, Healthcare, Personal, Savings); Minimal (3: Essentials, Everything Else, Savings).
Actions: pick a template (creates envelopes with category mappings); Create from scratch (opens the New Envelope form).
Shortcuts seen: none.

## 03-reports-empty.png

Page: Reports with no data. Reached from: top nav > Reports.
Layout: title "Reports" with filters at top right (Date range select "Last 90 Days", Accounts multi-select "All Accounts"); two chart cards side by side (Spending by Category, Income vs Expenses); full-width Net Worth Trend card; row of four stat tiles.
Elements: chart card (title, full-screen button, empty text such as "No spending data for this period"); stat tiles Total Assets £0.00, Total Debt £0.00, Monthly Surplus £0.00, Saving Rate 0%.
Actions: change date range, filter accounts, expand a chart full screen.
Shortcuts seen: none.

## 04-scheduled-empty.png

Page: Subscriptions (scheduled transactions), empty. Reached from: top nav > Subscriptions.
Layout: left column with a month calendar card ("Next due dates · No accounts", previous/next month arrows, today highlighted, caption "A dot marks a schedule's next due date.") and a "Due in next 7 days" card (Income £0.00, Outgoing £0.00, 0 transactions). Right: title "Subscriptions", subtitle "Manage your recurring bills and upcoming transfers.", primary "Add Subscription" button; empty card "No subscriptions yet." with "Add your first subscription" button.
Elements: calendar, 7-day summary card, empty-state card.
Actions: add a subscription, page the calendar month.
Shortcuts seen: none.

## 05-categories-empty.png

Page: Categories, before seeding. Reached from: settings gear > Categories.
Layout: title "Categories" with "New Category" button; full-width search field "Search categories…"; table with NAME and TYPE columns. Not actually empty: the app ships a default category tree (Allowance, Bank charge, Bills with 11 children, Business expense, Food, Healthcare, Insurance, Motoring, and so on).
Elements: parent row (name, "N sub-categories" caption, type, add-sub-category, edit, delete); child row indented with a left rule (name, "Sub-category of X", type, edit, delete). Delete is disabled on parents that have children.
Actions: new category, search, add sub-category, edit, delete, click a row for details.
Shortcuts seen: none.

## 06-payees-empty.png

Page: Payees, empty. Reached from: settings gear > Payees.
Layout: title "Payees" with "New Payee" button; search field "Search payees…"; empty card "No payees yet. They are added automatically when you save a transaction."
Elements: search, empty state.
Actions: new payee, search.
Shortcuts seen: none.

## 10-home.png

Page: Accounts (home/dashboard). Reached from: top nav > Accounts, or launch.
Layout: left sidebar "ACCOUNTS" listing each account with its balance (green positive, red negative) and "+ Add Account" at the bottom. Main: title "Accounts" with primary "Add account"; summary card "ALL ACCOUNTS · TOTAL BALANCE" -£156,272.22 with caption "Account balances, not available cash"; "Your accounts" table.
Elements: account row: name (link), type and masked number ("Bank · •• 4321"), Balance, Cleared balance, Last reconcile (date or "Never"), Remaining credit (credit cards with a limit only, e.g. £3,775.00), Edit icon, Reconcile icon. Seven sample accounts: Everyday Current, Rewards Credit Card, Rainy Day Saver, Home Mortgage, Stocks ISA, Wallet, Euro Travel.
Actions: open account register (row name or sidebar), add account, edit account, start reconcile.
Shortcuts seen: none.

## 11-account-register.png

Page: Account register ("Transactions") for Everyday Current. Reached from: sidebar > Everyday Current, or an account row on home.
Layout: sidebar with the current account highlighted; title "Transactions"; toolbar at right: "Filter · Hiding reconciled", primary "+ Add", "Reconcile", "Forecast". Table columns DATE, PAYEE, CATEGORY, AMOUNT, BALANCE, STATUS, oldest first.
Elements: transaction row: date, payee (clickable), category pill, signed amount (red/green), running balance (shown only on uncleared rows; cleared rows show "—"), status text Cleared/Uncleared, cleared checkbox, edit, delete.
Actions: toggle cleared, open details (click payee), edit, delete, add, filter, reconcile, forecast.
Shortcuts seen: none on screen. Source: N add, R reconcile, F forecast.

## 12-account-credit-card.png

Page: Account register for Rewards Credit Card. Reached from: sidebar > Rewards Credit Card.
Layout: same as 11; the credit card is highlighted in the sidebar. All amounts are negative spending; running balances run -£145.80 to -£225.00 on uncleared rows.
Elements: same transaction row as 11 (Rail Tickets, Pizza Place, Coffee Hut).
Actions: same as 11.
Shortcuts seen: none.

## 13-reconcile.png

Page: Account register for Everyday Current, not the reconcile page. Reached from: direct URL `#/reconcile/1` with no reconcile in progress.
Layout: identical to 11 (same tree). With no pending statement the reconcile route falls back to the plain register. The real reconcile page is `63-reconcile-page.png`.
Elements: as 11.
Actions: as 11.
Shortcuts seen: none.

## 14-forecast.png

Page: Forecast for Everyday Current. Reached from: register toolbar > Forecast (or F on an account page).
Layout: back arrow, account name as title with the full account number beneath; full-width line chart of projected balance (green line, red dashed zero line, x axis by week to 31 Jan); table DATE, PAYEE, CATEGORY, AMOUNT, BALANCE; sticky footer with help button (left), end-date picker "31/01/2027" and primary "Refresh".
Elements: projected row in italics: include checkbox, date, "Scheduled" caption, payee, "✓ Included" caption, category pill (or "—" for a transfer), amount, projected balance, info button.
Actions: include/exclude a projected row (changes the projection only), open row details, open help, change end date, Refresh (applies end date and resets inclusions), back.
Shortcuts seen: none.

## 15-scheduled.png

Page: Subscriptions with data. Reached from: top nav > Subscriptions.
Layout: as 04, but the calendar shows dots on 30 and 31 Oct; 7-day card shows Income £2,850.00, Outgoing £1,350.00, 3 transactions. Toolbar: "All accounts" filter button, primary "Add Subscription", "Sort: Next due ↑" button above the table. Columns DUE, PAYEE, AMOUNT, FREQUENCY, ACCOUNT.
Elements: schedule row: next due date, payee, "Paused" badge when inactive (dashed border, Gym Membership), amount, frequency pill (Monthly, Yearly), account name, Record payment icon, Skip icon, Edit, Delete.
Actions: open details (click payee), record payment, skip (confirms first), edit, delete, filter by account, sort, add.
Shortcuts seen: none on screen. Source: S navigates here.

## 16-budget.png

Page: Budget for October 2026. Reached from: top nav > Budget.
Layout: title "Budget" with month stepper (previous, "October 2026", next) at right; "AVAILABLE TO BUDGET" card -£1,772.29 in red with "Over-assigned: you have assigned more than you have."; button row: primary "Add envelope", "Move money", "Fill from last month"; "Envelopes" table with columns ENVELOPE, ASSIGNED, PROGRESS, SPENT, AVAILABLE.
Elements: envelope row: name, mapped categories caption, assigned amount with pencil (inline edit), progress bar (orange under budget, red when spent exceeds assigned), spent, available (green/red), edit icon, "..." more menu, drag handle. Envelopes: Groceries, Bills, Fun, Getting Around.
Actions: change month, add envelope, move money, fill from last month, edit assigned inline, edit envelope, move up/down, drag to reorder.
Shortcuts seen: none on screen. Source: B navigates here.

## 17-reports-full.png

Page: Reports, full-page capture. Reached from: top nav > Reports.
Layout: same content as 17-reports.png; only 75pt taller with a strip of white at the bottom. The page scrolls inside the main area, so the full-page capture does not show the summary tiles below the Net Worth chart.
Elements, actions: see 17-reports.png.
Shortcuts seen: none.

## 17-reports.png

Page: Reports with data. Reached from: top nav > Reports.
Layout: as 03. Spending by Category donut with total £5,196.42 in the centre and legend (Mortgage Payment, Groceries, Council Tax, Utilities, Fuel, Other); Income vs Expenses grouped bars for Aug 26, Sept 26, Oct 26; Net Worth Trend card with headline "£-573.48" in red and tall negative red bars; each chart card has a "Show values" disclosure. Stat tiles (below the fold, from tree): Total Assets £25,952.78, Total Debt £182,225.00, Monthly Surplus £1,139.26, Saving Rate 40%.
Elements: chart card (title, expand button, chart, legend, Show values), filter selects, stat tiles.
Actions: date range, accounts filter, expand chart, show values.
Shortcuts seen: none.

## 18-categories.png

Page: Categories after seeding. Reached from: settings gear > Categories.
Layout: as 05. The tree now also contains the seeded categories, including a second top-level "Household" (Council Tax, Groceries, Mortgage Payment, Utilities), Income (Interest, Salary), Leisure, Transport and Transfers.
Elements, actions: as 05.
Shortcuts seen: none.

## 19-payees.png

Page: Payees with data. Reached from: settings gear > Payees.
Layout: title, "New Payee", search; table PAYEE, DEFAULT CATEGORY, DEFAULT AMOUNT.
Elements: payee row: name (click for details), default category, default amount (e.g. "+2850.00", "−55.00", or "—"), edit, delete.
Actions: new, search, details, edit, delete.
Shortcuts seen: none.

## 20-settings.png

Page: Settings, General tab. Reached from: settings gear > Settings.
Layout: narrow centred column; back arrow and title "Settings"; segmented tabs General / Advanced / Shortcuts; cards: APPEARANCE (Theme: Light, System [selected], Dark icon toggle group); STARTUP ("Open on launch" select, value "Dashboard"); checkbox "Automatically fill transaction details" with help text (selecting a payee auto-fills category and amount; autocomplete is always on).
Elements: theme toggle group, launch-page select (source options: Dashboard, Budget, Reports, Categories, Payees, Scheduled Transactions, plus each account), autofill checkbox.
Actions: change theme, choose launch page, toggle autofill, switch tab, back.
Shortcuts seen: none.

## 21-settings-menu.png

Page: Accounts with the settings gear menu open. Reached from: gear icon.
Layout: dropdown anchored under the gear at top right.
Elements: menu items "Settings", separator, "Categories", "Payees", "About Budgie". The menu is not in the accessibility tree.
Actions: go to Settings, Categories, Payees; open About. Electron adds Backup..., Restore... and Check for updates (source).
Shortcuts seen: none.

## 22-account-add.png

Page: New Account dialog over Accounts. Reached from: Accounts > Add account (or sidebar > Add Account).
Layout: modal titled "New Account", subtitle "Add a new account to track."; footer Cancel / primary Create.
Elements: Name (placeholder "e.g. Current Account, Visa..."), Type select (Bank; options Bank, Credit card, Loan, Investment, Cash), Account Number ("Optional"), Opening Balance (0), Currency (GBP). Source: Credit card adds Credit Limit and Interest Rate (%); Loan adds Interest Rate (%).
Actions: create, cancel, close.
Shortcuts seen: none.

## 23-account-edit.png

Page: Edit Account dialog. Reached from: Accounts > row edit icon (Everyday Current).
Layout: modal "Edit Account", subtitle "Update account details. Balance and account type cannot be changed."; footer Cancel / Save Changes.
Elements: Name, Type (disabled), Account Number, Opening Balance (disabled, 1200.00), Currency, "Close Account" checkbox below a divider.
Actions: save, close the account (soft delete), cancel.
Shortcuts seen: none.

## 24-account-reconcile-dialog.png

Page: Reconcile start dialog over Accounts. Reached from: Accounts > row reconcile icon.
Layout: modal "Reconcile — Everyday Current"; line "Last reconciled: 22/09/2026 — £4,140.50"; footer Cancel / Next (disabled until a balance is entered).
Elements: Statement date picker (27/10/2026), Statement ending balance number field (placeholder 0.00).
Actions: enter statement details, Next (stores a pending reconcile on the account and opens the reconcile page), cancel.
Shortcuts seen: none.

## 25-register-filter.png

Page: Register with the filter popover open. Reached from: register toolbar > "Filter · Hiding reconciled".
Layout: small popover under the Filter button titled "VIEW FILTERS".
Elements: checkboxes "Hide reconciled" (on) and "Hide cleared" (off). The button label summarises active filters.
Actions: toggle hide reconciled, toggle hide cleared.
Shortcuts seen: none.

## 26-transaction-add-empty.png

Page: Add Transaction dialog over the register. Reached from: register > Add (or N).
Layout: modal "Add Transaction", subtitle "Record a new spending or income entry."; footer Cancel / primary Add Transaction.
Elements: Date picker (today), Payee combobox ("e.g. Starbucks, Amazon..."), Category combobox ("No category"), Withdrawal and Deposit fields side by side, Notes textarea ("Optional notes..."), Cleared checkbox.
Actions: fill and add, cancel. A transfer is made by picking a "Transfer > <account>" category.
Shortcuts seen: none.

## 27-transaction-add-payee-autocomplete.png

Page: Add Transaction with the payee suggestions open. Reached from: Add > type "Bi" in Payee.
Layout: dropdown list under the payee field.
Elements: suggestion "Big Supermarket" (known payees only).
Actions: pick a suggestion (fills category and amount when autofill is on); Tab takes the first match; Enter completes without submitting (source).
Shortcuts seen: none.

## 27b-transaction-add-category-picker.png

Page: Add Transaction with the category picker open. Reached from: Add > Category.
Layout: scrolling list under the Category field.
Elements: flat list of categories shown as "Parent > Child" (e.g. "Bills > Broadband"). The tree also lists an automatic "Transfer" parent with one child per account ("Transfer > Everyday Current" ...), the seeded "Transfers" category, and two separate "Household" entries.
Actions: type to filter, pick a category.
Shortcuts seen: none.

## 27c-transaction-add-date-picker.png

Page: Add Transaction with the date picker open. Reached from: Add > Date field.
Layout: popover month calendar under the Date field.
Elements: month title "October 2026", previous/next arrows, Su–Sa grid with spill-over days greyed, today selected.
Actions: change month, pick a day.
Shortcuts seen: none.

## 28-transaction-details.png

Page: Transaction Details dialog. Reached from: register > click a payee (Corner Grocer).
Layout: modal "Transaction Details", subtitle "Review this transaction before making changes."; header row with payee and amount (-£70.20); caption "Everyday Current · Cleared"; footer Close / primary Edit.
Elements: Date (10 August 2026), Category (Groceries), Notes (None).
Actions: Edit (opens the edit form), close.
Shortcuts seen: none.

## 29-transaction-edit.png

Page: Edit Transaction dialog. Reached from: register row pencil, or Details > Edit.
Layout: same form as 26, titled "Edit Transaction", subtitle "Update the details of this transaction."; footer Cancel / Save Changes.
Elements: prefilled fields; Payee and Category show clear (x) buttons; category shows the full path "Household > Groceries"; Withdrawal 70.20; Cleared checked.
Actions: save, cancel, clear payee/category.
Shortcuts seen: none.

## 30-transaction-delete-confirm.png

Page: Delete confirmation over the register (scrolled down). Reached from: register row trash icon (Fuel Stop).
Layout: small modal "Delete transaction?" with "This will permanently delete this transaction. This action cannot be undone."; footer Cancel / Delete (destructive).
Elements: confirm text only (does not name the transaction).
Actions: delete, cancel.
Shortcuts seen: none.

## 31-register-reconcile-dialog.png

Page: Reconcile start dialog over the register. Reached from: register toolbar > Reconcile (or R).
Layout, elements, actions: identical to 24.
Shortcuts seen: none.

## 32-forecast-row-details.png

Page: Projected row details over Forecast. Reached from: Forecast row info button (Home Mortgage Co).
Layout: modal titled with the payee, subtitle "Projected transaction details"; footer Close.
Elements: Date 01/11/2026, Amount -£1,150.00, Projected balance £3,428.58, Status Included, Source Scheduled payment, Category Mortgage Payment, Memo —.
Actions: close.
Shortcuts seen: none.

## 33-forecast-help.png

Page: Forecast Help dialog. Reached from: Forecast footer help button.
Layout: modal "Forecast Help", subtitle "How to use the balance forecast."; footer Close.
Elements: text explaining the green line (projected balance), red dashed line (zero), italic cards (projected scheduled payments), tapping a card (include/exclude, never changes real data), Details, and Refresh (apply end date and reset inclusions).
Actions: close.
Shortcuts seen: none.

## 34-scheduled-details.png

Page: Scheduled Payment Details dialog. Reached from: Subscriptions > click payee (Acme Ltd Payroll).
Layout: modal "Scheduled Payment Details", subtitle "Review this schedule. Nothing is recorded from here."; payee and amount (£2,850.00) header with caption "Everyday Current · Auto-post 2 days ahead"; footer Close, Skip, Edit, primary Record payment.
Elements: Next due 30 October 2026, Repeats Monthly, Category Salary, Auto-post "On, 2 days in advance", Notes None.
Actions: skip, edit, record payment, close.
Shortcuts seen: none.

## 35-scheduled-add.png

Page: Add Scheduled Payment dialog. Reached from: Subscriptions > Add Subscription.
Layout: wide modal "Add Scheduled Payment", subtitle "Set up a recurring payment or income."; two-column form; "RECURRENCE RULES" section; footer Cancel / Add Schedule. The form scrolls (Notes cut off at the bottom).
Elements: Account select (empty), Payee combobox, Category combobox, Withdrawal, Deposit; First Payment Date picker; Frequency select (Monthly); Occurrence select ("Every") with a 1–31 + "Last" day-of-month grid; End Condition segmented Never / On date / After X times; "Auto-post payment" checkbox (reveals Days in advance, source); Notes. Source: a "Transfer to account" select appears when a transfer category is chosen; weekly frequency shows a weekday picker.
Actions: add, cancel.
Shortcuts seen: none.

## 36-scheduled-edit.png

Page: Edit Scheduled Payment dialog. Reached from: Subscriptions row pencil (Home Mortgage Co).
Layout: same as 35, titled "Edit Scheduled Payment", subtitle "Update this schedule and its recurrence."; footer Cancel / Save Schedule.
Elements: prefilled Account Everyday Current, Payee Home Mortgage Co, Category "Household > Mortgage Payment" (clearable), Withdrawal 1150.00, First Payment Date 01/11/2026, Monthly, day 1 selected, End Never, Auto-post off. No field for Active/Paused.
Actions: save, cancel.
Shortcuts seen: none.

## 37-scheduled-record-payment.png

Page: Record Payment dialog. Reached from: Subscriptions row "Record payment" icon (Home Mortgage Co).
Layout: modal "Record Payment", subtitle "Adjust the details, then record the payment."; footer Cancel, Skip, primary Record.
Elements: Date (defaults to today 27/10/2026, not the due date), Account select, Payee plain text field, Category combobox, Withdrawal 1150.00, Deposit, Notes.
Actions: Record (posts a real transaction and advances the next due date), Skip, cancel.
Shortcuts seen: none.

## 38-scheduled-account-filter.png

Page: Subscriptions with the account filter popover open. Reached from: "All accounts" button.
Layout: popover titled "FILTER BY ACCOUNT".
Elements: a checkbox per account that has schedules (Everyday Current, Rewards Credit Card, both checked); "Show all accounts" link (disabled when all are shown).
Actions: toggle accounts, show all.
Shortcuts seen: none.

## 39-scheduled-sort.png

Page: Subscriptions with the sort menu open. Reached from: "Sort: Next due ↑" button.
Layout: dropdown menu with radio items and a check on the current choice.
Elements: Next due soonest first (checked) / latest first; Payee A to Z / Z to A; Amount lowest first / highest first; Account A to Z / Z to A.
Actions: choose a sort.
Shortcuts seen: none.

## 40-scheduled-delete-confirm.png

Page: Delete subscription confirmation. Reached from: Subscriptions row trash (Car Insurance).
Layout: small modal "Delete subscription?" with "This will permanently delete the Car Insurance subscription. This action cannot be undone."; footer Cancel / Delete.
Elements: confirm text naming the schedule.
Actions: delete, cancel.
Shortcuts seen: none.

## 41-budget-add-envelope.png

Page: New Envelope dialog. Reached from: Budget > Add envelope.
Layout: modal "New Envelope", subtitle "Name the envelope and choose the categories whose spending it tracks."; footer Cancel / Create (disabled until named).
Elements: Name field ("e.g. Groceries"); scrolling "Categories" checklist grouped under parent headings (Bills, Food, ...), income categories excluded; categories already in another envelope are disabled and suffixed "(mapped)"; includes Transfer > <account> categories.
Actions: create, cancel.
Shortcuts seen: none.

## 42-budget-edit-envelope.png

Page: Edit Envelope dialog. Reached from: Budget row edit icon (Groceries).
Layout: same as 41, titled "Edit Envelope"; footer has a destructive "Delete" at left plus Cancel / Save.
Elements: name prefilled; this envelope's own categories checked (Household > Groceries), other envelopes' categories disabled.
Actions: save, delete envelope ("Delete envelope?" confirm, source), cancel ("Discard changes?" confirm when the form has edits, source).
Shortcuts seen: none.

## 43-budget-more-actions.png

Page: Budget with an envelope "..." menu open. Reached from: Groceries row "..." button.
Layout: small dropdown under the button.
Elements: "Move up" (disabled on the first row), "Move down". Source: on phones the menu also has "Edit envelope".
Actions: reorder envelopes.
Shortcuts seen: none.

## 44-budget-move-money.png

Page: Move Money dialog. Reached from: Budget > Move money.
Layout: modal "Move Money", subtitle "Move budgeted money between envelopes for October 2026."; footer Cancel / Move (disabled until valid).
Elements: From select, To select ("Select envelope"), Amount (£), Notes (optional).
Actions: move (creates a budget transfer for the month), cancel.
Shortcuts seen: none.

## 45-budget-fill-confirm.png

Page: Fill from last month confirmation. Reached from: Budget > Fill from last month.
Layout: small modal "Fill from last month?" with "Copies September 2026 assignments into October 2026 for envelopes without one. Existing amounts are kept."; footer Cancel / Fill (styled as destructive).
Actions: fill, cancel.
Shortcuts seen: none.

## 46-budget-assign-inline.png

Page: Budget with inline assigned-amount editing. Reached from: click the assigned amount or pencil on Groceries.
Layout: the Groceries ASSIGNED cell becomes a number field (220) with a stepper; the rest of the page is unchanged.
Elements: inline spin field "Assigned amount for Groceries".
Actions: type a new amount; Enter or blur saves, Escape cancels (source).
Shortcuts seen: none.

## 47-budget-prev-month.png

Page: Budget for September 2026. Reached from: Budget > previous-month arrow.
Layout: as 16 with month label "September 2026". ATB -£648.74; Groceries available £39.35, Bills £9.50, Fun -£3.69, Getting Around £12.70.
Elements, actions: as 16.
Shortcuts seen: none.

## 48-reports-date-range.png

Page: Reports with the date range list open. Reached from: Reports > date range select.
Layout: dropdown list under the select, current item checked.
Elements: Last 30 Days, Last 60 Days, Last 90 Days (selected), This Month, Last Month, This Year.
Actions: choose a range.
Shortcuts seen: none.

## 49-reports-accounts.png

Page: Reports with the accounts filter open. Reached from: Reports > "All Accounts" select.
Layout: dropdown list under the select.
Elements: one option per account, plus the empty-state text "No accounts found" showing at the bottom even though seven accounts are listed.
Actions: select one or more accounts (multi-select chips), type to search.
Shortcuts seen: none.

## 50-reports-fullscreen.png

Page: Spending by Category in full screen. Reached from: chart card expand button.
Layout: chart fills the whole window, title at top left, close (x) at top right; donut on the left half, legend floating on the right.
Elements: donut with centre total £5,196.42, legend.
Actions: close (button or Escape, source).
Shortcuts seen: none.

## 51-reports-show-values.png

Page: Reports with "Show values" expanded on Spending by Category. Reached from: the card's "Show values" disclosure.
Layout: a table opens inside the card; the button changes to "Hide values".
Elements: row per slice: name, colour dot, amount, "of total" percentage (Mortgage Payment £3,450.00 66%, Groceries £541.95 10%, Council Tax £504.00 10%, Utilities £277.50 5%, Fuel £165.00 3%, Other £257.97 5%).
Actions: hide values.
Shortcuts seen: none.

## 52-reports-net-worth.png

Page: Net Worth Trend in full screen. Reached from: Net Worth card expand button.
Layout: full-window chart with title and "£-573.48" headline, close at top right.
Elements: three tall red monthly bars (Aug 26, Sept 26, Oct 26) on a negative y axis (£0.00 to £-140.0k). The top label is clipped and the Sept bar overlaps its axis label.
Actions: close.
Shortcuts seen: none.

## 53-category-new.png

Page: New Category dialog. Reached from: Categories > New Category.
Layout: modal "New Category", subtitle "Add a new spending category."; footer Cancel / Create (disabled until named).
Elements: Name ("e.g. Groceries, Rent..."), Type radio Expense (default) / Income. No Transfer option.
Actions: create, cancel.
Shortcuts seen: none.

## 54-category-add-sub.png

Page: New Sub-category dialog. Reached from: Categories row folder-plus icon (Allowance).
Layout: modal "New Sub-category", subtitle "Add a sub-category under Allowance."; footer Cancel / Create.
Elements: read-only "Parent category: Allowance", Name, Type radio Expense / Income.
Actions: create, cancel.
Shortcuts seen: none.

## 55-category-search.png

Page: Categories filtered by search. Reached from: type "gro" in the search field.
Layout: search field shows "gro" with a clear (x) button; list shows matches with their parents kept for context.
Elements: Food (1 sub-category) > Groceries; Household (1 sub-category) > Groceries. Parent counts reflect the filtered children.
Actions: clear search, row actions as 05.
Shortcuts seen: none.

## 56-payee-new.png

Page: New Payee dialog. Reached from: Payees > New Payee.
Layout: modal "New Payee", subtitle "Add a payee with a default category and amount."; footer Cancel / Create.
Elements: Name ("e.g. Starbucks"), Default category combobox, Default withdrawal, Default deposit.
Actions: create, cancel.
Shortcuts seen: none.

## 57-payee-details.png

Page: Payee details dialog. Reached from: Payees > click "Big Supermarket".
Layout: modal titled with the payee, subtitle "Payee details"; footer Close / Edit.
Elements: Default category Groceries, Default amount —.
Actions: edit, close.
Shortcuts seen: none.

## 58-payee-edit.png

Page: Edit Payee dialog. Reached from: Payees row pencil (Fuel Stop).
Layout: modal "Edit Payee", subtitle "Update the default category and amount for this payee."; footer Cancel / Save Changes.
Elements: Name (disabled, cannot rename), Default category "Transport > Fuel" (clearable), Default withdrawal 55.00, Default deposit.
Actions: save, cancel.
Shortcuts seen: none.

## 59-settings-advanced.png

Page: Settings, Advanced tab (web build). Reached from: Settings > Advanced.
Layout: one card "DATA TRANSFER" with text "Export your data to move it between Budgie installations. Importing replaces all local data." and two buttons.
Elements: "Export data" (download a data package), "Import data" (file chooser for a "Budgie data package", then a replace-all confirmation, source).
Actions: export, import.
Shortcuts seen: none.

## 60-settings-shortcuts.png

Page: Settings, Shortcuts tab. Reached from: Settings > Shortcuts.
Layout: card "KEYBOARD SHORTCUTS" with a Key / Action table, then an add row.
Elements: fixed rows A Accounts, S Subscriptions, B Budget, F Forecast (account page), R Reconcile (account page). Add row: "Key…" capture field, "Select account…" select, Add button (disabled); help text "Click the key field then press any key (with or without Ctrl/Cmd) to assign a shortcut to jump directly to an account."
Actions: record a key and bind it to an account; remove existing bindings (source).
Shortcuts seen: A, S, B, F, R.

## 61-about.png

Page: About dialog over Settings > Shortcuts. Reached from: settings gear > About Budgie.
Layout: small centred modal "Budgie", "Version 1.0.2", divider, link button; footer Close.
Elements: version text, "See what's changed in this version" (opens the GitHub CHANGELOG.md externally).
Actions: open changelog, close.
Shortcuts seen: none.

## 62-reconcile-dialog-filled.png

Page: Reconcile start dialog with a balance entered. Reached from: register > Reconcile, then type 4750.00.
Layout: as 24/31; Statement ending balance shows 4750.00 and Next is now enabled.
Actions: Next (goes to 63), cancel.
Shortcuts seen: none.

## 63-reconcile-page.png

Page: Reconcile page for Everyday Current. Reached from: Reconcile dialog > Next (route `#/reconcile/1` with a pending statement).
Layout: back arrow; title "Reconcile — Everyday Current" with "Statement: 27/10/2026 — £4,750.00"; top-right "Auto Balance" and primary "+ Add Transaction"; four summary tiles: Opening Balance £4,140.50, Cleared Balance £5,198.72, Statement Balance £4,750.00, Difference -£448.72 "Not balanced"; list of unreconciled transactions up to the statement date; sticky footer "10 selected  Difference -£448.72" with Cancel and Finish (disabled until difference is zero).
Elements: reconcile row: checkbox, date, payee, category pill, amount, edit pencil; checked rows tinted with a blue border. Initially checks cleared items, or auto-matches a subset that hits the statement when one exists (source).
Actions: tick/untick rows, edit a transaction, add a transaction, Auto Balance (opens the transaction form prefilled with the difference as an adjustment), Cancel, Finish (marks ticked items reconciled and saves a checkpoint).
Shortcuts seen: none on screen. Source: N add, Escape leave, Enter finish when balanced.

## 70-dark-home.png

Page: Accounts (home) in dark mode. Reached from: system dark appearance (Theme: System).
Layout: identical to 10; near-black page, slightly lighter cards and sidebar, same green/red money colours, blue primary button.
Elements, actions: as 10.
Shortcuts seen: none.

## 71-dark-register.png

Page: Account register in dark mode. Reached from: as 11.
Layout: identical to 11 in dark colours. Unchecked cleared checkboxes render as bright white squares.
Elements, actions: as 11.
Shortcuts seen: none.

## 72-dark-scheduled.png

Page: Subscriptions in dark mode. Reached from: as 15.
Layout: identical to 15 in dark colours.
Elements, actions: as 15.
Shortcuts seen: none.

## 73-dark-budget.png

Page: Budget in dark mode. Reached from: as 16.
Layout: identical to 16 in dark colours; the over-budget bar is a lighter red.
Elements, actions: as 16.
Shortcuts seen: none.

## 74-dark-reports.png

Page: Reports in dark mode. Reached from: as 17.
Layout: identical to 17 in dark colours; chart palette unchanged.
Elements, actions: as 17.
Shortcuts seen: none.

## 75-dark-transaction-add.png

Page: Add Transaction dialog in dark mode. Reached from: register > Add.
Layout: identical to 26 in dark colours.
Elements, actions: as 26.
Shortcuts seen: none.

## 80-narrow-register.png

Page: Account register at a 900px-wide window. Reached from: sidebar account at tablet width.
Layout: the accounts sidebar is gone. A "SELECTED ACCOUNT" card at the top shows name, "Bank · •• 4321", Balance £4,778.58, "Cleared balance £5,137.22" and a "Change account" button. Toolbar: Filter, Add, and a "..." overflow. Transactions become cards: payee and amount on the first line; "date · category · status" below; cleared checkbox and a "..." menu; uncleared cards add a "Balance £…" line.
Elements: account context card, overflow menu (Reconcile, Forecast, Edit account; source), per-transaction menu (Edit, Delete; source).
Actions: change account (opens a searchable account chooser), filter, add, reconcile/forecast/edit via overflow, toggle cleared, edit/delete via card menu.
Shortcuts seen: none.

## 81-phone-home.png

Page: Accounts (home) at a 600px phone width. Reached from: launch on a narrow window.
Layout: header with hamburger (opens the navigation drawer), page title "Accounts" and primary "+ Add account"; no top tabs. Total balance card; account cards: name, type/number, balance at right, "Cleared £…" plus "Reconciled <date>" or "Remaining credit £…", and a "..." menu.
Elements: account card, "..." menu (Edit account, Reconcile; source). Drawer (source): Accounts, Subscriptions, Budget, Reports | Categories, Payees, Settings | Electron-only Backup..., Restore..., Check for updates | "Version x.y.z".
Actions: open account, add account, open drawer, card menu.
Shortcuts seen: none.

## Not captured (Electron-only)

From source (`public/electron.js`, `public/ipc/*.js`, `src/components/header.tsx`, `SettingsPage.tsx`, `ImportDialog.tsx`); hidden in the web build by platform capability flags.

- **QIF import** (`capabilities.qifImport`): an "Import" button in the register toolbar and in the register "..." menu. It opens a native file chooser, then a review drawer listing parsed rows with a status badge (New or Duplicate), Date, Payee, Withdrawal, Deposit and a per-row "Import <payee>" checkbox, with Discard and Import buttons.
- **Backup / Restore** (`capabilities.filesystemBackups`): "Backup..." and "Restore..." items in the gear menu and the phone drawer. Backup dialog: backup folder with a "Choose backup folder" browse button, then "Creating backup…". Restore dialog: a list of backups to restore or delete, confirmed by "Restore this backup?" (replaces the database file; relaunch).
- **Settings > Advanced extras**: a "BACKUPS" card (Backup folder field with browse; "Keep backups for N days", default 30) and a "Data folder" card (current folder path with browse, "Browse for data folder"). Moving the data folder copies `budgie.db` to the new folder, writes a config file and quits the app after a confirmation.
- **Automatic backups**: one backup on every app quit and one before installing an update; backups older than the retention period are deleted. The default folder is `~/Documents/Budgie`.
- **Auto-update** (`capabilities.nativeUpdates`, electron-updater): a "Check for updates" gear menu item. Toasts: "Version X available" with a Download action (opens GitHub releases), "Version X available" with a Restart action once downloaded, and "Budgie is up to date". The web build instead shows "A new Budgie version is ready" with Update (service worker).
- **Native menu bar**: none defined. There is no `Menu.buildFromTemplate` or `setApplicationMenu`, so the Electron default menu applies. On macOS the header is a window drag region with a native-traffic-light inset (`app-header-native-mac`).
- **Storage**: a SQLite file in the data folder (the web build uses OPFS in the browser).

## Navigation map

- **Top nav tabs** (desktop, 768px and up): Accounts → `#/` (home); Subscriptions → `#/scheduled`; Budget → `#/budget`; Reports → `#/reports`.
- **Accounts sidebar** (home and account registers, wide windows): each account → `#/accounts/:id` (register); "+ Add Account" → New Account dialog. On narrow widths it becomes the "Selected account" card with "Change account" (a searchable chooser).
- **Account register toolbar**: Reconcile → Reconcile dialog → Next → `#/reconcile/:id`; Forecast → `#/forecast/:id`; back arrows on Forecast and Reconcile return to the register.
- **Home account rows**: name → register; edit icon → Edit Account; reconcile icon → Reconcile dialog → `#/reconcile/:id`.
- **Settings gear menu**: Settings → `#/settings` (tabs General, Advanced, Shortcuts); Categories → `#/categories`; Payees → `#/payees`; About Budgie → About dialog. Electron only: Backup..., Restore..., Check for updates.
- **Phone (under 768px)**: hamburger drawer with Accounts, Subscriptions, Budget, Reports | Categories, Payees, Settings | Electron extras, plus a version footer. Detail routes show a back arrow in the header instead of the hamburger.
- **Settings back arrow**: returns to the previous page. "Open on launch" picks the start route.
- **Custom account shortcuts** (Settings > Shortcuts): user-assigned key → `#/accounts/:id`.

## Command map

**Global keyboard** (`src/pages/layout.tsx`, `src/lib/shortcuts.ts`; ignored while typing in inputs): A → Accounts; S → Subscriptions; B → Budget; user-defined key (optionally with Ctrl/Cmd) → a specific account.

**Account register keyboard** (`AccountTransactions.tsx`): F → Forecast; R → open the Reconcile dialog; N → Add Transaction (N is not listed in the Shortcuts tab).

**Reconcile page keyboard** (`ReconcilePage.tsx`, off while the editor is open): N → Add Transaction; Escape → back to the register; Enter → Finish (only when balanced).

**Other keys**: payee combobox Tab/Enter accepts the first match (Enter never submits the form); inline assigned amount Enter saves, Escape cancels; full-screen chart Escape closes; dialogs close with Escape.

**Header**: nav tabs; gear menu (Settings, Categories, Payees, About Budgie; Electron: Backup..., Restore..., Check for updates).

**Accounts (home)**: Add account; per row: open, Edit account, Reconcile (phone "..." menu: Edit account, Reconcile).

**Account form**: Create / Save Changes, Cancel, Close Account checkbox (soft delete).

**Register toolbar**: Filter popover (Hide reconciled, Hide cleared); Add; Reconcile; Forecast; Import (Electron). Narrow "More actions" menu: Reconcile, Forecast, Edit account, Import (Electron).

**Register row**: cleared checkbox (toggle cleared), click → Transaction Details (Close, Edit), Edit (pencil), Delete (trash → "Delete transaction?" confirm). Narrow: "..." menu with Edit and Delete.

**Transaction form**: Date, Payee (autocomplete; autofill category and amount when enabled), Category (choosing "Transfer > account" makes a linked transfer pair), Withdrawal/Deposit, Notes, Cleared; Add Transaction / Save Changes, Cancel.

**Reconcile**: dialog (Statement date, Statement ending balance, Next, Cancel); page (row checkbox, row Edit, Auto Balance, Add Transaction, Cancel, Finish).

**Forecast**: row include checkbox, row Details, Help, end-date picker, Refresh, back.

**Subscriptions**: Add Subscription; account filter popover (per-account checkboxes, Show all accounts); Sort menu (8 options); calendar month arrows. Per row: click → Details (Close, Skip, Edit, Record payment); Record payment (dialog: Cancel, Skip, Record); Skip (confirm "Skip this payment?": moves the due date and records nothing; skipping the last occurrence removes the schedule); Edit; Delete ("Delete subscription?" confirm).

**Scheduled form**: Account, Payee, Category, Transfer to account (transfer categories only), Withdrawal/Deposit, First Payment Date, Frequency, Occurrence + day grid / weekday picker, End Condition (Never, On date, After X times), Auto-post + Days in advance, Notes; Add Schedule / Save Schedule.

**Budget**: month previous/next; Add envelope; Move money (From, To, Amount, Notes → Move); Fill from last month (confirm → Fill); onboarding templates (Starter, Detailed, Minimal, Create from scratch). Per envelope: inline Assigned edit, Edit (dialog: Name, Categories, Save, Delete), "..." menu (Move up, Move down; phone adds Edit envelope), drag handle to reorder.

**Reports**: Date range select (6 presets), Accounts multi-select; per chart: full screen (open/close), Show/Hide values.

**Categories**: New Category; search with clear; per row: click → details, Add sub-category (parents only), Edit, Delete (disabled while the category has children; soft delete). Form: Name, Type (Expense / Income).

**Payees**: New Payee; search; per row: click → details (Close, Edit), Edit (name locked), Delete.

**Settings**: General (Theme Light/System/Dark, Open on launch, Automatically fill transaction details); Advanced (Export data, Import data; Electron: backup folder, retention, data folder); Shortcuts (key + account → Add; remove).

**About**: "See what's changed in this version" (external CHANGELOG), Close.

**App-level (no UI)**: auto-post runs at startup and posts due scheduled transactions N days in advance.

## Data model guess

Cross-checked with `src/main/db/schema.ts`. Every synced table also has `publicId`, `updatedAt`, `deletedAt` and `createdAt`.

- **Account** (`accounts`): id, name, number (shown masked as "•• last4"), type (bank | credit_card | loan | investment | cash), balance (the opening balance, locked after creation), currency (default GBP), notes, interestRate (form only for credit_card and loan), creditLimit (credit_card), deleted (the "Close Account" checkbox), pendingReconcileBalance and pendingReconcileDate (a reconcile in progress).
  - Derived: **computedBalance** = opening balance + sum of all transaction amounts (the "Balance" column). **clearedBalance** = opening balance + sum of cleared transaction amounts. **lastReconcileDate / lastReconcileBalance** = the latest AccountReconciliation. **Remaining credit** = creditLimit + computedBalance (credit cards with a limit only). **Total balance** = sum of account balances. **Total Assets / Total Debt** = sums of positive and negative balances.
- **Transaction** (`transactions`): id, accountId, categoryId (nullable), date (ISO), payee (free text), amount (signed: withdrawal negative, deposit positive), notes, cleared, reconciled, transferTransactionId (links the two halves of a transfer).
  - Derived: **running balance** in the register (shown only on uncleared rows, starting from clearedBalance); status Cleared / Uncleared / Reconciled.
- **AccountReconciliation** (`account_reconciliations`): id, accountId, date, balance (statement balance), notes. A checkpoint is written on Finish.
  - Derived on the reconcile page: Opening Balance = last checkpoint balance; Cleared Balance = opening + ticked amounts; Difference = statement − cleared; Finish is enabled at a difference of 0.
- **Category** (`categories`): id, parentId (two levels), name, expenseType (expense | income | transfer), deleted (soft delete). The app auto-creates a "Transfer" parent with one child per account; the UI form offers only Expense and Income.
- **Payee** (`payees`): id, name (unique; cannot be renamed), categoryId (default category), amount (default signed amount). Created automatically when a transaction is saved.
- **ScheduledTransaction** (`scheduled_transactions`): id, accountId, categoryId, payee, amount, rrule (RFC 5545, e.g. `FREQ=MONTHLY;BYMONTHDAY=1;COUNT=10`), nextDueDate, autoPost, daysInAdvance, notes, active ("Paused" when false), transferToAccountId.
  - Derived: frequency label (Monthly, Yearly, ...); **Due in next 7 days** income and outgoing totals and count; calendar dots on next due dates; forecast rows (expanded occurrences up to an end date, with projected balance = current balance + cumulative included amounts).
- **Envelope** (`envelopes`): id, name, active, sortOrder.
- **EnvelopeCategory** (`envelope_categories`): id, envelopeId, categoryId (unique, so a category belongs to at most one envelope; shown "(mapped)" elsewhere).
- **BudgetAllocation** (`budget_allocations`): id, envelopeId, month ("YYYY-MM"), assigned.
- **BudgetTransfer** (`budget_transfers`): id, fromEnvelopeId, toEnvelopeId, month, amount, notes (Move money).
  - Derived per envelope and month: **Spent / activity** = sum of transactions in mapped categories that month (the receiving side of transfers is excluded). **Rolled over** = carried-forward positive available from earlier months, starting from the envelope's creation month (overspending does not roll into the envelope). **Available** = rolledOver + assigned + activity + transfersIn − transfersOut. **Progress bar** = spent ÷ assigned. **Underfunded** = assigned is less than the active schedules due that month in mapped categories.
  - Derived per month: **Available to Budget** = that month's income-category transactions − total assigned that month − the previous month's total envelope overspend. **Unbudgeted spending** = expense/transfer transactions in unmapped categories.
- **Settings** (`settings`): a single row with `preferences` JSON: theme, open-on-launch route, autofill on/off, accountShortcuts [{key, ctrl, accountId}], backupFolder, backupRetentionDays.
- **Reports (derived only)**: spending by category (top 5 + Other, with percentages), income vs expenses by month, net worth by month (worked backwards from today's net worth by subtracting each month's non-transfer transactions), **Total Assets** (sum of balances of asset-type accounts), **Total Debt** (sum of absolute balances of liability-type accounts), **Monthly Surplus** (income − expenses for the most recent complete month in range) and **Saving Rate** (surplus ÷ that month's income × 100). Balances in other currencies (Euro Travel, EUR) are added as if they were GBP.
