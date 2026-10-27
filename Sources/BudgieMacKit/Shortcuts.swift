import Foundation

/// S-049 and S-050: every built-in keyboard shortcut, so menus, the glossary,
/// and account shortcuts agree. Budgie's single keys (A, S, B, F, R) become
/// Command shortcuts that never fire while typing.
public struct KeyShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let shift = Modifiers(rawValue: 2)
        public static let option = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    public var key: String
    public var modifiers: Modifiers
    public var title: String

    public init(_ key: String, _ modifiers: Modifiers, _ title: String) {
        self.key = key.lowercased()
        self.modifiers = modifiers
        self.title = title
    }

    /// "⌃⌥⇧⌘K", in Apple's order.
    public var symbols: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }

    public func sameKeys(as other: KeyShortcut) -> Bool { key == other.key && modifiers == other.modifiers }
}

public enum Shortcuts {
    public static let builtIn: [KeyShortcut] = [
        KeyShortcut("n", .command, "New Transaction"),
        KeyShortcut("n", [.command, .shift], "New Account…"),
        KeyShortcut("i", [.command, .shift], "Import Budgie Data…"),
        KeyShortcut("e", [.command, .shift], "Export Budgie Data…"),
        KeyShortcut("i", [.command, .option], "Import QIF…"),
        KeyShortcut("1", .command, "All Accounts"),
        KeyShortcut("2", .command, "Scheduled"),
        KeyShortcut("3", .command, "Budget"),
        KeyShortcut("4", .command, "Reports"),
        KeyShortcut("5", .command, "Categories"),
        KeyShortcut("6", .command, "Payees"),
        KeyShortcut("f", .command, "Find"),
        KeyShortcut("r", .command, "Reconcile…"),
        KeyShortcut("f", [.command, .shift], "Forecast"),
        KeyShortcut("e", [.command, .option], "Edit Account…"),
        KeyShortcut("e", .command, "Edit Transaction…"),
        KeyShortcut("k", .command, "Mark as Cleared"),
        KeyShortcut("[", .command, "Previous Month"),
        KeyShortcut("]", .command, "Next Month"),
        KeyShortcut(",", .command, "Settings…"),
        KeyShortcut("z", .command, "Undo"),
        KeyShortcut("z", [.command, .shift], "Redo"),
        KeyShortcut("w", .command, "Close Window"),
        KeyShortcut("q", .command, "Quit"),
        KeyShortcut("h", .command, "Hide"),
        KeyShortcut("m", .command, "Minimize"),
    ]

    /// Budgie's single-key shortcuts and what replaces each.
    public static let replacingBudgie: [String: String] = [
        "A": "New Transaction", "S": "Scheduled", "B": "Budget", "F": "Find", "R": "Reconcile…",
    ]

    /// Why an account shortcut can't be used, or nil. It needs a modifier,
    /// and can't clash with a menu shortcut or another account's.
    public static func problem(with shortcut: KeyShortcut, accountShortcuts: [KeyShortcut] = []) -> String? {
        guard shortcut.key.count == 1 else { return "Choose one key." }
        guard !shortcut.modifiers.isEmpty else { return "Add ⌃, ⌥ or ⌘, so typing never opens an account." }
        if let clash = builtIn.first(where: { $0.sameKeys(as: shortcut) }) {
            return "\(shortcut.symbols) is already \(clash.title)."
        }
        if let clash = accountShortcuts.first(where: { $0.sameKeys(as: shortcut) }) {
            return "\(shortcut.symbols) already opens \(clash.title)."
        }
        return nil
    }
}
