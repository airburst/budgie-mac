import AppKit

/// S-058: BudgieMac > About shows the version, the build number, and a link to the changelog.
enum AboutPanel {
    static var changelog: URL? { Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") }

    static func show() {
        let credits = NSMutableAttributedString(string: "A native Mac version of Budgie. Your data stays on this Mac.\n\n",
                                                attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                             .foregroundColor: NSColor.secondaryLabelColor])
        if let changelog {
            credits.append(NSAttributedString(string: "What's New", attributes: [
                .link: changelog, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            ]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }

    static func openChangelog() {
        if let changelog { NSWorkspace.shared.open(changelog) }
    }
}
