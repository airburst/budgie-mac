import Foundation
import SwiftData

/// M5: envelope budgeting, ported from Budgie's `budget-computations.ts` and
/// `useBudgetSummary.ts`. Months are "2026-10", as Budgie stores them.
public enum Budget {
    // MARK: Months

    public static func month(of date: Date) -> String { String(Day.string(date).prefix(7)) }
    public static var thisMonth: String { month(of: Day.today) }

    public static func month(_ month: String, adding count: Int) -> String {
        let date = Day.parse(month + "-01")!
        return Budget.month(of: Day.calendar.date(byAdding: .month, value: count, to: date)!)
    }

    /// "October 2026".
    public static func title(of month: String, locale: Locale = .current) -> String {
        let date = Day.parse(month + "-01")!
        return date.formatted(Date.FormatStyle(timeZone: Day.calendar.timeZone).month(.wide).year().locale(locale))
    }

    // MARK: Summary

    public struct Line: Identifiable {
        public let envelope: Envelope
        public let rolledOver: Decimal
        public let assigned: Decimal
        /// Spending (negative) and refunds in the envelope's categories this month.
        public let activity: Decimal
        public let movedIn: Decimal
        public let movedOut: Decimal
        public var available: Decimal { rolledOver + assigned + activity + movedIn - movedOut }
        /// The money this month could use: everything but the spending.
        public var funded: Decimal { rolledOver + assigned + movedIn - movedOut }
        /// Share of the money available that is spent, 0…1 (S-036 progress).
        public var spentShare: Double {
            let spent = max(0, -activity)
            guard funded > 0 else { return spent > 0 ? 1 : 0 }
            return min(1, NSDecimalNumber(decimal: spent / funded).doubleValue)
        }
        public var id: PersistentIdentifier { envelope.persistentModelID }
    }

    public struct Summary {
        public let month: String
        public let availableToBudget: Decimal
        public let income: Decimal
        public let assigned: Decimal
        public let overspentBefore: Decimal
        public let lines: [Line]
    }

    /// The month's budget. Available to Budget counts all income received up
    /// to the month, minus all amounts assigned up to the month, minus what
    /// envelopes overspent in earlier months (Fixes: only this month's income).
    public static func summary(for month: String, in context: ModelContext) -> Summary {
        let envelopes = (try? context.fetch(FetchDescriptor<Envelope>(sortBy: [SortDescriptor(\.sortOrder)]))) ?? []
        let allocations = (try? context.fetch(FetchDescriptor<BudgetAllocation>())) ?? []
        let transfers = (try? context.fetch(FetchDescriptor<BudgetTransfer>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        return summary(for: month, envelopes: envelopes, allocations: allocations, transfers: transfers, transactions: transactions)
    }

    public static func summary(for month: String, envelopes: [Envelope], allocations: [BudgetAllocation],
                               transfers: [BudgetTransfer], transactions: [Transaction]) -> Summary {
        // The receiving side of a transfer would count the money twice (as Budgie).
        let counted = transactions.filter { !($0.transferUUID != nil && $0.amount > 0) }

        var activity: [String: [PersistentIdentifier: Decimal]] = [:]
        var income: [String: Decimal] = [:]
        for transaction in counted {
            guard let category = transaction.category else { continue }
            let m = Budget.month(of: transaction.date)
            if category.kind == .income {
                income[m, default: 0] += transaction.amount
            } else {
                activity[m, default: [:]][category.persistentModelID, default: 0] += transaction.amount
            }
        }
        var assigned: [String: [PersistentIdentifier: Decimal]] = [:]
        for allocation in allocations {
            guard let envelope = allocation.envelope else { continue }
            assigned[allocation.month, default: [:]][envelope.persistentModelID, default: 0] += allocation.assigned
        }
        var movedIn: [String: [PersistentIdentifier: Decimal]] = [:]
        var movedOut: [String: [PersistentIdentifier: Decimal]] = [:]
        for move in transfers {
            if let to = move.toEnvelope { movedIn[move.month, default: [:]][to.persistentModelID, default: 0] += move.amount }
            if let from = move.fromEnvelope { movedOut[move.month, default: [:]][from.persistentModelID, default: 0] += move.amount }
        }

        func line(_ envelope: Envelope, in m: String, rolledOver: Decimal) -> Line {
            let id = envelope.persistentModelID
            let categories = envelope.categories.compactMap { $0.category?.persistentModelID }
            let spent = categories.reduce(Decimal(0)) { $0 + (activity[m]?[$1] ?? 0) }
            return Line(envelope: envelope, rolledOver: rolledOver, assigned: assigned[m]?[id] ?? 0, activity: spent,
                        movedIn: movedIn[m]?[id] ?? 0, movedOut: movedOut[m]?[id] ?? 0)
        }

        // Walk each envelope from its first month: what's left rolls over;
        // what's overspent doesn't, and comes out of Available to Budget instead.
        var lines: [Line] = []
        var overspentBefore: Decimal = 0
        for envelope in envelopes {
            let firstAllocation = allocations.filter { $0.envelope === envelope }.map(\.month).min()
            var current = [Budget.month(of: envelope.createdAt), firstAllocation ?? month, month].min()!
            var rolledOver: Decimal = 0
            while current < month {
                let past = line(envelope, in: current, rolledOver: rolledOver)
                if past.available < 0 { overspentBefore += -past.available }
                rolledOver = max(0, past.available)
                current = Budget.month(current, adding: 1)
            }
            if envelope.active { lines.append(line(envelope, in: month, rolledOver: rolledOver)) }
        }

        let incomeSoFar = income.filter { $0.key <= month }.values.reduce(0, +)
        let assignedSoFar = assigned.filter { $0.key <= month }.values.flatMap(\.values).reduce(0, +)
        return Summary(month: month, availableToBudget: incomeSoFar - assignedSoFar - overspentBefore,
                       income: income[month] ?? 0, assigned: assigned[month]?.values.reduce(0, +) ?? 0,
                       overspentBefore: overspentBefore, lines: lines)
    }

    // MARK: Changes

    /// S-040: sets the envelope's assigned amount for the month.
    public static func assign(_ amount: Decimal, to envelope: Envelope, in month: String, context: ModelContext) {
        if let existing = envelope.allocations.first(where: { $0.month == month }) {
            existing.assigned = amount
            existing.updatedAt = .now
        } else {
            context.insert(BudgetAllocation(envelope: envelope, month: month, assigned: amount))
        }
    }

    public static func assigned(to envelope: Envelope, in month: String) -> Decimal? {
        envelope.allocations.first { $0.month == month }?.assigned
    }

    /// S-041: moves money between envelopes for the month.
    @discardableResult
    public static func move(_ amount: Decimal, from: Envelope, to: Envelope, in month: String, notes: String?, context: ModelContext) -> BudgetTransfer? {
        guard from !== to, amount > 0 else { return nil }
        let move = BudgetTransfer(from: from, to: to, month: month, amount: amount)
        move.notes = notes
        context.insert(move)
        return move
    }

    /// S-042: fills envelopes with no assignment this month from last month.
    @discardableResult
    public static func copyLastMonth(into month: String, envelopes: [Envelope], context: ModelContext) -> Int {
        let previous = Budget.month(month, adding: -1)
        var filled = 0
        for envelope in envelopes where envelope.active && assigned(to: envelope, in: month) == nil {
            guard let last = assigned(to: envelope, in: previous) else { continue }
            assign(last, to: envelope, in: month, context: context)
            filled += 1
        }
        return filled
    }
}

/// S-038 and S-039: envelopes and the categories they track.
public enum Envelopes {
    /// The envelope a category already belongs to, if any.
    public static func owner(of category: Category, in envelopes: [Envelope]) -> Envelope? {
        envelopes.first { $0.active && $0.categories.contains { $0.category === category } }
    }

    /// A category can belong to only one envelope; ones taken elsewhere are skipped.
    public static func setCategories(_ categories: [Category], for envelope: Envelope, all envelopes: [Envelope], context: ModelContext) {
        for link in envelope.categories where !categories.contains(where: { $0 === link.category }) {
            context.delete(link)
        }
        for category in categories where !envelope.categories.contains(where: { $0.category === category }) {
            guard owner(of: category, in: envelopes.filter { $0 !== envelope }) == nil else { continue }
            context.insert(EnvelopeCategory(envelope: envelope, category: category))
        }
    }

    /// Frees its categories and hides it; its past assignments stay, so past
    /// months' totals don't change.
    public static func delete(_ envelope: Envelope, context: ModelContext) {
        for link in envelope.categories { context.delete(link) }
        envelope.active = false
        envelope.updatedAt = .now
    }

    /// S-043: renumbers so the envelopes keep the given order.
    public static func reorder(_ envelopes: [Envelope]) {
        for (index, envelope) in envelopes.enumerated() { envelope.sortOrder = index }
    }

    public struct Template: Identifiable, Sendable {
        public let name: String
        public let description: String
        public let envelopes: [(name: String, categories: [String])]
        public var id: String { name }
    }

    /// Budgie's three templates (`budget-templates.ts`).
    public static let templates: [Template] = [
        Template(name: "Starter", description: "5 envelopes covering common spending areas", envelopes: [
            ("Bills", ["Bills", "Council Tax", "Mobile"]), ("Food", ["Groceries"]),
            ("Transport", ["Motoring", "Petrol", "Parking"]), ("Personal", ["Clothing", "Entertainment", "Fitness"]),
            ("Savings", []),
        ]),
        Template(name: "Detailed", description: "8 envelopes with finer-grained category mapping", envelopes: [
            ("Mortgage/Rent", ["Rent", "Mortgage"]), ("Utilities", ["Electric", "Gas", "Water"]),
            ("Insurance", ["Insurance", "Home Insurance", "Car Insurance", "Life Insurance"]),
            ("Food", ["Groceries", "Dining out", "Wine"]), ("Transport", ["Motoring", "Petrol", "Parking", "Travel"]),
            ("Healthcare", ["Healthcare", "Dentist", "Optician"]),
            ("Personal", ["Clothing", "Entertainment", "Fitness", "Personal care"]), ("Savings", []),
        ]),
        Template(name: "Minimal", description: "3 broad envelopes, to keep it simple", envelopes: [
            ("Essentials", ["Bills", "Council Tax", "Groceries", "Motoring", "Mobile", "Insurance"]),
            ("Everything Else", ["Clothing", "Entertainment", "Fitness", "Dining out", "Holiday"]),
            ("Savings", []),
        ]),
    ]

    /// S-037: makes the template's envelopes and maps categories whose name
    /// matches (ignoring case), with their children; each category once.
    @discardableResult
    public static func apply(_ template: Template, categories: [Category], context: ModelContext) -> [Envelope] {
        let budgetable = categories.filter { !$0.softDeleted && $0.kind != .income }
        var used = Set<PersistentIdentifier>()
        var made: [Envelope] = []
        for (index, definition) in template.envelopes.enumerated() {
            let envelope = Envelope(name: definition.name, sortOrder: index)
            context.insert(envelope)
            made.append(envelope)
            for pattern in definition.categories {
                for category in budgetable where category.name.caseInsensitiveCompare(pattern) == .orderedSame {
                    for match in [category] + budgetable.filter({ $0.parent === category }) where used.insert(match.persistentModelID).inserted {
                        context.insert(EnvelopeCategory(envelope: envelope, category: match))
                    }
                }
            }
        }
        return made
    }
}
