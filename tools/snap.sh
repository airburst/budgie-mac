#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=accounts,settings tools/snap.sh
set -u
app=~/Applications/BudgieMac.app/Contents/MacOS/BudgieMac
store=/tmp/BudgieMac-test.store
shots=/tmp/BudgieMac-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/net.fairhursts.budgiemac.savedState
# A saved sidebar width would make snapshots differ from run to run.
defaults delete net.fairhursts.budgiemac "NSSplitView Subview Frames main, SidebarNavigationSplitView" 2>/dev/null
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
