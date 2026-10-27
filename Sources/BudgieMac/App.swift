import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI

// BudgieMac
//   BudgieMac                      the app
//   APP_STORE=<file> BudgieMac     use another database (tests, experiments)
//   APP_SNAPSHOT=<dir> BudgieMac   save a PNG of every sidebar page and Settings tab in light and dark mode, then quit
//   APP_SEED=1 BudgieMac           fill an empty /tmp store with sample accounts (tools/snap.sh)
//   BudgieMac --selftest           run the self-test on a /tmp store and quit with 0 or 1 (tools/selftest.sh)
//   APP_ACCENT=<id> BudgieMac      run with another accent from Theme.all (UI/Theme.swift)
//   APP_GRID=1 BudgieMac           draw the 8 pt grid and the layout probes over the window

@main
struct BudgieMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel(container: Store.makeContainer())

    var body: some Scene {
        Window("BudgieMac", id: "main") {
            ContentView()
                .environment(model)
                .themed()
                .overlay { if GridOverlay.enabled { GridOverlay() } }
                .frame(minWidth: 760, minHeight: 480)
        }
        .modelContainer(model.container)
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(before: .sidebar) {
                Button("All Accounts") { model.sidebar = .page(.accounts) }
                    .keyboardShortcut("1")
                Divider()
            }
            ToolbarCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Account…") { model.isAddingAccount = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Budgie Data…") { model.importFlow.chooseFile() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .themed()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from a terminal, the process is not a foreground app yet.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// The self-test's result becomes the exit code, after a normal quit.
    func applicationWillTerminate(_ notification: Notification) {
        if SelfTest.requested { exit(SelfTest.exitCode) }
    }
}

/// Where the data lives: ~/Library/Application Support/BudgieMac/BudgieMac.store
enum Store {
    /// True when APP_STORE points somewhere else (tests, snapshots, seed data).
    static var isOverridden: Bool {
        !(ProcessInfo.processInfo.environment["APP_STORE"] ?? "").isEmpty
    }

    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["APP_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "BudgieMac", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "BudgieMac.store")
    }

    static func makeContainer() -> ModelContainer {
        do {
            return try BudgieSchema.container(url: url)
        } catch {
            fatalError("Could not open the database at \(url.path): \(error)")
        }
    }
}
