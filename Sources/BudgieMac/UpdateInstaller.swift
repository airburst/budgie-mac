import AppKit
import BudgieMacKit
import CryptoKit

/// Install and Relaunch: downloads the release's zip, checks it, puts it in
/// place of the running app, and reopens. A file the app downloads itself is
/// not quarantined, so the new version opens without the "damaged" warning.
enum UpdateInstaller {
    /// Everything up to the swap. Cancelling the task stops the download.
    /// Returns the installed app, ready for `relaunch`.
    nonisolated static func install(_ release: Updates.Release, replacing current: URL) async throws -> URL {
        let folder = current.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            throw UpdateInstall.Problem.notWritable(folder.path)
        }
        guard let checksumURL = release.checksumURL else { throw UpdateInstall.Problem.noChecksum }
        // On the app's own volume, so the swap is a rename.
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: current, create: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let zip = work.appending(path: release.downloadURL.lastPathComponent)
        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        try check(response)
        try FileManager.default.moveItem(at: downloaded, to: zip)
        let (checksum, checksumResponse) = try await URLSession.shared.data(from: checksumURL)
        try check(checksumResponse)
        let digest = try SHA256.hash(data: Data(contentsOf: zip, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined()
        try UpdateInstall.verifyChecksum(digest, against: String(decoding: checksum, as: UTF8.self))
        try Task.checkCancellation()

        let unzipped = work.appending(path: "unzipped", directoryHint: .isDirectory)
        try await run("/usr/bin/ditto", "-x", "-k", zip.path, unzipped.path)
        let app = unzipped.appending(path: "BudgieMac.app", directoryHint: .isDirectory)
        guard let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any] else {
            throw UpdateInstall.Problem.noApp
        }
        try UpdateInstall.verifyApp(info: info, bundleID: Bundle.main.bundleIdentifier, version: release.version)
        try await run("/usr/bin/codesign", "--verify", "--deep", "--strict", app.path)
        try Task.checkCancellation()

        // One step: the old app is gone and the new one is in its place, or nothing changed.
        let installed = try FileManager.default.replaceItemAt(current, withItemAt: app) ?? current
        return installed
    }

    /// Quits (which takes the usual backup) and opens the new copy once this process has gone.
    /// A test run's store goes along, so the new copy never opens the real data.
    static func relaunch(_ app: URL) {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        let store = ProcessInfo.processInfo.environment["APP_STORE"].map { ["--env", "APP_STORE=\($0)"] } ?? []
        relauncher.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$@\"",
                                "relaunch"] + store + [app.path]
        try? relauncher.run()
        NSApp.terminate(nil)
    }

    private enum Failure: LocalizedError {
        case server(Int), tool(String)
        var errorDescription: String? {
            switch self {
            case .server(let code): "GitHub answered with error \(code)."
            case .tool(let name): "\(name) couldn't read the download."
            }
        }
    }

    nonisolated private static func check(_ response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.server(status) }
    }

    nonisolated private static func run(_ tool: String, _ arguments: String...) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw Failure.tool(URL(fileURLWithPath: tool).lastPathComponent) }
    }
}
