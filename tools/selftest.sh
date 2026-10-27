#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/net.fairhursts.budgiemac.savedState
store=/tmp/BudgieMac-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/BudgieMac.app/Contents/MacOS/BudgieMac --selftest
