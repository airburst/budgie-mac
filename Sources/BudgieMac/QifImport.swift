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

    /// Adds the ticked rows to the account as you chose them, with one Undo.
    /// Learns what each bank text means from the duplicates' transactions
    /// (S-061) and from the rows you import, your changes counting more (S-062).
    func importQif(_ matches: [Qif.Match], choices: [Int: QifChoice] = [:], into account: Account, undoManager: UndoManager?) {
        let context = container.mainContext
        let book = ImportRuleBook(context: context)
        let existing = Dictionary(account.transactions.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        for match in matches {
            if let uuid = match.matched?.uuid, let transaction = existing[uuid] { book.learn(from: match.row, matched: transaction) }
        }
        var added: [Transaction] = []
        for match in matches where match.checked {
            let row = match.row
            let choice = choices[match.id]
            var draft = TransactionDraft(date: row.date)
            draft.payee = choice?.payee ?? row.payee
            draft.category = choice?.category
            draft.notes = row.memo ?? ""
            let text = abs(row.amount).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
            if row.amount < 0 { draft.withdrawal = text } else { draft.deposit = text }
            if let transaction = try? draft.add(to: account, in: context, locale: Locale(identifier: "en_US_POSIX")) {
                transaction.bankText = row.payee
                added.append(transaction)
                if match.matched == nil {
                    book.learn(imported: row, payee: transaction.payee, category: transaction.category, edited: choice?.edited ?? false)
                }
            }
        }
        try? context.save()
        sidebar = .account(account.uuid)
        undoManager?.registerUndo(withTarget: self) { model in model.delete(added, undoManager: nil) }
        undoManager?.setActionName("Import \(Words.count(added.count, "Transaction").capitalized)")
    }
}

/// What a QIF row will be imported as (S-062): filled from a rule, a payee,
/// or the transaction a duplicate matched, and changed by you.
struct QifChoice: Equatable {
    var payee: String
    var category: Category?
    var source: ImportRuleBook.Source?
    var confirmations = 0
    var edited = false

    /// Hover text for a filled row: where the payee and category came from.
    var help: String? {
        switch source {
        case .ruleForAmount, .rule: "Learned from your transactions, confirmed \(confirmations == 1 ? "once" : "\(confirmations.formatted()) times")"
        case .payeeName, .payeeWord, .nearPayee: "Matches your payee \(payee)"
        case nil: nil
        }
    }
}

/// S-055: tick the rows to import; duplicates and reconciled dates start unticked.
/// S-062: each row shows the payee and category it will get, and you can change them.
struct QifReviewSheet: View {
    let review: QifReview
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @Query(sort: \Payee.name) private var payees: [Payee]
    @State private var account: Account?
    @State private var matches: [Qif.Match] = []
    @State private var choices: [Int: QifChoice] = [:]

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
                    .width(min: 120, ideal: 250)
                TableColumn("Date") { (match: Qif.Match) in Text(Day.formatted(match.row.date)).monospacedDigit() }
                    .width(min: 80, ideal: 88, max: 120)
                TableColumn("Payee") { (match: Qif.Match) in payeeCell(match) }
                    .width(min: 140, ideal: 190)
                TableColumn("Category") { (match: Qif.Match) in categoryCell(match) }
                    .width(min: 120, ideal: 170)
                TableColumn("Withdrawal") { (match: Qif.Match) in AmountCell(amount: -match.row.amount, currency: currency) }
                    .width(min: 80, ideal: 96, max: 140)
                    .alignment(.trailing)
                TableColumn("Deposit") { (match: Qif.Match) in AmountCell(amount: match.row.amount, currency: currency) }
                    .width(min: 80, ideal: 96, max: 140)
                    .alignment(.trailing)
            }
        }
        .navigationTitle("Import QIF")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                let count = matches.filter(\.checked).count
                Button(count == 0 ? "Import" : "Import \(Words.count(count, "Transaction").capitalized)") {
                    if let account { model.importQif(matches, choices: choices, into: account, undoManager: undoManager) }
                    dismiss()
                }
                .disabled(account == nil || count == 0)
            }
        }
        .frame(width: 1080, height: 560)
        .onAppear {
            account = accounts.first { $0.uuid == review.account }
            rematch()
        }
    }

    private var currency: String { account?.currency ?? "GBP" }

    /// The payee to import as, with the bank text under it when they differ.
    private func payeeCell(_ match: Qif.Match) -> some View {
        let choice = choices[match.id]
        return HStack(spacing: Space.xs) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Payee", text: payee(match.id), prompt: Text(match.row.payee))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .textInputSuggestions {
                        ForEach(Suggestions.payees(payees, matching: choice?.payee ?? "").prefix(12)) { payee in
                            Text(payee.name).textInputCompletion(payee.name)
                        }
                    }
                if let choice, choice.payee.caseInsensitiveCompare(match.row.payee) != .orderedSame {
                    Text(match.row.payee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let help = choice?.help, choice?.edited == false {
                Spacer(minLength: 0)
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .help(help)
                    .accessibilityLabel(help)
            }
        }
        .disabled(!match.checked)
        .help("Bank text: \(match.row.payee)")
    }

    private func categoryCell(_ match: Qif.Match) -> some View {
        Picker("Category", selection: category(match.id)) {
            Text("None").tag(Category?.none)
            ForEach(Suggestions.categories(categories, matching: "")) { category in
                Text(category.path).tag(Category?.some(category))
            }
        }
        .labelsHidden()
        .disabled(!match.checked)
    }

    private func checked(_ id: Int) -> Binding<Bool> {
        Binding(get: { matches.first { $0.id == id }?.checked ?? false },
                set: { on in if let index = matches.firstIndex(where: { $0.id == id }) { matches[index].checked = on } })
    }

    /// Typing a payee marks the row as yours; naming a payee fills its category when there's none.
    private func payee(_ id: Int) -> Binding<String> {
        Binding(get: { choices[id]?.payee ?? "" },
                set: { name in
                    guard var choice = choices[id], choice.payee != name else { return }
                    choice.payee = name
                    choice.edited = true
                    if choice.category == nil, let payee = Suggestions.payee(named: name, in: payees), payee.name == name {
                        choice.category = payee.category
                    }
                    choices[id] = choice
                })
    }

    private func category(_ id: Int) -> Binding<Category?> {
        Binding(get: { choices[id]?.category },
                set: { category in
                    guard var choice = choices[id], choice.category?.persistentModelID != category?.persistentModelID else { return }
                    choice.category = category
                    choice.edited = true
                    choices[id] = choice
                })
    }

    private func rematch() {
        matches = Qif.match(review.rows, existing: account?.transactions ?? [], lastReconciled: account?.lastReconciled)
        choices = model.qifChoices(for: matches, in: account)
    }
}

extension AppModel {
    /// How each row starts in the review sheet: a duplicate as the transaction
    /// it matched, a new row as the rules or payees suggest, else its bank text.
    func qifChoices(for matches: [Qif.Match], in account: Account?) -> [Int: QifChoice] {
        let previews = ImportRuleBook.preview(matches, in: container)
        let byUUID = Dictionary((account?.transactions ?? []).map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let context = container.mainContext
        return Dictionary(uniqueKeysWithValues: matches.map { match in
            if let uuid = match.matched?.uuid, let transaction = byUUID[uuid] {
                return (match.id, QifChoice(payee: transaction.payee, category: transaction.category))
            }
            if let preview = previews[match.id] {
                let category = preview.categoryID.flatMap { context.model(for: $0) as? Category }
                return (match.id, QifChoice(payee: preview.payee, category: category, source: preview.source, confirmations: preview.confirmations))
            }
            return (match.id, QifChoice(payee: match.row.payee))
        })
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

/// S-064: Settings > Import Rules. What QIF imports have learned, one row per
/// bank text and payee; change a category or delete a rule, with Undo.
struct ImportRuleSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Query(sort: [SortDescriptor(\ImportRule.bankText), SortDescriptor(\ImportRule.count, order: .reverse)]) private var rules: [ImportRule]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @State private var search = ""

    var body: some View {
        if rules.isEmpty {
            Section {
                ContentUnavailableView("No Import Rules", systemImage: "tray.and.arrow.down",
                                       description: Text("When you import a QIF file, BudgieMac learns what each bank text means from the transactions you entered and the changes you make, and fills in the next import."))
                    .frame(maxWidth: .infinity)
            }
        } else {
            Section {
                TextField("Search", text: $search, prompt: Text("Bank text, payee or category"))
            } footer: {
                Text("Rules fill in the payee and category of imported QIF rows. A rule is used when most of what was learned for its bank text agrees.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let shown = rules.filter(matches)
            Section(Words.count(shown.count, "Rule")) {
                if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity)
                }
                ForEach(shown) { rule in
                    ImportRuleRow(rule: rule, categories: categories)
                }
            }
        }
    }

    private func matches(_ rule: ImportRule) -> Bool {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return true }
        return rule.bankText.localizedStandardContains(text) || rule.payee.localizedStandardContains(text)
            || (rule.category?.path.localizedStandardContains(text) ?? false)
    }
}

private struct ImportRuleRow: View {
    let rule: ImportRule
    let categories: [Category]
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.bankText).lineLimit(1).help(rule.bankText)
                Text("\(rule.payee) · \(rule.isDeposit ? "money in" : "money out") · \(confirmed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.sm)
            Picker("Category", selection: Binding(get: { rule.category?.softDeleted == true ? nil : rule.category },
                                                  set: { model.setCategory($0, of: rule, undoManager: undoManager) })) {
                Text("None").tag(Category?.none)
                ForEach(Suggestions.categories(categories, matching: "")) { Text($0.path).tag(Category?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Button("Delete Rule", systemImage: "minus.circle") { model.deleteImportRule(rule, undoManager: undoManager) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Delete this rule; the next import learns again")
        }
        .contextMenu {
            Button("Delete Rule") { model.deleteImportRule(rule, undoManager: undoManager) }
        }
    }

    private var confirmed: String {
        rule.count == 1 ? "confirmed once" : "confirmed \(rule.count.formatted()) times"
    }
}

extension AppModel {
    /// S-064: deletes a rule, with Undo bringing it back as it was.
    func deleteImportRule(_ rule: ImportRule, undoManager: UndoManager?) {
        let context = container.mainContext
        let saved = (uuid: rule.uuid, bankText: rule.bankText, isDeposit: rule.isDeposit, payee: rule.payee, category: rule.category,
                     count: rule.count, amountsText: rule.amountsText, lastUsed: rule.lastUsed, createdAt: rule.createdAt)
        context.delete(rule)
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { model in
            let back = ImportRule(bankText: saved.bankText, isDeposit: saved.isDeposit, payee: saved.payee, category: saved.category)
            back.uuid = saved.uuid
            back.count = saved.count
            back.amountsText = saved.amountsText
            back.lastUsed = saved.lastUsed
            back.createdAt = saved.createdAt
            context.insert(back)
            try? context.save()
        }
        undoManager?.setActionName("Delete Rule")
    }

    /// S-064: files a rule under another category, with Undo.
    func setCategory(_ category: Category?, of rule: ImportRule, undoManager: UndoManager?) {
        let before = rule.category
        guard before?.persistentModelID != category?.persistentModelID else { return }
        let context = container.mainContext
        rule.category = category
        try? context.save()
        undoManager?.registerUndo(withTarget: self) { model in model.setCategory(before, of: rule, undoManager: undoManager) }
        undoManager?.setActionName("Change Rule Category")
    }
}
