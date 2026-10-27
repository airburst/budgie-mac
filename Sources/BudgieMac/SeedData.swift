import Foundation
import SwiftData

/// Sample data for snapshots: APP_SEED=1 with APP_STORE in /tmp fills an empty
/// store with realistic accounts (short and long names, open and closed).
/// Replace these with your app's own types. Seed only what a person can
/// create in the app, or the snapshots show features no one can use.
@MainActor
enum SeedData {
    static func insertIfRequested(into model: AppModel) {
        guard ProcessInfo.processInfo.environment["APP_SEED"] == "1" else { return }
        guard Store.isOverridden else {
            print("APP_SEED ignored: APP_STORE must be a file in /tmp")
            return
        }
        let context = model.container.mainContext
        guard ((try? context.fetchCount(FetchDescriptor<Account>())) ?? 0) == 0 else { return }
        let samples: [(String, Bool)] = [
            ("Current Account", false),
            ("Joint Account", false),
            ("Easy Access Savings", false),
            ("Credit Card", false),
            ("Cash", false),
            ("Stocks and Shares ISA held with the investment platform since 2019", false),
            ("Car Loan", true),
            ("Old Current Account", true),
        ]
        for (index, sample) in samples.enumerated() {
            let account = Account(name: sample.0)
            account.isClosed = sample.1
            account.createdAt = Date.now.addingTimeInterval(Double(-index) * 3_600)
            context.insert(account)
        }
        try? context.save()
    }
}
