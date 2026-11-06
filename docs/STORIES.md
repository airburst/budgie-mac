# BudgieMac stories

Names on screen come from `docs/GLOSSARY.md`. Earlier stories (S-001 to
S-059) are done; they live in git history before "Docs clean up".

## M9 Imports that learn

QIF import (S-055) adds rows with the bank's own text as the payee and no
category. These stories make each import fill in payee and category from
what you chose before, and get better with every import.

Measured on a year of the Joint account (1,249 rows, 680 of them already
entered by hand): learned rules fill the right category for 73% of rows,
up from 50% in the first month to about 80% after six; 85% of filled
categories are right. Apple Intelligence was tested and dropped: it got
42% alone and 11% of the rows the rules left blank.

### S-060 See which transaction a duplicate matched
As the user, the QIF review sheet pairs each duplicate with the right existing transaction and shows me which one it is.
Depends: S-055
Acceptance:
- [unit] Among existing transactions with the same amount within 3 days, rows whose bank text names the payee (same name, or the payee is a whole word of the cleaned text) pair first across the whole file; the rest pair by nearest date, then the earliest.
- [unit] Two rows of the same amount a day apart (ASDA and MIPERMIT -1.50, against Asda and Parking) each pair with their own payee, not swapped.
- [unit] Bank text cleaning drops card processor prefixes (ZETTLE_*, SUMUP *, SQ *, CLR*, PAYPAL *), reference codes after `*`, store numbers, punctuation and words like LTD, PLC and STORES: "CO-OP GROUP 070590" -> "COOP", "ZETTLE_*THE BERTIN" -> "BERTIN".
- [snap] A Duplicate row says which transaction it matched, as "Duplicate of Coop, 4 Nov", with the full date, payee and amount in its tooltip.
- [self] Importing the same QIF twice marks every row as a duplicate of the transaction the first import added.
UX:
- Flow: File > Import QIF… (⌥⌘I) or drop on a register -> review sheet -> Duplicate rows show their match -> Import
- Surface: the existing review sheet (one short task that must finish or cancel)
- Words: "Duplicate of Coop, 4 Nov"; tooltip "Already in this account: Coop, 4 November 2026, -£12.05"
Status: done (the sheet is wider, 880 pt, so the match and the bank text fit; the bank text has a tooltip)

### S-061 Learn import rules from transactions I entered
As the user, when bank rows match transactions I entered myself, BudgieMac remembers which payee and category that bank text means.
Depends: S-060
Acceptance:
- [unit] An Import Rule stores the cleaned bank text, money in or out, an optional amount, the payee, the category, a count and the date last used.
- [unit] Each imported transaction keeps its bank text.
- [unit] Matching tries, in order: a rule for this bank text and amount, a rule for this bank text and direction, an exact payee name, a payee that is a whole word of the cleaned text, then a near match. A rule only fills the category when at least 60% of what it learned agrees.
- [unit] On the Joint account QIF from Nov 2026 (kept as a test fixture with names reduced), learning month by month gets at least 70% of categories right and 80% of filled categories right.
- [self] The first import learns from every existing transaction it matches, so the second import of new rows fills their payee and category.

### S-062 Review and correct payee and category before importing
As the user, the review sheet shows the payee and category each row will get, and when I change one, BudgieMac learns from it.
Depends: S-061
Acceptance:
- [snap] Payee and Category columns are filled where a rule or payee matched and blank otherwise; the bank text shows under the payee.
- [snap] A filled row has a small symbol with the tooltip "Learned from 14 earlier imports".
- [unit] A change made in the sheet counts more than a learned match.
- [self] Imported rows get the payee and category shown; no payee is added for bank text that matched an existing payee.

### S-063 Learn when I recategorise an imported transaction
As the user, when I change the payee or category of an imported transaction in the register, the next import uses my change.
Depends: S-061
Acceptance:
- [unit] Editing an imported transaction's payee or category updates the rule for its bank text.
- [self] Change an imported Amazon row to Fitness; importing the same text again suggests Fitness when that is now the majority.

### S-064 Review and edit import rules in Settings
As the user, I open Settings > Import Rules to see what BudgieMac has learned and fix or delete a wrong rule.
Depends: S-061
Acceptance:
- [snap] One row per rule: bank text, payee, category, times confirmed; a search field; Delete with Undo.
- [snap] With no rules: an empty state that says rules are learned from QIF imports.
- [self] Deleting a rule stops it filling the next import.
