import Foundation

/// Update checks: the latest GitHub release, compared with this version.
/// The app does the fetching and the notification; the rules live here.
public enum Updates {
    /// Published releases only: GitHub leaves out drafts and pre-releases.
    public static let latestURL = URL(string: "https://api.github.com/repos/airburst/budgie-mac/releases/latest")!
    /// How long to wait between automatic checks.
    public static let interval: TimeInterval = 24 * 60 * 60

    public struct Release: Equatable, Sendable {
        public let version: String
        /// The release page, with its notes.
        public let pageURL: URL
        /// The zip that `tools/release.ts` attaches, or the release page when it's missing.
        public let downloadURL: URL
        public let notes: String

        public init(version: String, pageURL: URL, downloadURL: URL, notes: String) {
            self.version = version
            self.pageURL = pageURL
            self.downloadURL = downloadURL
            self.notes = notes
        }
    }

    public enum Problem: Error, Equatable { case unreadable, noVersion }

    /// Reads GitHub's reply for one release.
    public static func release(from data: Data) throws(Problem) -> Release {
        struct Reply: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let body: String?
            let assets: [Asset]
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { throw .unreadable }
        let version = reply.tag_name.hasPrefix("v") ? String(reply.tag_name.dropFirst()) : reply.tag_name
        guard Version(version) != nil else { throw .noVersion }
        let zip = reply.assets.first { $0.name == "BudgieMac-\(version).zip" }
        return Release(version: version, pageURL: reply.html_url, downloadURL: zip?.browser_download_url ?? reply.html_url,
                       notes: reply.body ?? "")
    }

    /// True when the release is a later version than the one running.
    public static func isNewer(_ release: Release, than current: String) -> Bool {
        guard let latest = Version(release.version), let running = Version(current) else { return false }
        return latest > running
    }

    /// Automatic checks run at most once per interval.
    public static func isDue(lastChecked: Date?, now: Date = .now) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= interval || lastChecked > now
    }

    /// An automatic check notifies once per version; a check from the menu always answers.
    public static func shouldNotify(_ release: Release, current: String, alreadyNotified: String?) -> Bool {
        isNewer(release, than: current) && release.version != alreadyNotified
    }

    /// The release notes without the install instructions every release repeats.
    public static func summary(of notes: String) -> String {
        let trimmed = notes.components(separatedBy: "\n### Install").first ?? notes
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A major.minor.patch version; "1.0" reads as 1.0.0.
public struct Version: Comparable, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(pieces.count) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == pieces.count, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}
