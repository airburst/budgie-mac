import Foundation

/// S-055: a port of Budgie's `qif-parser.ts` and `qif-matcher.ts`.
public enum Qif {
    public struct Row: Equatable, Sendable {
        public var date: Date
        public var payee: String
        public var amount: Decimal
        public var memo: String?
    }

    public enum Kind: String, Sendable { case bank, creditCard }

    public enum Failure: Error, Equatable, LocalizedError {
        case notQif, badDate(String)

        public var errorDescription: String? {
            switch self {
            case .notQif: "Invalid QIF file: expected !Type:Bank or !Type:CCard header."
            case .badDate(let text): "Invalid date format: \(text). QIF dates must be DD/MM/YYYY."
            }
        }
    }

    /// Parses a bank or credit card QIF file, oldest first. Credit card
    /// amounts are flipped, so spending is negative as in a register.
    public static func parse(_ content: String) throws(Failure) -> (kind: Kind, rows: [Row]) {
        let lines = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        let header = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let card = header.hasPrefix("!Type:CCard")
        guard card || header.hasPrefix("!Type:Bank") else { throw .notQif }

        var rows: [Row] = []
        var date: Date?, payee = "", amount: Decimal = 0, memo: String?, hasData = false
        func flush() {
            if hasData, let date { rows.append(Row(date: date, payee: payee, amount: amount, memo: memo)) }
            date = nil; payee = ""; amount = 0; memo = nil; hasData = false
        }
        for raw in lines.dropFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let code = line.first else { continue }
            if line == "^" { flush(); continue }
            let value = String(line.dropFirst())
            switch code {
            case "D":
                date = try parseDate(value)
                hasData = true
            case "P":
                payee = value
                hasData = true
            case "T":
                let parsed = Decimal(string: value.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) ?? 0
                amount = card ? -parsed : parsed
                hasData = true
            case "M":
                memo = value
            default:
                break
            }
        }
        flush()
        return (card ? .creditCard : .bank, rows.sorted { $0.date < $1.date })
    }

    static func parseDate(_ text: String) throws(Failure) -> Date {
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count == 3, let date = Day.parse("\(parts[2])-\(parts[1].leftPadded)-\(parts[0].leftPadded)") else {
            throw .badDate(text)
        }
        return date
    }

    public enum Status: String, Sendable { case new = "New", duplicate = "Duplicate", reconciled = "Before Last Reconcile" }

    public struct Match: Identifiable, Sendable {
        /// The row's position in the file.
        public var id = 0
        public var row: Qif.Row
        public var status: Status
        public var duplicateOf: UUID?
        /// Ticked to import: new rows only, at first.
        public var checked: Bool
    }

    /// A row is a duplicate of an existing transaction with the same amount
    /// within 3 days (a same-payee one first); each existing one matches once.
    /// Rows on or before the last reconcile are out of range.
    public static func match(_ rows: [Row], existing: [Transaction], lastReconciled: Date?) -> [Match] {
        var used = Set<UUID>()
        let window: TimeInterval = 3 * 86_400
        return rows.enumerated().map { index, row in
            var match = matchOne(row)
            match.id = index
            return match
        }
        func matchOne(_ row: Row) -> Match {
            if let lastReconciled, row.date <= lastReconciled {
                return Match(row: row, status: .reconciled, checked: false)
            }
            let candidates = existing.filter {
                !used.contains($0.uuid) && $0.amount == row.amount && abs($0.date.timeIntervalSince(row.date)) <= window
            }
            let best = candidates.first { $0.payee.caseInsensitiveCompare(row.payee) == .orderedSame } ?? candidates.first
            if let best {
                used.insert(best.uuid)
                return Match(row: row, status: .duplicate, duplicateOf: best.uuid, checked: false)
            }
            return Match(row: row, status: .new, checked: true)
        }
    }
}

private extension String {
    var leftPadded: String { count == 1 ? "0" + self : self }
}
