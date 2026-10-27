import AppKit

/// A destructive confirmation as a sheet on the main window: Cancel first and
/// the default (Return), the destructive button second. A SwiftUI alert would
/// make the destructive button the default, so this is an NSAlert.
enum Confirm {
    static func destructive(_ title: String, message: String, button: String, perform: @escaping () -> Void) {
        guard let window = NSApp.mainAppWindow else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let destroy = alert.addButton(withTitle: button)
        destroy.hasDestructiveAction = true
        destroy.keyEquivalent = ""
        alert.beginSheetModal(for: window) { response in
            if response == .alertSecondButtonReturn { perform() }
        }
    }
}
