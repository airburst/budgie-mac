import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

private typealias Category = BudgieMacKit.Category

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
