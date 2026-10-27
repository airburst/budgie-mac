import Foundation
import Testing
@testable import BudgieMacKit

/// S-049 and S-050.
@Suite("Shortcuts")
struct ShortcutTests {
    @Test("Budgie's single keys are replaced by menu shortcuts listed in the glossary")
    func budgieKeys() throws {
        let glossary = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/GLOSSARY.md"), encoding: .utf8)
        for (key, title) in Shortcuts.replacingBudgie {
            let shortcut = try #require(Shortcuts.builtIn.first { $0.title == title })
            #expect(!shortcut.modifiers.isEmpty)
            #expect(glossary.contains("| \(key) | \(title) | \(shortcut.symbols) |"))
        }
        #expect(Shortcuts.builtIn.allSatisfy { !$0.modifiers.isEmpty })
    }

    @Test("Built-in shortcuts never repeat")
    func unique() {
        let keys = Shortcuts.builtIn.map(\.symbols)
        #expect(Set(keys).count == keys.count)
    }

    @Test("An account shortcut that clashes with a menu shortcut is refused")
    func clashes() {
        #expect(Shortcuts.problem(with: KeyShortcut("n", .command, "Current"))?.contains("New Transaction") == true)
        #expect(Shortcuts.problem(with: KeyShortcut("1", .control, "Current")) == nil)
        #expect(Shortcuts.problem(with: KeyShortcut("1", .control, "Saver"), accountShortcuts: [KeyShortcut("1", .control, "Current")]) != nil)
        #expect(Shortcuts.problem(with: KeyShortcut("c", [], "Current")) != nil)
        #expect(KeyShortcut("k", [.command, .shift, .control], "x").symbols == "⌃⇧⌘K")
    }
}
