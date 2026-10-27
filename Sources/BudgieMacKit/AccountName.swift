import Foundation

/// Rules for account names. Logic lives in this library so tests can run it
/// without the app. Put parsers, date rules, and data rules here too.
public enum AccountName {
    /// Trims spaces and line breaks, collapses inner runs of spaces, and
    /// falls back to "New Account" for an empty title.
    public static func clean(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? "New Account" : words.joined(separator: " ")
    }
}
