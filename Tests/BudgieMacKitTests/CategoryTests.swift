import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit


/// S-015: the category tree.
@MainActor
@Suite("Categories")
struct CategoryTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("A new store gets Budgie's default tree, once")
    func seeds() throws {
        #expect(DefaultCategories.seedIfEmpty(context) == 63)
        #expect(DefaultCategories.seedIfEmpty(context) == 0)
        let all = try context.fetch(FetchDescriptor<Category>())
        #expect(all.count == 63)
        let fuel = try #require(all.first { $0.name == "Fuel" })
        #expect(fuel.path == "Motoring > Fuel")
        #expect(all.first { $0.name == "Salary" }?.kind == .income)
        #expect(all.first { $0.name == "Transfer" }?.kind == .transfer)
    }

    @Test("A search keeps a match's parent visible")
    func search() {
        let motoring = Category(name: "Motoring"), fuel = Category(name: "Fuel", parent: motoring)
        let servicing = Category(name: "Servicing", parent: motoring), food = Category(name: "Food")
        let all = [motoring, fuel, servicing, food]
        let found = CategoryTree.nodes(all, search: "fue")
        #expect(found.map(\.category.name) == ["Motoring"])
        #expect(found.first?.children?.map(\.category.name) == ["Fuel"])
        let parentMatch = CategoryTree.nodes(all, search: "motor")
        #expect(parentMatch.first?.children?.count == 2)
        #expect(CategoryTree.nodes(all).map(\.category.name) == ["Food", "Motoring"])
    }
}

/// S-016 and S-017.
@MainActor
@Suite("Category editing")
struct CategoryEditingTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    @Test("A sibling's name is refused, ignoring case; cousins may share it")
    func duplicates() throws {
        let food = try CategoryDraft(name: "Food").add(in: context)
        var dup = CategoryDraft()
        dup.name = "  food "
        #expect(throws: CategoryDraft.Problem.duplicate("Food")) { try dup.add(in: context) }
        var child = CategoryDraft(parent: food)
        child.name = "Food"
        #expect(try child.add(in: context).path == "Food > Food")
        #expect(throws: CategoryDraft.Problem.noName) { try CategoryDraft().add(in: context) }
    }

    @Test("Transfer is a type you can choose, and children start with their parent's type")
    func transferKind() throws {
        var draft = CategoryDraft(name: "Moves")
        draft.kind = .transfer
        let moves = try draft.add(in: context)
        #expect(moves.kind == .transfer)
        #expect(CategoryDraft(parent: moves).kind == .transfer)
    }

    @Test("Renaming checks siblings but not itself")
    func rename() throws {
        let a = try CategoryDraft(name: "A").add(in: context)
        try CategoryDraft(name: "B").add(in: context)
        var draft = CategoryDraft(a)
        draft.name = "a"
        try draft.apply(to: a, in: context)
        #expect(a.name == "a")
        draft.name = "b"
        #expect(throws: CategoryDraft.Problem.duplicate("B")) { try draft.apply(to: a, in: context) }
    }

    @Test("A parent with children can't be deleted; a used category leaves its transactions uncategorised")
    func deletion() throws {
        let parent = try CategoryDraft(name: "Food").add(in: context)
        let child = try CategoryDraft(name: "Takeaway", parent: parent).add(in: context)
        #expect(CategoryDeletion.blocked(parent) != nil)
        #expect(CategoryDeletion.blocked(child) == nil)
        let account = Account(name: "Bank")
        context.insert(account)
        let meal = Transaction(account: account, payee: "Noodles", amount: -10, category: child)
        context.insert(meal)
        #expect(CategoryDeletion.usage(child) == 1)
        let lost = CategoryDeletion.delete(child)
        #expect(meal.category == nil && child.softDeleted && lost.count == 1)
        #expect(CategoryDeletion.blocked(parent) == nil)
        CategoryDeletion.restore(child, to: lost)
        #expect(meal.category === child && !child.softDeleted)
    }
}

extension CategoryDraft {
    fileprivate init(name: String, parent: Category? = nil) {
        self.init(parent: parent)
        self.name = name
    }
}
