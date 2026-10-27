import Foundation
import SwiftData

/// S-016 and S-017: what the category sheet edits.
public struct CategoryDraft {
    public enum Problem: Error, Equatable, Sendable {
        case noName, duplicate(String)

        public var message: String {
            switch self {
            case .noName: "Enter a name."
            case .duplicate(let name): "There's already a category called “\(name)” here."
            }
        }
    }

    public var name = ""
    public var kind: CategoryKind = .expense
    public var parent: Category?

    public init(parent: Category? = nil) {
        self.parent = parent
        if let parent { kind = parent.kind }
    }

    public init(_ category: Category) {
        name = category.name
        kind = category.kind
        parent = category.parent
    }

    var cleanName: String { name.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    /// A name that matches a sibling's, ignoring case, is refused (Fixes: duplicates allowed).
    public func problem(among categories: [Category], editing: Category? = nil) -> Problem? {
        let name = cleanName
        guard !name.isEmpty else { return .noName }
        let siblings = categories.filter { !$0.softDeleted && $0.parent === parent && $0 !== editing }
        if let clash = siblings.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return .duplicate(clash.name)
        }
        return nil
    }

    @discardableResult
    public func add(in context: ModelContext) throws(Problem) -> Category {
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if let problem = problem(among: all) { throw problem }
        let category = Category(name: cleanName, kind: kind, parent: parent)
        context.insert(category)
        return category
    }

    public func apply(to category: Category, in context: ModelContext) throws(Problem) {
        let all = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        if let problem = problem(among: all, editing: category) { throw problem }
        category.name = cleanName
        category.kind = kind
        category.updatedAt = .now
    }
}

public enum CategoryDeletion {
    /// Why Delete is off, or nil when it's allowed.
    public static func blocked(_ category: Category) -> String? {
        let count = category.liveChildren.count
        guard count > 0 else { return nil }
        return "Delete or move its \(count == 1 ? "sub-category" : "\(count) sub-categories") first."
    }

    /// Transactions that use the category, which become uncategorised.
    public static func usage(_ category: Category) -> Int {
        category.transactions.count
    }

    /// Soft-deletes the category; its transactions become uncategorised.
    /// Returns the transactions that lost it, for Undo.
    @discardableResult
    public static func delete(_ category: Category) -> [Transaction] {
        let used = category.transactions
        for transaction in used { transaction.category = nil }
        category.softDeleted = true
        category.updatedAt = .now
        return used
    }

    public static func restore(_ category: Category, to transactions: [Transaction]) {
        category.softDeleted = false
        for transaction in transactions { transaction.category = category }
    }
}
