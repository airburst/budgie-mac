import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

typealias Category = BudgieMacKit.Category

/// M5: envelope budgeting.
@MainActor
@Suite("Budget")
struct BudgetTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    struct Fixture {
        let bank: Account
        let salary: Category
        let groceries: Category
        let fun: Category
        let food: Envelope
        let play: Envelope
    }

    private func fixture() -> Fixture {
        let bank = Account(name: "Bank")
        let salary = Category(name: "Salary", kind: .income)
        let groceries = Category(name: "Groceries"), fun = Category(name: "Fun")
        let food = Envelope(name: "Food", sortOrder: 0), play = Envelope(name: "Play", sortOrder: 1)
        food.createdAt = Day.parse("2026-08-01")!
        play.createdAt = Day.parse("2026-08-01")!
        context.insert(bank)
        [salary, groceries, fun].forEach(context.insert)
        [food, play].forEach(context.insert)
        context.insert(EnvelopeCategory(envelope: food, category: groceries))
        context.insert(EnvelopeCategory(envelope: play, category: fun))
        return Fixture(bank: bank, salary: salary, groceries: groceries, fun: fun, food: food, play: play)
    }

    private func spend(_ f: Fixture, _ day: String, _ amount: String, _ category: Category) {
        context.insert(Transaction(account: f.bank, date: Day.parse(day)!, payee: day, amount: Decimal(string: amount)!, category: category))
    }

    @Test("Available to Budget counts all income so far, all assigned so far, and earlier overspending")
    func availableToBudget() {
        let f = fixture()
        spend(f, "2026-08-25", "2000", f.salary)
        spend(f, "2026-09-25", "2000", f.salary)
        Budget.assign(300, to: f.food, in: "2026-09", context: context)
        Budget.assign(100, to: f.play, in: "2026-09", context: context)
        spend(f, "2026-09-10", "-150", f.fun) // Play overspends by 50 in September
        Budget.assign(300, to: f.food, in: "2026-10", context: context)
        let october = Budget.summary(for: "2026-10", in: context)
        #expect(october.overspentBefore == 50)
        #expect(october.availableToBudget == 3250, "\(october.availableToBudget) income \(october.income) assigned \(october.assigned)")
        let september = Budget.summary(for: "2026-09", in: context)
        #expect(september.availableToBudget == 3600, "\(september.availableToBudget)")
    }

    @Test("Envelope available = rolled over + assigned + spending + moved in − moved out")
    func envelopeAvailable() {
        let f = fixture()
        Budget.assign(300, to: f.food, in: "2026-09", context: context)
        spend(f, "2026-09-12", "-250", f.groceries) // 50 rolls over
        Budget.assign(300, to: f.food, in: "2026-10", context: context)
        spend(f, "2026-10-03", "-70.20", f.groceries)
        Budget.assign(20, to: f.play, in: "2026-10", context: context)
        Budget.move(25, from: f.food, to: f.play, in: "2026-10", notes: nil, context: context)
        let october = Budget.summary(for: "2026-10", in: context)
        let food = october.lines.first { $0.envelope === f.food }!
        #expect(food.rolledOver == 50 && food.assigned == 300 && food.activity == Decimal(string: "-70.20")!)
        #expect(food.available == Decimal(string: "254.80")!)
        let play = october.lines.first { $0.envelope === f.play }!
        #expect(play.available == 45)
    }

    @Test("Moving money changes both envelopes but not Available to Budget")
    func move() {
        let f = fixture()
        Budget.assign(100, to: f.food, in: "2026-10", context: context)
        let before = Budget.summary(for: "2026-10", in: context)
        #expect(Budget.move(0, from: f.food, to: f.play, in: "2026-10", notes: nil, context: context) == nil)
        #expect(Budget.move(10, from: f.food, to: f.food, in: "2026-10", notes: nil, context: context) == nil)
        Budget.move(40, from: f.food, to: f.play, in: "2026-10", notes: "Treat", context: context)
        let after = Budget.summary(for: "2026-10", in: context)
        #expect(after.availableToBudget == before.availableToBudget)
        #expect(after.lines.map(\.available) == [60, 40])
    }

    @Test("Spent share follows moved money and only overspending is over 1")
    func spentShare() {
        let f = fixture()
        Budget.assign(100, to: f.food, in: "2026-10", context: context)
        Budget.move(50, from: f.food, to: f.play, in: "2026-10", notes: nil, context: context)
        spend(f, "2026-10-02", "-25", f.groceries)
        let food = Budget.summary(for: "2026-10", in: context).lines.first { $0.envelope === f.food }!
        #expect(food.spentShare == 0.5 && food.available == 25)
    }

    @Test("Copying last month fills only empty envelopes")
    func copyLastMonth() {
        let f = fixture()
        Budget.assign(300, to: f.food, in: "2026-09", context: context)
        Budget.assign(100, to: f.play, in: "2026-09", context: context)
        Budget.assign(80, to: f.play, in: "2026-10", context: context)
        #expect(Budget.copyLastMonth(into: "2026-10", envelopes: [f.food, f.play], context: context) == 1)
        #expect(Budget.assigned(to: f.food, in: "2026-10") == 300 && Budget.assigned(to: f.play, in: "2026-10") == 80)
    }

    @Test("A category belongs to one envelope; deleting an envelope frees them and keeps past totals")
    func envelopes() throws {
        let f = fixture()
        Envelopes.setCategories([f.groceries, f.fun], for: f.food, all: [f.food, f.play], context: context)
        try context.save()
        #expect(f.food.categories.compactMap(\.category?.name).sorted() == ["Groceries"])
        #expect(Envelopes.owner(of: f.fun, in: [f.food, f.play]) === f.play)

        spend(f, "2026-09-25", "1000", f.salary)
        Budget.assign(200, to: f.play, in: "2026-09", context: context)
        let before = Budget.summary(for: "2026-09", in: context).availableToBudget
        Envelopes.delete(f.play, context: context)
        try context.save()
        #expect(Envelopes.owner(of: f.fun, in: [f.food, f.play]) == nil)
        #expect(Budget.summary(for: "2026-09", in: context).availableToBudget == before)
        #expect(Budget.summary(for: "2026-09", in: context).lines.count == 1)
    }

    @Test("A template makes its envelopes and maps matching categories with their children")
    func template() throws {
        DefaultCategories.seedIfEmpty(context)
        let categories = try context.fetch(FetchDescriptor<Category>())
        let starter = Envelopes.templates.first { $0.name == "Starter" }!
        let made = Envelopes.apply(starter, categories: categories, context: context)
        try context.save()
        #expect(made.map(\.name) == ["Bills", "Food", "Transport", "Personal", "Savings"])
        let transport = made[2].categories.compactMap(\.category?.name)
        #expect(transport.contains("Motoring") && transport.contains("Fuel"))
        #expect(made[4].categories.isEmpty)
    }

    @Test("Reordering saves the new order")
    func reorder() {
        let f = fixture()
        Envelopes.reorder([f.play, f.food])
        #expect(f.play.sortOrder == 0 && f.food.sortOrder == 1)
    }

    @Test("Months step and print")
    func months() {
        #expect(Budget.month("2026-01", adding: -1) == "2025-12")
        #expect(Budget.month("2026-12", adding: 1) == "2027-01")
        #expect(Budget.title(of: "2026-10", locale: Locale(identifier: "en_GB")) == "October 2026")
    }
}
