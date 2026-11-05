#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
# Usage: tools/selftest.sh [path/to/BudgieMac.app]    (default: the installed copy)
set -u
rm -rf ~/Library/Saved\ Application\ State/net.fairhursts.budgiemac.savedState
store=/tmp/BudgieMac-self.store
rm -f $store $store-shm $store-wal
app=${1:-$HOME/Applications/BudgieMac.app}
APP_STORE=$store "$app/Contents/MacOS/BudgieMac" --selftest
