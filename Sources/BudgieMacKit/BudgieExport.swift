import CryptoKit
import Foundation
import SwiftData

/// S-053: writes everything as a Budgie portable data package (format 1),
/// field for field as Budgie's `createPortableData`, so Budgie and BudgieMac
/// can both import it. Budgie checks the checksum by hashing `JSON.stringify`
/// of the parsed package, so this writes JSON exactly as JavaScript would:
/// keys in a fixed order, no spaces, shortest numbers.
public enum BudgieExport {
    public static let applicationVersion = "0.16.3"

    public static func data(from context: ModelContext, exportedAt: Date = .now) -> Data {
        func all<T: PersistentModel>(_ type: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        let accounts = all(Account.self), categories = all(Category.self), transactions = all(Transaction.self)
        let reconciliations = all(AccountReconciliation.self), schedules = all(ScheduledTransaction.self)
        let payees = all(Payee.self), envelopes = all(Envelope.self), links = all(EnvelopeCategory.self)
        let allocations = all(BudgetAllocation.self), moves = all(BudgetTransfer.self)
        let preferences = all(Preferences.self).first

        func sync(_ uuid: UUID, _ created: Date, _ updated: Date?) -> [(String, JSON)] {
            [("publicId", .string(id(uuid))), ("createdAt", .string(timestamp(created))),
             ("updatedAt", updated.map { .string(timestamp($0)) } ?? .null), ("deletedAt", .null)]
        }
        func ref(_ uuid: UUID?) -> JSON { uuid.map { .string(id($0)) } ?? .null }
        func day(_ date: Date?) -> JSON { date.map { .string(Day.string($0)) } ?? .null }
        func number(_ value: Decimal?) -> JSON { value.map(JSON.number) ?? .null }
        func text(_ value: String?) -> JSON { value.map(JSON.string) ?? .null }

        var prefs: [(String, JSON)] = []
        if let preferences {
            prefs = [("hideReconciled", .bool(preferences.hideReconciled)), ("hideCleared", .bool(preferences.hideCleared))]
            if let folder = preferences.backupFolder { prefs.append(("backupFolder", .string(folder))) }
            if let days = preferences.backupRetentionDays { prefs.append(("backupRetentionDays", .number(Decimal(days)))) }
            prefs.append(("autofillPayees", .bool(preferences.autofillPayees)))
            if let theme = preferences.theme { prefs.append(("theme", .string(theme))) }
            if let page = preferences.startupPage { prefs.append(("startupPage", .string(page))) }
            let shortcuts = preferences.accountShortcuts.filter { shortcut in accounts.contains { $0.uuid == shortcut.accountUUID } }
            if !shortcuts.isEmpty {
                prefs.append(("accountShortcuts", .array(shortcuts.map { .object([
                    ("key", .string($0.key)), ("ctrl", .bool($0.ctrl)), ("accountPublicId", .string(id($0.accountUUID))),
                ]) })))
            }
            let order = preferences.accountOrder.filter { uuid in accounts.contains { $0.uuid == uuid } }
            if !order.isEmpty { prefs.append(("accountOrder", .array(order.map { .string(id($0)) }))) }
        }

        var package: [(String, JSON)] = [
            ("manifest", .object([
                ("formatVersion", .number(1)), ("applicationVersion", .string(applicationVersion)),
                ("exportedAt", .string(exportedAt.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: true)))),
                ("minimumReaderVersion", .string(applicationVersion)), ("checksum", .string("")),
            ])),
            ("preferences", .object(prefs)),
            ("accounts", .array(accounts.map { a in .object(sync(a.uuid, a.createdAt, a.updatedAt) + [
                ("name", .string(a.name)), ("number", text(a.number)), ("type", .string(a.typeRaw)),
                ("balance", .number(a.openingBalance)), ("currency", .string(a.currency)), ("notes", text(a.notes)),
                ("interestRate", number(a.interestRate)), ("creditLimit", number(a.creditLimit)), ("deleted", .bool(a.softDeleted)),
                ("pendingReconcileBalance", number(a.pendingReconcileBalance)), ("pendingReconcileDate", day(a.pendingReconcileDate)),
            ]) })),
            ("categories", .array(categories.map { c in .object(sync(c.uuid, c.createdAt, c.updatedAt) + [
                ("parentPublicId", ref(c.parent?.uuid)), ("name", .string(c.name)), ("expenseType", .string(c.kindRaw)),
                ("deleted", .bool(c.softDeleted)),
            ]) })),
            ("transactions", .array(transactions.filter { $0.account != nil }.map { t in .object(sync(t.uuid, t.createdAt, t.updatedAt) + [
                ("accountPublicId", ref(t.account?.uuid)), ("categoryPublicId", ref(t.category?.uuid)), ("date", day(t.date)),
                ("payee", .string(t.payee)), ("amount", .number(t.amount)), ("notes", text(t.notes)), ("cleared", .bool(t.cleared)),
                ("reconciled", .bool(t.reconciled)),
                ("transferTransactionPublicId", ref(t.transferUUID.flatMap { link in transactions.contains { $0.uuid == link } ? link : nil })),
            ]) })),
            ("accountReconciliations", .array(reconciliations.filter { $0.account != nil }.map { r in .object(sync(r.uuid, r.createdAt, r.updatedAt) + [
                ("accountPublicId", ref(r.account?.uuid)), ("date", day(r.date)), ("balance", .number(r.balance)), ("notes", text(r.notes)),
            ]) })),
            ("scheduledTransactions", .array(schedules.filter { $0.account != nil }.map { s in .object(sync(s.uuid, s.createdAt, s.updatedAt) + [
                ("accountPublicId", ref(s.account?.uuid)), ("categoryPublicId", ref(s.category?.uuid)), ("payee", .string(s.payee)),
                ("amount", .number(s.amount)), ("rrule", .string(s.rrule)), ("nextDueDate", day(s.nextDueDate)),
                ("autoPost", .bool(s.autoPost)), ("daysInAdvance", s.daysInAdvance.map { .number(Decimal($0)) } ?? .null),
                ("notes", text(s.notes)), ("active", .bool(s.active)), ("transferToAccountPublicId", ref(s.transferToAccount?.uuid)),
            ]) })),
            ("payees", .array(payees.map { p in .object(sync(p.uuid, p.createdAt, p.updatedAt) + [
                ("name", .string(p.name)), ("categoryPublicId", ref(p.category?.uuid)), ("amount", number(p.amount)),
            ]) })),
            ("envelopes", .array(envelopes.map { e in .object(sync(e.uuid, e.createdAt, e.updatedAt) + [
                ("name", .string(e.name)), ("active", .bool(e.active)), ("sortOrder", .number(Decimal(e.sortOrder))),
            ]) })),
            ("envelopeCategories", .array(links.filter { $0.envelope != nil && $0.category != nil }.map { l in .object(sync(l.uuid, l.createdAt, l.updatedAt) + [
                ("envelopePublicId", ref(l.envelope?.uuid)), ("categoryPublicId", ref(l.category?.uuid)),
            ]) })),
            ("budgetAllocations", .array(allocations.filter { $0.envelope != nil }.map { b in .object(sync(b.uuid, b.createdAt, b.updatedAt) + [
                ("envelopePublicId", ref(b.envelope?.uuid)), ("month", .string(b.month)), ("assigned", .number(b.assigned)),
            ]) })),
            ("budgetTransfers", .array(moves.filter { $0.fromEnvelope != nil && $0.toEnvelope != nil }.map { m in .object(sync(m.uuid, m.createdAt, m.updatedAt) + [
                ("fromEnvelopePublicId", ref(m.fromEnvelope?.uuid)), ("toEnvelopePublicId", ref(m.toEnvelope?.uuid)),
                ("month", .string(m.month)), ("amount", .number(m.amount)), ("notes", text(m.notes)),
            ]) })),
        ]
        // Hash with an empty checksum, then write the hash in (Budgie's `checksum`).
        let digest = SHA256.hash(data: Data(JSON.object(package).text.utf8)).map { String(format: "%02x", $0) }.joined()
        if case .object(var manifest) = package[0].1 {
            manifest[4] = ("checksum", .string(digest))
            package[0] = ("manifest", .object(manifest))
        }
        return Data(JSON.object(package).text.utf8)
    }

    /// Budgie's ids are lowercase UUIDs.
    static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    /// SQLite's "2026-10-27 12:34:56", as Budgie stores timestamps.
    static func timestamp(_ date: Date) -> String {
        let text = date.ISO8601Format(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        return text.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }

    /// The JSON Budgie writes: ordered keys, JavaScript number and string forms.
    indirect enum JSON {
        case null, bool(Bool), number(Decimal), string(String), array([JSON]), object([(String, JSON)])

        var text: String {
            switch self {
            case .null: "null"
            case .bool(let value): value ? "true" : "false"
            case .number(let value): JSON.number(value)
            case .string(let value): JSON.quote(value)
            case .array(let items): "[" + items.map(\.text).joined(separator: ",") + "]"
            case .object(let pairs): "{" + pairs.map { JSON.quote($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
            }
        }

        /// JavaScript prints the shortest form of the double: 70.2, 1150, -0.1.
        static func number(_ value: Decimal) -> String {
            let double = NSDecimalNumber(decimal: value).doubleValue
            if double == double.rounded(), abs(double) < 1e15 { return String(Int64(double)) }
            return "\(double)"
        }

        /// JSON.stringify escaping: quote, backslash and control characters; everything else as is.
        static func quote(_ text: String) -> String {
            var out = "\""
            for scalar in text.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                case "\r": out += "\\r"
                case "\t": out += "\\t"
                case "\u{08}": out += "\\b"
                case "\u{0C}": out += "\\f"
                default:
                    if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
                }
            }
            return out + "\""
        }
    }
}
