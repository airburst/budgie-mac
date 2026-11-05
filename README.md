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

| Command                                                              | Description                                                       |
| -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `./build.sh`                                                         | Release build, signed and installed to `~/Applications`           |
| `./build.sh --debug`                                                 | Debug build                                                       |
| `./build.sh --open`                                                  | Build, then quit the running copy and open the new one            |
| `swift test --scratch-path ~/Library/Developer/BudgieMac/test-build` | Unit tests for `BudgieMacKit` (Swift Testing)                     |
| `tools/selftest.sh`                                                  | Runs the app's real actions against a throwaway store in `/tmp`   |
| `tools/snap.sh`                                                      | Light and dark snapshots of every page to `/tmp/BudgieMac-shots/` |
| `tools/grid-lint.sh`                                                 | Checks spacing values sit on the 4 pt grid                        |
| `tools/make_icon.sh`                                                 | Compiles `Icon/AppIcon.icon` (`build.sh` runs it when needed)     |
| `bun run release`                                                    | Test, build and publish a GitHub release (see below)              |

For `swift` commands, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
if `xcode-select -p` points at the Command Line Tools. `build.sh` does this by
itself.

Build products go to `~/Library/Developer/BudgieMac`, outside the repo. The
self-test, snapshots and sample data refuse to run unless `APP_STORE` points
into `/tmp`, so they never touch your real data.

## Releasing

Releases are built on this Mac, not in CI, and published to GitHub Releases
with `gh`.

```bash
bun run release                  # recommends a level from the commits, then asks
bun run release minor            # or major / patch: skips the question
bun run release patch --dry-run  # everything up to the zip; nothing committed or published
```

`tools/release.ts`:

1. Refuses unless you're on a clean `main` that's level with `origin/main`, and `gh` is signed in.
2. Picks the next version from `Info.plist.in` (the single source of the version). It recommends
   patch when every commit since the last tag is a fix or tidy-up, major when one says "breaking",
   and minor otherwise.
3. Uses the version's section in `CHANGELOG.md` as the release notes, or drafts one from the commit
   subjects. You can accept, edit (`$EDITOR`) or stop.
4. Runs the unit tests and the grid lint, builds to `~/Library/Developer/BudgieMac/release/<version>/`,
   runs the self-test on that build, and zips it with `ditto` plus a SHA-256 file.
5. Commits the version and changelog as `Release x.y.z`, tags `vx.y.z`, pushes `main` and the tag
   together, then creates a draft release with the zip attached and publishes it.

If anything fails before the commit, the version files go back as they were.

## Updates

Once a day, at launch or when the app comes forward, BudgieMac asks GitHub for
the [latest release](https://github.com/airburst/budgie-mac/releases/latest).
When there's a newer version it posts a notification. **Install and Relaunch**
downloads it, checks it, puts it in place of the running app and reopens.
Clicking the notification opens the release notes. You hear about each version
once. **BudgieMac > Check for Updates…** checks at any time and always answers.
Turn automatic checks off in Settings > General.

Install and Relaunch checks the zip against the release's `.sha256` file, then
checks that the app inside is BudgieMac at that version with an intact
signature. Only then does it replace the running copy, in one step. Quitting
takes the usual backup. The app downloads the file itself, so the new version
isn't quarantined and opens without the "damaged" warning. If BudgieMac can't
write to its folder, or a check fails, it offers the download instead.

The check is one request to GitHub's public API. Nothing about you or your
budget is sent.

To try it, run an older pretend version:
`APP_PRETEND_VERSION=0.1.0 ~/Applications/BudgieMac.app/Contents/MacOS/BudgieMac`.
Runs with `APP_STORE` in `/tmp` only check from the menu and save nothing, and
the relaunch after installing keeps the same store. To try installing, run a
copy from a scratch folder so your real copy isn't replaced.

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
