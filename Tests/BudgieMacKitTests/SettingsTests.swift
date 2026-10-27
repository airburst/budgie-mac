import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-052 and S-054.
@MainActor
@Suite("Settings and backups")
struct SettingsTests {
    @Test("Preferences persist")
    func persist() throws {
        let url = URL.temporaryDirectory.appending(path: "prefs-\(UUID()).store")
        let account = UUID()
        do {
            let container = try BudgieSchema.container(url: url)
            let prefs = Preferences.current(in: container.mainContext)
            prefs.appearance = .dark
            prefs.startupPage = StartPage.account(account).text
            prefs.autofillPayees = false
            try container.mainContext.save()
        }
        let container = try BudgieSchema.container(url: url)
        let prefs = Preferences.current(in: container.mainContext)
        #expect(prefs.appearance == .dark && prefs.theme == "dark")
        #expect(StartPage(prefs.startupPage) == .account(account))
        #expect(!prefs.autofillPayees)
        prefs.appearance = .system
        #expect(prefs.theme == nil)
        #expect(StartPage("budget") == .page("budget") && StartPage("") == nil)
    }

    @Test("A backup is written and old ones are pruned, keeping the newest")
    func backups() throws {
        let folder = URL.temporaryDirectory.appending(path: "backups-\(UUID())", directoryHint: .isDirectory)
        let old = try Backups.write(Data("old".utf8), to: folder, now: Date(timeIntervalSinceNow: -40 * 86_400))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -40 * 86_400)], ofItemAtPath: old.path)
        let recent = try Backups.write(Data("recent".utf8), to: folder, now: .now)
        let list = Backups.list(folder)
        #expect(list.map(\.url.lastPathComponent) == [recent.lastPathComponent])
        // A lone old backup is never deleted.
        let lonely = URL.temporaryDirectory.appending(path: "backups-\(UUID())", directoryHint: .isDirectory)
        let only = try Backups.write(Data("x".utf8), to: lonely)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -90 * 86_400)], ofItemAtPath: only.path)
        #expect(Backups.prune(lonely) == 0)
    }
}
