import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

@MainActor
@Suite("Account order")
struct AccountOrderTests {
    let container = try! BudgieSchema.inMemory()
    var context: ModelContext { container.mainContext }

    private func accounts(_ names: String...) -> [Account] {
        let made = names.map { Account(name: $0) }
        made.forEach(context.insert)
        return made
    }

    @Test("With no saved order, accounts are by name; new accounts go after the saved ones")
    func sorting() {
        let all = accounts("Joint", "Chase Saver", "Current")
        #expect(AccountOrder.sorted(all, by: []).map(\.name) == ["Chase Saver", "Current", "Joint"])
        let joint = all[0], current = all[2]
        #expect(AccountOrder.sorted(all, by: [joint.uuid, current.uuid]).map(\.name) == ["Joint", "Current", "Chase Saver"])
    }

    @Test("Dragging Joint to the top and Chase Saver to the bottom")
    func dragging() {
        let shown = AccountOrder.sorted(accounts("Joint", "Chase Saver", "Current"), by: [])
        let jointFirst = AccountOrder.moving(shown, from: [2], to: 0)
        let afterFirst = AccountOrder.sorted(shown, by: jointFirst)
        #expect(afterFirst.map(\.name) == ["Joint", "Chase Saver", "Current"])
        let saverLast = AccountOrder.moving(afterFirst, from: [1], to: 3)
        #expect(AccountOrder.sorted(shown, by: saverLast).map(\.name) == ["Joint", "Current", "Chase Saver"])
    }

    @Test("Move Up and Move Down stop at the ends")
    func stepping() {
        let shown = accounts("A", "B", "C")
        #expect(AccountOrder.moving(shown[0], by: -1, in: shown) == nil)
        #expect(AccountOrder.moving(shown[2], by: 1, in: shown) == nil)
        #expect(AccountOrder.moving(shown[0], by: 1, in: shown) == [shown[1].uuid, shown[0].uuid, shown[2].uuid])
        #expect(AccountOrder.moving(shown[2], by: -1, in: shown) == [shown[0].uuid, shown[2].uuid, shown[1].uuid])
    }
}
