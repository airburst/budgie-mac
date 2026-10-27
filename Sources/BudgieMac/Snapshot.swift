import AppKit
import BudgieMacKit
import SwiftData
import IOKit.pwr_mgt
import SwiftUI

/// Screenshot mode for agents.
///   APP_STORE=/tmp/test.store APP_SNAPSHOT=/tmp/shots ~/Applications/BudgieMac.app/Contents/MacOS/BudgieMac
/// writes <page>-light.png and <page>-dark.png for every sidebar page, and
/// settings-<tab>-light.png and settings-<tab>-dark.png for every Settings tab, then quits.
/// Each PNG gets a <page>-<mode>-layout.json with the grid probes (tools/check-layout.swift).
/// APP_SNAPSHOT_PAGES=accounts,budget limits the pages. Add "settings" to include Settings,
/// "import" for the import confirmation and banner.
/// Add APP_ACCENT=<id> to see the pages in another accent.
enum Snapshot {
    static func runIfRequested(model: AppModel, openSettings: OpenSettingsAction) {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["APP_SNAPSHOT"], !dir.isEmpty else { return }
        // Snapshots never run against the real database.
        guard Store.isOverridden else {
            print("SNAPSHOT refused: set APP_STORE to a file in /tmp")
            NSApp.terminate(nil)
            return
        }
        let only = env["APP_SNAPSHOT_PAGES"].map { Set($0.split(separator: ",").map(String.init)) }
        Task {
            // A sleeping display gives screencapture nothing. Declaring user
            // activity wakes it; the assertion keeps it on until the run quits.
            var activity: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("Snapshots" as CFString, kIOPMUserActiveLocal, &activity)
            var awake: IOPMAssertionID = 0
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn), "Snapshots" as CFString, &awake)
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? await Task.sleep(for: .seconds(1.5))
            for mode in ["light", "dark"] {
                NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                for page in SidebarItem.allCases where only?.contains(page.rawValue) ?? true {
                    model.sidebar = page
                    try? await Task.sleep(for: .seconds(0.8))
                    capture(to: "\(dir)/\(page.rawValue)-\(mode).png")
                }
            }
            if only == nil || only?.contains("import") == true {
                await captureImport(model: model, dir: dir)
            }
            if only == nil || only?.contains("settings") == true {
                let main = NSApp.windows.first { $0.canBecomeMain && !$0.isSheet }
                openSettings()
                try? await Task.sleep(for: .seconds(1))
                for mode in ["light", "dark"] {
                    NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
                    for tab in SettingsTab.allCases {
                        model.settingsTab = tab
                        try? await Task.sleep(for: .seconds(0.8))
                        let settings = NSApp.windows.first { $0.isVisible && $0 !== main && !$0.isSheet }
                        capture(to: "\(dir)/settings-\(tab.rawValue)-\(mode).png", window: settings)
                    }
                }
            }
            print("SNAPSHOT done \(dir)")
            // An open sheet refuses terminate, and the run would wait forever.
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet) } }
            NSApp.terminate(nil)
        }
    }

    /// S-002: the Replace All Data confirmation and the banner after an import.
    private static func captureImport(model: AppModel, dir: String) async {
        let empty = #"{"manifest":{"formatVersion":1,"applicationVersion":"0.16.3","exportedAt":"2026-10-27T12:00:00.000Z"},"preferences":{},"accounts":[],"categories":[],"transactions":[],"accountReconciliations":[],"scheduledTransactions":[],"payees":[],"envelopes":[],"envelopeCategories":[],"budgetAllocations":[],"budgetTransfers":[]}"#
        guard let package = try? JSONDecoder().decode(BudgieImport.Package.self, from: Data(empty.utf8)) else { return }
        let context = model.container.mainContext
        let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        let transactions = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        model.sidebar = .accounts
        for mode in ["light", "dark"] {
            NSApp.appearance = NSAppearance(named: mode == "light" ? .aqua : .darkAqua)
            model.importFlow.confirm(ImportFlow.Pending(fileName: "budgie-export-2026-10-27.json", package: package,
                                                        accounts: accounts, transactions: transactions), in: model)
            try? await Task.sleep(for: .seconds(1))
            capture(to: "\(dir)/import-confirm-\(mode).png", withSheet: true)
            for window in NSApp.windows { if let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .alertFirstButtonReturn) } }
            model.importFlow.banner = "Imported 7 accounts and 1,234 transactions from Budgie."
            try? await Task.sleep(for: .seconds(0.8))
            capture(to: "\(dir)/import-banner-\(mode).png")
            model.importFlow.banner = nil
        }
    }

    /// Captures the real window with screencapture, so glass, sidebars, and
    /// materials look exactly as on screen. That needs Screen Recording
    /// permission for the app that started this one (your terminal, or Claude).
    /// Without it, falls back to drawing the view hierarchy, which leaves
    /// sidebars and glass blank.
    /// `withSheet` captures the window's attached sheet or alert (a window of its own) instead.
    private static func capture(to path: String, window: NSWindow? = nil, withSheet: Bool = false) {
        // Another app can hide this one while snapshots run (computer use hides
        // apps it does not control). Hidden windows cannot be captured.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        guard let window = window ?? NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet }) else {
            print("SNAPSHOT no window")
            return
        }
        // Active, like a window someone is using: real accent colors and focus rings.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        let size = window.contentView?.bounds.size ?? .zero
        GridProbes.shared.write(to: path.replacingOccurrences(of: ".png", with: "-layout.json"), window: size)
        try? FileManager.default.removeItem(atPath: path)
        // The first capture of a run sometimes misses the window. Try three times.
        for _ in 1...3 {
            let shot = Process()
            shot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            if withSheet, let sheet = window.attachedSheet ?? NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) {
                shot.arguments = ["-x", "-o", "-l", String(sheet.windowNumber), path]
            } else {
                shot.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            }
            try? shot.run()
            shot.waitUntilExit()
            if FileManager.default.fileExists(atPath: path) {
                print("SNAPSHOT \(path)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("SNAPSHOT \(path) (fallback: no Screen Recording permission, sidebars and glass are blank)")
        }
    }
}
