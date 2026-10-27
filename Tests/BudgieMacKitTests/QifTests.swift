import Foundation
import Testing
@testable import BudgieMacKit

/// S-055: ported from Budgie's qif-parser.test.ts and qif-matcher.test.ts.
@Suite("QIF")
struct QifTests {
    private func day(_ text: String) -> Date { Day.parse(text)! }

    @Test("Parses a basic QIF file, with memo, sorted by date")
    func basic() throws {
        let (kind, rows) = try Qif.parse("!Type:Bank\nD09/03/2026\nPCorner Grocer\nT-70.20\nMWeekly shop\n^\nD05/03/2026\nPEmployer\nT2500.00\n^\n")
        #expect(kind == .bank)
        #expect(rows.map { Day.string($0.date) } == ["2026-03-05", "2026-03-09"])
        #expect(rows[1] == Qif.Row(date: day("2026-03-09"), payee: "Corner Grocer", amount: Decimal(string: "-70.20")!, memo: "Weekly shop"))
    }

    @Test("Credit card amounts are negated")
    func creditCard() throws {
        let (kind, rows) = try Qif.parse("!Type:CCard\nD01/03/2026\nPShop\nT36.00\n^\nD02/03/2026\nPRefund\nT-164\n^")
        #expect(kind == .creditCard && rows.map(\.amount) == [-36, 164])
    }

    @Test("Refuses other types and empty files")
    func refuses() {
        #expect(throws: Qif.Failure.notQif) { try Qif.parse("!Type:Invst\nD01/01/2026\nPFoo\nT-5\n^") }
        #expect(throws: Qif.Failure.notQif) { try Qif.parse("") }
    }

    @Test("Amounts without decimals or with commas; no trailing ^; Windows lines; empty blocks; padding")
    func edges() throws {
        #expect(try Qif.parse("!Type:Bank\nD01/03/2026\nPPay\nT500\n^").rows.first?.amount == 500)
        #expect(try Qif.parse("!Type:Bank\nD01/03/2026\nPBig\nT-1,234.56\n^").rows.first?.amount == Decimal(string: "-1234.56")!)
        #expect(try Qif.parse("!Type:Bank\nD01/03/2026\nPLast\nT-1").rows.count == 1)
        #expect(try Qif.parse("!Type:Bank\r\nD01/03/2026\r\nPWin\r\nT-1\r\n^\r\n").rows.count == 1)
        #expect(try Qif.parse("!Type:Bank\n^\n^\nD01/03/2026\nPOne\nT-1\n^\n^").rows.count == 1)
        #expect(try Qif.parse("!Type:Bank\nD1/3/2026\nPPad\nT-1\n^").rows.first.map { Day.string($0.date) } == "2026-03-01")
    }

    @Test("Duplicates match by amount within 3 days, once each; reconciled dates are out of range")
    @MainActor
    func matcher() {
        let existing = [Transaction(account: nil, date: day("2026-03-05"), payee: "Corner Grocer", amount: -70)]
        let rows = [
            Qif.Row(date: day("2026-03-07"), payee: "CORNER GROCER", amount: -70),
            Qif.Row(date: day("2026-03-07"), payee: "Corner Grocer", amount: -70),
            Qif.Row(date: day("2026-03-20"), payee: "Shop", amount: -70),
            Qif.Row(date: day("2026-02-01"), payee: "Old", amount: -5),
        ]
        let matches = Qif.match(rows, existing: existing, lastReconciled: day("2026-02-28"))
        #expect(matches.map(\.status) == [.duplicate, .new, .new, .reconciled])
        #expect(matches.map(\.checked) == [false, true, true, false])
        #expect(matches[0].duplicateOf == existing[0].uuid)
    }
}
