import Foundation

/// The order of accounts in the sidebar, All Accounts and View > Accounts.
/// People drag accounts into place; the order is kept in Preferences as
/// account ids. Accounts not in the saved order (new ones) go last, by name.
public enum AccountOrder {
    public static func sorted(_ accounts: [Account], by order: [UUID]) -> [Account] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return accounts.sorted { a, b in
            switch (rank[a.uuid], rank[b.uuid]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }

    /// The new order after a drag of `offsets` in `shown` to `destination`.
    public static func moving(_ shown: [Account], from offsets: IndexSet, to destination: Int) -> [UUID] {
        var ids = shown.map(\.uuid)
        let moved = offsets.sorted().map { ids[$0] }
        let before = offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { ids.remove(at: index) }
        ids.insert(contentsOf: moved, at: destination - before)
        return ids
    }

    /// The new order after moving one account up (-1) or down (+1), or nil at either end.
    public static func moving(_ account: Account, by step: Int, in shown: [Account]) -> [UUID]? {
        guard let index = shown.firstIndex(where: { $0 === account }) else { return nil }
        let target = index + step
        guard shown.indices.contains(target) else { return nil }
        return moving(shown, from: [index], to: step > 0 ? target + 1 : target)
    }
}
