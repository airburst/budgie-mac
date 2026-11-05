import AppKit
import BudgieMacKit
import UserNotifications

/// Checks GitHub for a newer release: quietly once a day, with a notification
/// that has a Download button, or from BudgieMac > Check for Updates…, which
/// always answers in an alert. The settings belong to this Mac, so they live in
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
        let download = UNNotificationAction(identifier: Self.downloadAction, title: "Download")
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [download], intentIdentifiers: [])])
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
        content.body = "You have \(current). Click to see what's new, or download it now."
        content.categoryIdentifier = Self.category
        content.userInfo = ["page": release.pageURL.absoluteString, "download": release.downloadURL.absoluteString]
        try? await center.add(UNNotificationRequest(identifier: "update-\(release.version)", content: content, trigger: nil))
    }

    private func showAlert(for release: Updates.Release, current: String) {
        let alert = NSAlert()
        if Updates.isNewer(release, than: current) {
            alert.messageText = "BudgieMac \(release.version) is available"
            let summary = Updates.summary(of: release.notes)
            let notes = summary.count > 600 ? summary.prefix(600) + "…" : summary
            alert.informativeText = "You have \(current)." + (notes.isEmpty ? "" : "\n\n\(notes)")
            alert.addButton(withTitle: "Download")
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
            case .alertFirstButtonReturn: NSWorkspace.shared.open(release.downloadURL)
            case .alertSecondButtonReturn: NSWorkspace.shared.open(release.pageURL)
            default: break
            }
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

    /// Download opens the zip; clicking the notification opens the release page.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.content.categoryIdentifier == Self.category,
              response.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let key = response.actionIdentifier == Self.downloadAction ? "download" : "page"
        guard let text = response.notification.request.content.userInfo[key] as? String, let url = URL(string: text) else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
