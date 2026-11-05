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
        #expect(!release.canInstall)
    }

    @Test("A release installs only with both its zip and its checksum")
    func installable() throws {
        #expect(try Updates.release(from: reply(tag: "v1.0.1", assets: ["BudgieMac-1.0.1.zip", "BudgieMac-1.0.1.zip.sha256"])).canInstall)
        #expect(try !Updates.release(from: reply(tag: "v1.0.1", assets: ["BudgieMac-1.0.1.zip"])).canInstall)
        #expect(try !Updates.release(from: reply(tag: "v1.0.1", assets: ["BudgieMac-1.0.1.zip.sha256"])).canInstall)
    }

    @Test("The download must match the checksum file")
    func checksum() throws {
        let hash = "73d8b88b650b2ac34d511a0f188c1c94a62995954c2e295de676d4b07de5bc96"
        try UpdateInstall.verifyChecksum(hash.uppercased(), against: "\(hash)  BudgieMac-1.0.1.zip\n")
        #expect(throws: UpdateInstall.Problem.checksumMismatch) {
            try UpdateInstall.verifyChecksum(String(repeating: "0", count: 64), against: "\(hash)  BudgieMac-1.0.1.zip")
        }
        #expect(throws: UpdateInstall.Problem.noChecksum) { try UpdateInstall.verifyChecksum(hash, against: "<html>Not Found</html>") }
    }

    @Test("The unzipped app must be BudgieMac at the release's version")
    func verifiesApp() throws {
        let id = "net.fairhursts.budgiemac"
        try UpdateInstall.verifyApp(info: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0.2"], bundleID: id, version: "1.0.2")
        #expect(throws: UpdateInstall.Problem.wrongApp("com.example.other")) {
            try UpdateInstall.verifyApp(info: ["CFBundleIdentifier": "com.example.other", "CFBundleShortVersionString": "1.0.2"], bundleID: id, version: "1.0.2")
        }
        #expect(throws: UpdateInstall.Problem.wrongVersion("1.0.1")) {
            try UpdateInstall.verifyApp(info: ["CFBundleIdentifier": id, "CFBundleShortVersionString": "1.0.1"], bundleID: id, version: "1.0.2")
        }
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
