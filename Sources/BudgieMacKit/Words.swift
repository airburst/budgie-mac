import Foundation

public enum Words {
    /// "1 account", "1,234 transactions".
    public static func count(_ number: Int, _ noun: String) -> String {
        "\(number.formatted()) \(noun)\(number == 1 ? "" : "s")"
    }
}
