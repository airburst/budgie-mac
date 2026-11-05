# BudgieMac

Personal finance for the Mac: a native SwiftUI rewrite of
[Budgie](https://github.com/airburst/budgie). Swift 6 + SwiftUI + SwiftData,
no server, no account. Your data stays on your Mac, in
`~/Library/Application Support/BudgieMac/`.

BudgieMac reads and writes Budgie's data file, so you can move between the
Electron app, the web app and this one with no data loss. It installs next to
`Budgie.app`, not over it (bundle id `net.fairhursts.budgiemac`).

## Features

- **Accounts**: bank, credit card, loan, investment, cash; multi-currency, with totals kept per currency
- **Transactions**: a register with running balance, payee autofill, categories, transfers between accounts, search, filters and Undo
- **Categories and payees**: hierarchical categories, type-ahead, rename and merge
- **Scheduled transactions**: full repeat rules, record or skip, automatic recording at launch
- **Reconciliation**: tick against a statement, with automatic matching and Auto Balance
- **Forecasting**: an account's projected balance from its scheduled transactions
- **Envelope budgeting**: monthly assignments, templates, moving money, copy last month
- **Reports**: spending by category, income vs expenses, net worth, summary figures
- **Import and export**: Budgie data files both ways; QIF import with duplicates flagged (or drop a `.qif` on a register)
- **Backups**: automatic on quit, manual create and restore, pruned by age
- **A Mac app**: every command in the menu bar with a shortcut, light and dark mode, a choice of accent colour

## Requirements

- macOS 26 or later
- Xcode 26 (the SwiftUI and SwiftData macro plugins ship with Xcode, not the
  Command Line Tools)

There is no Xcode project. The app is a Swift package that `build.sh` wraps in
an `.app` bundle.

## Quick Start

```bash
./build.sh --open    # build, install to ~/Applications/BudgieMac.app, and relaunch
```

## Scripts

| Command                                                        | Description                                                        |
| -------------------------------------------------------------- | ------------------------------------------------------------------ |
| `./build.sh`                                                   | Release build, signed and installed to `~/Applications`            |
| `./build.sh --debug`                                           | Debug build                                                        |
| `./build.sh --open`                                            | Build, then quit the running copy and open the new one             |
| `swift test --scratch-path ~/Library/Developer/BudgieMac/test-build` | Unit tests for `BudgieMacKit` (Swift Testing)                |
| `tools/selftest.sh`                                            | Runs the app's real actions against a throwaway store in `/tmp`    |
| `tools/snap.sh`                                                | Light and dark snapshots of every page to `/tmp/BudgieMac-shots/`  |
| `tools/grid-lint.sh`                                           | Checks spacing values sit on the 4 pt grid                         |
| `tools/make_icon.sh`                                           | Compiles `Icon/AppIcon.icon` (`build.sh` runs it when needed)      |

For `swift` commands, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
if `xcode-select -p` points at the Command Line Tools. `build.sh` does this by
itself.

Build products go to `~/Library/Developer/BudgieMac`, outside the repo. The
self-test, snapshots and sample data refuse to run unless `APP_STORE` points
into `/tmp`, so they never touch your real data.

## Signing

`build.sh` signs with your Apple Development certificate if there is one in the
keychain (or `SIGN_IDENTITY=...`), and ad hoc otherwise. Either is fine for
running the app on the Mac that built it.

## Issues with downloaded builds

The app is not signed with a Developer ID or notarised. A copy downloaded from
a release may show:

> "BudgieMac.app is damaged and can’t be opened. You should move it to the Bin"

If you see this, either allow it in System Settings > Privacy & Security, or run:

```bash
xattr -d com.apple.quarantine /Applications/BudgieMac.app
```

## Docs

- [Changelog](CHANGELOG.md)
- [Architecture](ARCHITECTURE.md)
- [Brief](docs/BRIEF.md)
- [Glossary](docs/GLOSSARY.md)
- [Working on the app (agent notes)](CLAUDE.md)
