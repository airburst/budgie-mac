import Foundation
import SwiftData
import Testing
@testable import BudgieMacKit

/// S-061: how well import rules do on your own data. Runs only when pointed
/// at a bank QIF and a copy of a store in /tmp (never the real one):
///
///     IMPORT_EVAL_QIF=/tmp/joint.qif IMPORT_EVAL_STORE=/tmp/copy.store IMPORT_EVAL_ACCOUNT=Joint \
///       swift test --filter ImportEval
///
/// It imports the file a month at a time and scores each duplicate's
/// suggested category against the one you entered, then learns from it, so
/// earlier rows teach later ones as the review sheet will (S-062).
private let environment = ProcessInfo.processInfo.environment

@Suite("Import rules on real data", .enabled(if: environment["IMPORT_EVAL_QIF"] != nil && environment["IMPORT_EVAL_STORE"] != nil))
@MainActor
struct ImportEvalTests {
    @Test("Learning month by month fills at least 70% of categories, 80% of them right")
    func monthByMonth() throws {
        let store = URL(fileURLWithPath: environment["IMPORT_EVAL_STORE"]!).resolvingSymlinksInPath()
        try #require(store.path.hasPrefix("/tmp/") || store.path.hasPrefix("/private/tmp/"), "IMPORT_EVAL_STORE must be a copy in /tmp")
        // Work on a copy of the copy, so the run leaves nothing behind.
        let scratch = FileManager.default.temporaryDirectory.appending(path: "import-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: store.path + suffix) {
            try FileManager.default.copyItem(atPath: store.path + suffix, toPath: scratch.appending(path: "eval.store").path + suffix)
        }
        let container = try BudgieSchema.container(url: scratch.appending(path: "eval.store"))
        let context = container.mainContext
        context.autosaveEnabled = false

        let name = environment["IMPORT_EVAL_ACCOUNT"] ?? "Joint"
        let account = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.name == name }, "No account named \(name)")
        let text = try String(contentsOfFile: environment["IMPORT_EVAL_QIF"]!, encoding: .utf8)
        let rows = try Qif.parse(text).rows
        let months = Dictionary(grouping: rows) { String(Day.string($0.date).prefix(7)) }

        var duplicates = 0, filled = 0, right = 0
        var report: [String] = []
        for month in months.keys.sorted() {
            let matches = Qif.match(months[month]!, existing: account.transactions, lastReconciled: nil)
            let book = ImportRuleBook(context: context)
            var monthRight = 0, monthDuplicates = 0
            let byUUID = Dictionary(account.transactions.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            for match in matches {
                guard let uuid = match.matched?.uuid, let truth = byUUID[uuid] else { continue }
                monthDuplicates += 1
                let suggestion = book.suggestion(for: match.row.payee, amount: match.row.amount)
                if let suggestion {
                    filled += 1
                    if suggestion.category?.persistentModelID == truth.category?.persistentModelID { right += 1; monthRight += 1 }
                }
                if environment["IMPORT_EVAL_VERBOSE"] != nil, suggestion?.category?.persistentModelID != truth.category?.persistentModelID {
                    print("MISS \(match.row.payee) | \(match.row.amount) | \(suggestion.map { "\($0.source) \($0.payee) → \($0.category?.path ?? "none")" } ?? "blank") | yours \(truth.payee) → \(truth.category?.path ?? "none")")
                }
                // Learn after scoring: earlier duplicates in a file teach its later rows (S-062).
                book.learn(from: match.row, matched: truth)
            }
            duplicates += monthDuplicates
            if monthDuplicates > 0 {
                report.append("\(month): \(monthDuplicates) duplicates, \(monthRight * 100 / monthDuplicates)% right")
            }
        }
        let rightShare = Double(right) / Double(max(duplicates, 1))
        let precision = Double(right) / Double(max(filled, 1))
        print(report.joined(separator: "\n"))
        print("IMPORT EVAL \(rows.count) rows, \(duplicates) duplicates: \(right) right (\(Int(rightShare * 100))%), \(filled) filled (\(Int(precision * 100))% of them right), \(duplicates - filled) blank")
        #expect(rightShare >= 0.7)
        #expect(precision >= 0.8)
    }
}
