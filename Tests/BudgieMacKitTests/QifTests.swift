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

    @Test("S-060: a duplicate pairs with the transaction its bank text names, then the nearest date")
    @MainActor
    func pairsByName() {
        let asda = Transaction(account: nil, date: day("2026-04-07"), payee: "Asda", amount: -1.5)
        let parking = Transaction(account: nil, date: day("2026-04-07"), payee: "Parking", amount: -1.5)
        let rows = [
            Qif.Row(date: day("2026-04-07"), payee: "MIPERMIT LTD", amount: -1.5),
            Qif.Row(date: day("2026-04-08"), payee: "ASDA  STORES 4345", amount: -1.5),
        ]
        let matches = Qif.match(rows, existing: [asda, parking], lastReconciled: nil)
        #expect(matches.map(\.duplicateOf) == [parking.uuid, asda.uuid])
        #expect(matches[1].matched == Qif.Matched(uuid: asda.uuid, payee: "Asda", date: day("2026-04-07"), amount: -1.5))
    }

    @Test("S-060: with no name to go on, the nearest date wins")
    @MainActor
    func pairsByDate() {
        let early = Transaction(account: nil, date: day("2026-07-28"), payee: "Kindle", amount: -5.99)
        let late = Transaction(account: nil, date: day("2026-07-31"), payee: "Books", amount: -5.99)
        let rows = [Qif.Row(date: day("2026-07-31"), payee: "amazon.co.uk*6D7MG", amount: -5.99)]
        #expect(Qif.match(rows, existing: [early, late], lastReconciled: nil).first?.duplicateOf == late.uuid)
    }

    @Test("S-060: bank text loses processors, references, numbers and filler words")
    func cleaning() {
        #expect(Qif.cleaned("CO-OP GROUP 070590") == ["COOP"])
        #expect(Qif.cleaned("ZETTLE_*THE BERTIN") == ["BERTIN"])
        #expect(Qif.cleaned("SumUp  *CHAO CHAO") == ["CHAO", "CHAO"])
        #expect(Qif.cleaned("PAYPAL_*THE BERTIN") == ["BERTIN"])
        #expect(Qif.cleaned("AMZNMktplace*BB9G4") == ["AMZNMKTPLACE"])
        #expect(Qif.cleaned("SAINSBURYS S/MKTS") == ["SAINSBURYS", "S"])
        #expect(Qif.cleaned("LNK COOPERATIVE SN") == ["COOPERATIVE", "SN"])
        #expect(Qif.cleaned("VODAFONE LTD") == ["VODAFONE"])
    }

    @Test("S-060: bank text names a payee by whole words only")
    func naming() {
        #expect(Qif.names("CO-OP GROUP 070590", "Coop"))
        #expect(Qif.names("B & Q 1330", "B&Q"))
        #expect(Qif.names("SCOTTISHPOWER", "Scottish Power"))
        #expect(Qif.names("SAINSBURYS PETROL", "Sainsburys"))
        #expect(Qif.names("vodafone", "Vodafone"))
        #expect(!Qif.names("MARKS&SPENCER PLC", "Mark"))
        #expect(!Qif.names("MIPERMIT LTD", "Parking"))
        #expect(!Qif.names("ASDA", "As"))
    }
}
