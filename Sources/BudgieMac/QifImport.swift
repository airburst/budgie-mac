import AppKit
import BudgieMacKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// A QIF file read and waiting for review (S-055).
struct QifReview: Identifiable {
    let id = UUID()
    let fileName: String
    let kind: Qif.Kind
    let rows: [Qif.Row]
    var account: UUID?
}

extension UTType {
    static let qif = UTType(filenameExtension: "qif") ?? .plainText
}

extension AppModel {
    /// File > Import QIF…
    func chooseQifFile() {
        guard let window = NSApp.mainAppWindow else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.qif]
        panel.message = "Choose a QIF file exported by your bank."
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url { self.openQif(url) }
        }
    }

    /// Reads the file and opens the review sheet, for the open account if there is one.
    func openQif(_ url: URL, account: UUID? = nil) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let (kind, rows) = try Qif.parse(text)
            qifReview = QifReview(fileName: url.lastPathComponent, kind: kind, rows: rows, account: account ?? openAccount)
        } catch {
            guard let window = NSApp.mainAppWindow else { return }
            let alert = NSAlert()
            alert.messageText = "Unable to import “\(url.lastPathComponent)”"
            alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            alert.beginSheetModal(for: window)
        }
    }

    /// Adds the ticked rows to the account, with one Undo.
    func importQif(_ rows: [Qif.Row], into account: Account, undoManager: UndoManager?) {
        let context = container.mainContext
        var added: [Transaction] = []
        for row in rows {
            var draft = TransactionDraft(date: row.date)
            draft.payee = row.payee
            draft.notes = row.memo ?? ""
            let text = abs(row.amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            if row.amount < 0 { draft.withdrawal = text } else { draft.deposit = text }
            if let transaction = try? draft.add(to: account, in: context, locale: Locale(identifier: "en_US_POSIX")) { added.append(transaction) }
        }
        try? context.save()
        sidebar = .account(account.uuid)
        undoManager?.registerUndo(withTarget: self) { model in model.delete(added, undoManager: nil) }
        undoManager?.setActionName("Import \(Words.count(added.count, "Transaction").capitalized)")
    }
}

/// S-055: tick the rows to import; duplicates and reconciled dates start unticked.
struct QifReviewSheet: View {
    let review: QifReview
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @State private var account: Account?
    @State private var matches: [Qif.Match] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Account", selection: $account) {
                    Text("Choose…").tag(Account?.none)
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }
                .onChange(of: account) { _, _ in rematch() }
                LabeledContent("File", value: "\(review.fileName) · \(review.kind == .creditCard ? "Credit card" : "Bank") · \(Words.count(review.rows.count, "row"))")
            }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
            Table(matches) {
                TableColumn("") { (match: Qif.Match) in
                    Toggle("Import", isOn: checked(match.id)).labelsHidden().toggleStyle(.checkbox)
                        .disabled(match.status == .reconciled)
                }
                .width(24)
                TableColumn("Status") { (match: Qif.Match) in StatusBadge(match: match, currency: currency) }
                    .width(min: 120, ideal: 240)
                TableColumn("Date") { (match: Qif.Match) in Text(Day.formatted(match.row.date)).monospacedDigit() }
                    .width(min: 80, ideal: 96, max: 120)
                TableColumn("Payee") { (match: Qif.Match) in Text(match.row.payee).lineLimit(1).help(match.row.payee) }
                    .width(min: 120, ideal: 170)
                TableColumn("Withdrawal") { (match: Qif.Match) in AmountCell(amount: -match.row.amount, currency: currency) }
                    .width(min: 80, ideal: 100, max: 140)
                    .alignment(.trailing)
                TableColumn("Deposit") { (match: Qif.Match) in AmountCell(amount: match.row.amount, currency: currency) }
                    .width(min: 80, ideal: 100, max: 140)
                    .alignment(.trailing)
            }
        }
        .navigationTitle("Import QIF")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                let count = matches.filter(\.checked).count
                Button(count == 0 ? "Import" : "Import \(Words.count(count, "Transaction").capitalized)") {
                    if let account { model.importQif(matches.filter(\.checked).map(\.row), into: account, undoManager: undoManager) }
                    dismiss()
                }
                .disabled(account == nil || count == 0)
            }
        }
        .frame(width: 880, height: 520)
        .onAppear {
            account = accounts.first { $0.uuid == review.account }
            rematch()
        }
    }

    private var currency: String { account?.currency ?? "GBP" }

    private func checked(_ id: Int) -> Binding<Bool> {
        Binding(get: { matches.first { $0.id == id }?.checked ?? false },
                set: { on in if let index = matches.firstIndex(where: { $0.id == id }) { matches[index].checked = on } })
    }

    private func rematch() {
        guard let account else {
            matches = Qif.match(review.rows, existing: [], lastReconciled: nil)
            return
        }
        matches = Qif.match(review.rows, existing: account.transactions, lastReconciled: account.lastReconciled)
    }
}

/// New, Before Last Reconcile, or "Duplicate of Coop, 4 Nov" (S-060).
private struct StatusBadge: View {
    let match: Qif.Match
    let currency: String

    var body: some View {
        Label(text, systemImage: match.status == .new ? "plus.circle" : match.status == .duplicate ? "doc.on.doc" : "lock")
            .foregroundStyle(match.status == .new ? .primary : .secondary)
            .lineLimit(1)
            .help(help)
    }

    private var text: String {
        guard let matched = match.matched else { return match.status.rawValue }
        let day = matched.date.formatted(Date.FormatStyle(timeZone: Day.calendar.timeZone).day().month(.abbreviated))
        return "Duplicate of \(matched.payee), \(day)"
    }

    private var help: String {
        guard let matched = match.matched else { return match.status == .reconciled ? "On or before this account's last reconcile" : "Not in this account yet" }
        return "Already in this account: \(matched.payee), \(Day.formatted(matched.date, .long)), \(Money.string(matched.amount, currency: currency))"
    }
}

/// Shows the amount only when it's positive (the other column has it otherwise).
private struct AmountCell: View {
    let amount: Decimal
    let currency: String

    var body: some View {
        if amount > 0 { Text(Money.string(amount, currency: currency)).monospacedDigit() }
    }
}
