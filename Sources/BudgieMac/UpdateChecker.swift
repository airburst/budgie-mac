import AppKit
import BudgieMacKit
import UserNotifications

/// Checks GitHub for a newer release: quietly once a day, with a notification
/// that offers Install and Relaunch (or Download, for a release without a
/// checksum), or from BudgieMac > Check for Updates…, which always answers in an alert. The settings belong to this Mac, so they live in
/// UserDefaults, not in the budget data.
@Observable
final class UpdateChecker: NSObject {
    static let shared = UpdateChecker()

    private enum Key {
        static let automatic = "updates.automatic"
        static let lastChecked = "updates.lastChecked"
        static let notified = "updates.notifiedVersion"
    }
    nonisolated private static let category = "update"
    nonisolated private static let downloadCategory = "update.download"
    nonisolated private static let installAction = "install"
    nonisolated private static let downloadAction = "download"

    var automatic = UserDefaults.standard.object(forKey: Key.automatic) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automatic, forKey: Key.automatic)
            checkIfDue()
        }
    }
    private(set) var lastChecked = UserDefaults.standard.object(forKey: Key.lastChecked) as? Date {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(lastChecked, forKey: Key.lastChecked) } }
    }
    private var notified = UserDefaults.standard.string(forKey: Key.notified) {
        didSet { if !Store.isOverridden { UserDefaults.standard.set(notified, forKey: Key.notified) } }
    }
    private(set) var checking = false
    private var installing: Task<Void, Never>?

    /// The running version. APP_PRETEND_VERSION=0.1.0 tries the update path.
    static var currentVersion: String {
        ProcessInfo.processInfo.environment["APP_PRETEND_VERSION"]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Test, snapshot and self-test runs never check on their own.
    private var checksAutomatically: Bool { automatic && !Store.isOverridden }

    /// Before launch finishes, so a click on a notification that opened the app arrives here.
    func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let install = UNNotificationAction(identifier: Self.installAction, title: "Install and Relaunch", options: .foreground)
        let download = UNNotificationAction(identifier: Self.downloadAction, title: "Download")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [install], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.downloadCategory, actions: [download], intentIdentifiers: []),
        ])
    }

    /// At launch, then whenever the app comes forward and a day has passed.
    func start() {
        checkIfDue()
        Task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                checkIfDue()
            }
        }
    }

    func checkIfDue() {
        guard checksAutomatically, !checking, Updates.isDue(lastChecked: lastChecked) else { return }
        Task { await check(fromMenu: false) }
    }

    /// BudgieMac > Check for Updates…
    func checkNow() {
        Task { await check(fromMenu: true) }
    }

    private func check(fromMenu: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let current = Self.currentVersion
        do {
            let release = try await fetchLatest()
            lastChecked = .now
            if fromMenu {
                if Updates.isNewer(release, than: current) { notified = release.version }
                showAlert(for: release, current: current)
            } else if Updates.shouldNotify(release, current: current, alreadyNotified: notified) {
                notified = release.version
                await announce(release, current: current)
            }
        } catch {
            // An automatic check stays quiet and tries again next time.
            if fromMenu { showProblem(error) }
        }
    }

    private enum CheckProblem: LocalizedError {
        case noReleases, server(Int)
        var errorDescription: String? {
            switch self {
            case .noReleases: "No versions have been published yet."
            case .server(let code): "GitHub answered with error \(code). Try again later."
            }
        }
    }

    private func fetchLatest() async throws -> Updates.Release {
        var request = URLRequest(url: Updates.latestURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BudgieMac/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw CheckProblem.noReleases }
        guard status == 200 else { throw CheckProblem.server(status) }
        return try Updates.release(from: data)
    }

    /// A notification when they're allowed, otherwise the same alert as the menu.
    private func announce(_ release: Updates.Release, current: String) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert])) == true else {
            showAlert(for: release, current: current)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "BudgieMac \(release.version) is available"
        content.body = "You have \(current). Click to see what's new, or \(release.canInstall ? "install it now" : "download it now")."
        content.categoryIdentifier = release.canInstall ? Self.category : Self.downloadCategory
        content.userInfo = ["version": release.version, "page": release.pageURL.absoluteString,
                            "download": release.downloadURL.absoluteString, "checksum": release.checksumURL?.absoluteString ?? ""]
        try? await center.add(UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil))
    }

    private func showAlert(for release: Updates.Release, current: String) {
        let alert = NSAlert()
        if Updates.isNewer(release, than: current) {
            alert.messageText = "BudgieMac \(release.version) is available"
            let summary = Updates.summary(of: release.notes)
            let notes = summary.count > 600 ? summary.prefix(600) + "…" : summary
            alert.informativeText = "You have \(current)." + (notes.isEmpty ? "" : "\n\n\(notes)")
            alert.addButton(withTitle: release.canInstall ? "Install and Relaunch" : "Download")
            alert.addButton(withTitle: "Release Notes")
            alert.addButton(withTitle: "Later").keyEquivalent = "\u{1b}"
        } else {
            alert.messageText = "BudgieMac is up to date"
            alert.informativeText = release.version == current
                ? "Version \(current) is the latest."
                : "You have \(current). The latest published version is \(release.version)."
            alert.addButton(withTitle: "OK")
        }
        present(alert) { response in
            guard Updates.isNewer(release, than: current) else { return }
            switch response {
            case .alertFirstButtonReturn: self.installOrDownload(release)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(release.pageURL)
            default: break
            }
        }
    }

    /// Install and Relaunch, behind a sheet with Cancel. Any failure offers the download instead.
    func installOrDownload(_ release: Updates.Release) {
        guard release.canInstall else {
            NSWorkspace.shared.open(release.downloadURL)
            return
        }
        guard installing == nil else { return }
        let progress = NSAlert()
        progress.messageText = "Installing BudgieMac \(release.version)…"
        progress.informativeText = "BudgieMac reopens when it's done. It backs up your data as it quits, as always."
        let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 240, height: 16))
        bar.style = .bar
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        progress.accessoryView = bar
        progress.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        let window = NSApp.mainAppWindow
        let task = Task {
            do {
                let installed = try await UpdateInstaller.install(release, replacing: Bundle.main.bundleURL)
                if let window, let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .OK) }
                UpdateInstaller.relaunch(installed)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                if let window, let sheet = window.attachedSheet { window.endSheet(sheet, returnCode: .OK) }
                installing = nil
                showInstallProblem(error, release: release)
            }
        }
        installing = task
        NSApp.activate()
        if let window {
            progress.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    task.cancel()
                    self.installing = nil
                }
            }
        }
    }

    private func showInstallProblem(_ error: Error, release: Updates.Release) {
        let alert = NSAlert()
        alert.messageText = "Couldn't install BudgieMac \(release.version)"
        alert.informativeText = "\(error.localizedDescription)\n\nYou can download it and install it yourself instead."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        present(alert) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(release.downloadURL) }
        }
    }

    private func showProblem(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        present(alert) { _ in }
    }

    private func present(_ alert: NSAlert, then handle: @escaping (NSApplication.ModalResponse) -> Void) {
        NSApp.activate()
        if let window = NSApp.mainAppWindow {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}

extension UpdateChecker: UNUserNotificationCenterDelegate {
    /// Shows the banner even when BudgieMac is in front, as it is at launch.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Install and Relaunch installs, Download opens the zip, and clicking the
    /// notification opens the release page.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard [Self.category, Self.downloadCategory].contains(content.categoryIdentifier),
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let url = { (key: String) in (content.userInfo[key] as? String).flatMap(URL.init(string:)) }
        guard let version = content.userInfo["version"] as? String, let page = url("page"), let download = url("download") else { return }
        let release = Updates.Release(version: version, pageURL: page, downloadURL: download, checksumURL: url("checksum"), notes: "")
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Self.installAction: self.installOrDownload(release)
            case Self.downloadAction: NSWorkspace.shared.open(release.downloadURL)
            default: NSWorkspace.shared.open(release.pageURL)
            }
        }
    }
}
