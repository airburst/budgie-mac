import Foundation
import SwiftData

/// S-015: the category tree Budgie seeds on a new database
/// (`src/main/db/migrations/0001_seed_categories.sql` and later migrations).
public enum DefaultCategories {
    /// (name, kind, parent name), parents before their children.
    static let tree: [(String, CategoryKind, String?)] = [
        ("Allowance", .expense, nil),
        ("Bank charge", .expense, nil),
        ("Bills", .expense, nil),
        ("Business expense", .expense, nil),
        ("Cash withdrawal", .expense, nil),
        ("Charitable donation", .expense, nil),
        ("Clothing", .expense, nil),
        ("Council Tax", .expense, nil),
        ("Education", .expense, nil),
        ("Entertainment", .expense, nil),
        ("Fitness", .expense, nil),
        ("Food", .expense, nil),
        ("Gifts", .expense, nil),
        ("Healthcare", .expense, nil),
        ("Holiday", .expense, nil),
        ("Home", .expense, nil),
        ("Household", .expense, nil),
        ("Insurance", .expense, nil),
        ("Interest", .income, nil),
        ("Loan", .expense, nil),
        ("Miscellaneous", .expense, nil),
        ("Mobile", .expense, nil),
        ("Motoring", .expense, nil),
        ("Other income", .income, nil),
        ("Parking", .expense, nil),
        ("Personal care", .expense, nil),
        ("Pet care", .expense, nil),
        ("Pets", .expense, nil),
        ("Retirement income", .income, nil),
        ("Salary", .income, nil),
        ("School", .expense, nil),
        ("Taxes", .expense, nil),
        ("Transfer", .transfer, nil),
        ("Travel", .expense, nil),
        ("Broadband", .expense, "Bills"),
        ("Cable/satellite", .expense, "Bills"),
        ("Electric", .expense, "Bills"),
        ("Garbage", .expense, "Bills"),
        ("Gas", .expense, "Bills"),
        ("Homeowners dues", .expense, "Bills"),
        ("Internet", .expense, "Bills"),
        ("Mortgage", .expense, "Bills"),
        ("Phone", .expense, "Bills"),
        ("Rent", .expense, "Bills"),
        ("Water/sewer", .expense, "Bills"),
        ("Non-reimbursed", .expense, "Business expense"),
        ("Reimbursed", .expense, "Business expense"),
        ("Dining out", .expense, "Food"),
        ("Groceries", .expense, "Food"),
        ("Wine", .expense, "Food"),
        ("Dental", .expense, "Healthcare"),
        ("Hospital", .expense, "Healthcare"),
        ("Prescriptions", .expense, "Healthcare"),
        ("Vision", .expense, "Healthcare"),
        ("Maintenance", .expense, "Household"),
        ("Car", .expense, "Insurance"),
        ("Health", .expense, "Insurance"),
        ("Home", .expense, "Insurance"),
        ("Life", .expense, "Insurance"),
        ("Payment", .expense, "Loan"),
        ("Fuel", .expense, "Motoring"),
        ("Servicing", .expense, "Motoring"),
        ("Tax", .expense, "Motoring"),
    ]

    /// Fills an empty store with the default tree. Does nothing if any category exists.
    @discardableResult
    public static func seedIfEmpty(_ context: ModelContext) -> Int {
        guard ((try? context.fetchCount(FetchDescriptor<Category>())) ?? 0) == 0 else { return 0 }
        var parents: [String: Category] = [:]
        for (name, kind, parentName) in tree {
            let category = Category(name: name, kind: kind, parent: parentName.flatMap { parents[$0] })
            context.insert(category)
            if parentName == nil { parents[name] = category }
        }
        return tree.count
    }
}

/// S-015: the Categories page's rows.
public enum CategoryTree {
    public struct Node: Identifiable {
        public let category: Category
        public let children: [Node]?
        public var id: PersistentIdentifier { category.persistentModelID }
    }

    /// Top-level categories with their children, by name. A search keeps a
    /// matching child's parent, so the match is seen in context.
    public static func nodes(_ categories: [Category], search: String = "") -> [Node] {
        let live = categories.filter { !$0.deleted }
        let text = search.trimmingCharacters(in: .whitespaces)
        func matches(_ category: Category) -> Bool { text.isEmpty || category.name.localizedStandardContains(text) }
        func byName(_ a: Category, _ b: Category) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        return live.filter { $0.parent == nil }.sorted(by: byName).compactMap { parent in
            let children = live.filter { $0.parent === parent }.sorted(by: byName)
            let shownChildren = matches(parent) ? children : children.filter(matches)
            guard matches(parent) || !shownChildren.isEmpty else { return nil }
            return Node(category: parent, children: shownChildren.isEmpty ? nil : shownChildren.map { Node(category: $0, children: nil) })
        }
    }
}

public extension Category {
    /// Children still in use.
    var liveChildren: [Category] { children.filter { !$0.deleted } }
}
