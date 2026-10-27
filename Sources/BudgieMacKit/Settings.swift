import Foundation
import SwiftData

/// S-052: General settings, stored in Preferences as Budgie stores them.
public enum Appearance: String, CaseIterable, Sendable {
    case system = "auto", light, dark

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public extension Preferences {
    var appearance: Appearance {
        get { theme.flatMap(Appearance.init) ?? .system }
        set { theme = newValue == .system ? nil : newValue.rawValue }
    }
}

/// Where the app opens: a page ("budget") or an account ("account:<uuid>").
public enum StartPage: Hashable, Sendable {
    case page(String)
    case account(UUID)

    public init?(_ text: String?) {
        guard let text, !text.isEmpty else { return nil }
        if text.hasPrefix("account:") {
            guard let uuid = UUID(uuidString: String(text.dropFirst(8))) else { return nil }
            self = .account(uuid)
        } else {
            self = .page(text)
        }
    }

    public var text: String {
        switch self {
        case .page(let name): name
        case .account(let uuid): "account:\(uuid.uuidString)"
        }
    }
}

/// S-054: backups are Budgie data files in a folder, pruned by age.
public enum Backups {
    public static let defaultRetentionDays = 30
    static let prefix = "BudgieMac-backup-"

    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "BudgieMac/Backups", directoryHint: .isDirectory)
    }

    public struct Backup: Identifiable, Hashable, Sendable {
        public let url: URL
        public let date: Date
        public let size: Int
        public var id: URL { url }
    }

    /// Writes a backup, then deletes ones older than the retention period.
    @discardableResult
    public static func write(_ data: Data, to folder: URL, now: Date = .now, retentionDays: Int = defaultRetentionDays) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = now.formatted(Date.VerbatimFormatStyle(format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
                                                            timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        let url = folder.appending(path: "\(prefix)\(stamp).json")
        try data.write(to: url, options: .atomic)
        prune(folder, now: now, retentionDays: retentionDays)
        return url
    }

    /// Newest first.
    public static func list(_ folder: URL) -> [Backup] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Backup(url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
        .sorted { $0.date > $1.date }
    }

    /// Deletes backups older than the retention period, always keeping the newest.
    @discardableResult
    public static func prune(_ folder: URL, now: Date = .now, retentionDays: Int = defaultRetentionDays) -> Int {
        let cutoff = now.addingTimeInterval(-Double(max(1, retentionDays)) * 86_400)
        var removed = 0
        for backup in list(folder).dropFirst() where backup.date < cutoff {
            if (try? FileManager.default.removeItem(at: backup.url)) != nil { removed += 1 }
        }
        return removed
    }
}
