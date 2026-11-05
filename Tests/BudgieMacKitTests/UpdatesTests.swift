import Foundation
import Testing
@testable import BudgieMacKit

/// Update checks against GitHub's latest release.
@Suite("Updates")
struct UpdatesTests {
    private func reply(tag: String, assets: [String] = [], body: String? = "Notes") -> Data {
        let list = assets.map { #"{"name": "\#($0)", "browser_download_url": "https://github.com/airburst/budgie-mac/releases/download/\#(tag)/\#($0)"}"# }
        let notes = body.map { #""\#($0)""# } ?? "null"
        return Data(#"""
        {"tag_name": "\#(tag)", "html_url": "https://github.com/airburst/budgie-mac/releases/tag/\#(tag)",
         "body": \#(notes), "draft": false, "assets": [\#(list.joined(separator: ","))]}
        """#.utf8)
    }

    @Test("The release's zip is the download, with the tag's v dropped")
    func readsRelease() throws {
        let release = try Updates.release(from: reply(tag: "v1.0.1", assets: ["BudgieMac-1.0.1.zip.sha256", "BudgieMac-1.0.1.zip"]))
        #expect(release.version == "1.0.1")
        #expect(release.downloadURL.absoluteString == "https://github.com/airburst/budgie-mac/releases/download/v1.0.1/BudgieMac-1.0.1.zip")
        #expect(release.pageURL.absoluteString == "https://github.com/airburst/budgie-mac/releases/tag/v1.0.1")
    }

    @Test("Without its zip, the download is the release page")
    func noZip() throws {
        let release = try Updates.release(from: reply(tag: "v1.2.0", body: nil))
        #expect(release.downloadURL == release.pageURL)
        #expect(release.notes == "")
    }

    @Test("A tag that isn't a version, or a reply that isn't a release, is refused")
    func refused() {
        #expect(throws: Updates.Problem.noVersion) { try Updates.release(from: reply(tag: "nightly")) }
        #expect(throws: Updates.Problem.unreadable) { try Updates.release(from: Data(#"{"message": "Not Found"}"#.utf8)) }
    }

    @Test("Versions compare by number, not by text", arguments: [
        ("1.0.10", "1.0.9", true), ("1.1.0", "1.0.99", true), ("2.0.0", "1.9.9", true),
        ("1.0.0", "1.0", false), ("1.0.0", "1.0.1", false), ("1.0.1", "1.0.1", false),
    ])
    func compares(latest: String, current: String, newer: Bool) throws {
        let release = try Updates.release(from: reply(tag: "v\(latest)"))
        #expect(Updates.isNewer(release, than: current) == newer)
    }

    @Test("Automatic checks wait a day between runs")
    func due() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Updates.isDue(lastChecked: nil, now: now))
        #expect(!Updates.isDue(lastChecked: now.addingTimeInterval(-3600), now: now))
        #expect(Updates.isDue(lastChecked: now.addingTimeInterval(-Updates.interval), now: now))
        #expect(Updates.isDue(lastChecked: now.addingTimeInterval(3600), now: now), "a clock moved back still checks")
    }

    @Test("A new version is announced once")
    func notifiesOnce() throws {
        let release = try Updates.release(from: reply(tag: "v1.0.2"))
        #expect(Updates.shouldNotify(release, current: "1.0.1", alreadyNotified: nil))
        #expect(Updates.shouldNotify(release, current: "1.0.1", alreadyNotified: "1.0.1"))
        #expect(!Updates.shouldNotify(release, current: "1.0.1", alreadyNotified: "1.0.2"))
        #expect(!Updates.shouldNotify(release, current: "1.0.2", alreadyNotified: nil))
    }

    @Test("The summary leaves out the install instructions")
    func summary() {
        #expect(Updates.summary(of: "- Faster\n\n### Install\n\nUnzip…") == "- Faster")
        #expect(Updates.summary(of: "  - Faster  \n") == "- Faster")
    }
}
