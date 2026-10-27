import AppKit
import BudgieMacKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// S-002: File > Import Budgie Data… -> open panel -> confirmation when
/// BudgieMac already has data -> replace everything -> banner on All Accounts.
@Observable
final class ImportFlow {
    struct Pending {
        var fileName: String
        var package: BudgieImport.Package
        /// What BudgieMac holds now, for the confirmation message.
        var accounts: Int
        var transactions: Int
    }

    struct Failure {
        var fileName: String
        var message: String
    }

    var isChoosingFile = false
    var failure: Failure?
    /// "Imported 7 accounts and 1,234 transactions from Budgie."
    var banner: String?

    func chooseFile() { isChoosingFile = true }

    /// Reads and checks the file. Replaces at once when BudgieMac is empty,
    /// otherwise asks first.
    func open(_ url: URL, into model: AppModel) {
        let fileName = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let package = try BudgieImport.read(Data(contentsOf: url))
            let context = model.container.mainContext
            let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
            let transactions = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
            let request = Pending(fileName: fileName, package: package, accounts: accounts, transactions: transactions)
            if accounts == 0 && transactions == 0 {
                replace(with: request, in: model)
            } else {
                confirm(request, in: model)
            }
        } catch let error as BudgieImport.Failure {
            failure = Failure(fileName: fileName, message: error.errorDescription ?? "")
        } catch {
            failure = Failure(fileName: fileName, message: error.localizedDescription)
        }
    }

    /// Asks before replacing, with Cancel as the default (UI/Confirm.swift).
    func confirm(_ request: Pending, in model: AppModel) {
        Confirm.destructive("Replace All Data with This Budgie File?",
                            message: "Your \(Self.count(request.accounts, "account")) and \(Self.count(request.transactions, "transaction")) in BudgieMac will be replaced. This can't be undone. Export your data first if you want a copy.",
                            button: "Replace All Data") { self.replace(with: request, in: model) }
    }

    func replace(with request: Pending, in model: AppModel) {
        do {
            let summary = try BudgieImport.replaceAll(in: model.container.mainContext, with: request.package)
            model.sidebar = .page(.accounts)
            let text = "Imported \(Self.count(summary.accounts, "account")) and \(Self.count(summary.transactions, "transaction")) from Budgie."
            banner = text
            AccessibilityNotification.Announcement(text).post()
        } catch {
            failure = Failure(fileName: request.fileName, message: error.localizedDescription)
        }
    }

    /// "1 account", "1,234 transactions".
    static func count(_ number: Int, _ noun: String) -> String {
        "\(number.formatted()) \(noun)\(number == 1 ? "" : "s")"
    }
}

/// The open panel, confirmation, and error alert, attached to the main window.
struct ImportFlowModifier: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        @Bindable var flow = model.importFlow
        content
            .fileImporter(isPresented: $flow.isChoosingFile, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { flow.open(url, into: model) }
            }
            .alert("Unable to import “\(flow.failure?.fileName ?? "")”",
                   isPresented: Binding(get: { flow.failure != nil }, set: { if !$0 { flow.failure = nil } }),
                   presenting: flow.failure) { _ in
                Button("OK") { flow.failure = nil }
            } message: { failure in
                Text(failure.message)
            }
    }
}

/// The inline banner at the top of All Accounts after an import.
struct ImportBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        GroupBox {
            HStack(spacing: Space.sm) {
                Label(text, systemImage: "checkmark.circle.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer(minLength: Space.sm)
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Close")
            }
            .padding(Space.xs)
        }
        .padding(.horizontal, Space.md)
        .padding(.top, Space.sm)
    }
}
