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

    /// The existing transaction a duplicate row matched.
    public struct Matched: Equatable, Sendable {
        public var uuid: UUID
        public var payee: String
        public var date: Date
        public var amount: Decimal
    }

    public struct Match: Identifiable, Sendable {
        /// The row's position in the file.
        public var id = 0
        public var row: Qif.Row
        public var status: Status
        public var matched: Matched?
        /// Ticked to import: new rows only, at first.
        public var checked: Bool

        public var duplicateOf: UUID? { matched?.uuid }
    }

    /// S-060: a row is a duplicate of an existing transaction with the same
    /// amount within 3 days; each existing one matches once. Rows whose bank
    /// text names the transaction's payee pair first, across the whole file,
    /// then the rest by nearest date. Rows on or before the last reconcile
    /// are out of range.
    public static func match(_ rows: [Row], existing: [Transaction], lastReconciled: Date?) -> [Match] {
        let window: TimeInterval = 3 * 86_400
        var matches = rows.enumerated().map { index, row in
            if let lastReconciled, row.date <= lastReconciled {
                return Match(id: index, row: row, status: .reconciled, checked: false)
            }
            return Match(id: index, row: row, status: .new, checked: true)
        }
        var used = Set<UUID>()
        func nearest(_ row: Row, _ test: (Transaction) -> Bool) -> Transaction? {
            existing
                .filter { !used.contains($0.uuid) && $0.amount == row.amount && abs($0.date.timeIntervalSince(row.date)) <= window && test($0) }
                .min { (abs($0.date.timeIntervalSince(row.date)), $0.date) < (abs($1.date.timeIntervalSince(row.date)), $1.date) }
        }
        for pass in [true, false] {
            for index in matches.indices where matches[index].status == .new {
                let row = matches[index].row
                guard let best = nearest(row, { !pass || names(row.payee, $0.payee) }) else { continue }
                used.insert(best.uuid)
                matches[index].status = .duplicate
                matches[index].matched = Matched(uuid: best.uuid, payee: best.payee, date: best.date, amount: best.amount)
                matches[index].checked = false
            }
        }
        return matches
    }

    /// True when the bank text is the payee's name, or the payee is one of its
    /// cleaned words or how they start ("CO-OP GROUP 070590" names "Coop").
    public static func names(_ bankText: String, _ payee: String) -> Bool {
        if bankText.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(payee) == .orderedSame { return true }
        let key = payeeKey(payee)
        guard key.count >= 3 else { return false }
        let words = cleaned(bankText)
        return words.contains(key) || words.indices.contains { words[...$0].joined() == key }
    }

    /// The words of bank text that say who it was: card processor prefixes,
    /// reference codes after "*", store numbers, punctuation and words like
    /// LTD go. "ZETTLE_*THE BERTIN" -> ["BERTIN"].
    public static func cleaned(_ bankText: String) -> [String] {
        var text = bankText.uppercased()
        if let prefix = text.range(of: #"^(ZETTLE|SUMUP|SQ|CLR|IZ|PAYPAL)_?\s*\*\s*"#, options: .regularExpression) {
            text.removeSubrange(prefix)
        } else if let star = text.firstIndex(of: "*") {
            text = String(text[..<star])
        }
        if let prefix = text.range(of: #"^LNK\s+"#, options: .regularExpression) { text.removeSubrange(prefix) }
        text = text.replacingOccurrences(of: ".CO.UK", with: " ")
            .replacingOccurrences(of: ".COM", with: " ")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: #"[^A-Z0-9& ]"#, with: " ", options: .regularExpression)
        return text.split(separator: " ").map(String.init).filter { !noise.contains($0) && !$0.contains(where: \.isNumber) }
    }

    static let noise: Set<String> = ["LTD", "LIMITED", "PLC", "INC", "GB", "UK", "STORES", "STORE", "MKTS", "CO", "THE", "PAYMENT", "PAYMENTS", "MBP", "GROUP", "LIMIT", "L"]

    /// A payee's name cleaned like bank text, then joined: "The Noodle Bar" ->
    /// "NOODLEBAR", "Co-op" -> "COOP", "B & Q" -> "B&Q".
    public static func payeeKey(_ name: String) -> String {
        let words = cleaned(name)
        return words.isEmpty ? squashed(name) : words.joined()
    }

    /// A name in capitals with only letters, digits and "&": "B & Q" -> "B&Q".
    static func squashed(_ name: String) -> String {
        name.uppercased().replacingOccurrences(of: #"[^A-Z0-9&]"#, with: "", options: .regularExpression)
    }
}

private extension String {
    var leftPadded: String { count == 1 ? "0" + self : self }
}
