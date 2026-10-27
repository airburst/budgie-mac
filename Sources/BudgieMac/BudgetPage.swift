import BudgieMacKit
import SwiftData
import SwiftUI

/// S-036: this month's budget; S-040 inline assigning; S-043 reordering.
struct BudgetPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    // Watched so the summary recomputes when any of them change.
    @Query(sort: \Envelope.sortOrder) private var envelopes: [Envelope]
    @Query private var allocations: [BudgetAllocation]
    @Query private var transfers: [BudgetTransfer]
    @Query private var transactions: [Transaction]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]

    private let currency = Locale.current.currency?.identifier ?? "GBP"

    var body: some View {
        let month = model.budgetMonth
        let summary = Budget.summary(for: month, envelopes: envelopes, allocations: allocations,
                                     transfers: transfers, transactions: transactions)
        Group {
            if envelopes.allSatisfy({ !$0.active }) {
                BudgetTemplates(categories: categories)
            } else {
                VStack(spacing: 0) {
                    AvailableCard(amount: summary.availableToBudget, overspent: summary.overspentBefore, currency: currency)
                        .padding(Space.margin)
                    EnvelopeHeader()
                        .padding(.horizontal, Space.margin)
                    List {
                        ForEach(summary.lines) { line in
                            EnvelopeRow(line: line, month: month, currency: currency)
                                .contextMenu { menu(for: line.envelope, in: summary.lines) }
                        }
                        .onMove { from, to in
                            var order = summary.lines.map(\.envelope)
                            order.move(fromOffsets: from, toOffset: to)
                            model.reorder(order, undoManager: undoManager)
                        }
                    }
                }
            }
        }
        .navigationTitle("Budget")
        .navigationSubtitle(Budget.title(of: month))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Previous Month", systemImage: "chevron.left") { model.budgetMonth = Budget.month(month, adding: -1) }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Previous month (⌘[)")
                Button("Next Month", systemImage: "chevron.right") { model.budgetMonth = Budget.month(month, adding: 1) }
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Next month (⌘])")
            }
            ToolbarItemGroup {
                Button("Move Money…", systemImage: "arrow.left.arrow.right") { model.movingMoney = true }
                    .disabled(summary.lines.count < 2)
                    .help("Move money between envelopes for \(Budget.title(of: month))")
                Button("Copy Last Month…", systemImage: "doc.on.doc") { model.copyLastMonth(into: month, envelopes: envelopes) }
                    .disabled(summary.lines.isEmpty)
                    .help("Fill this month's empty envelopes with last month's amounts")
                Button("Add Envelope", systemImage: "plus") { model.envelopeSheet = .add }
                    .help("Add an envelope")
            }
        }
        .sheet(item: Bindable(model).envelopeSheet) { mode in
            NavigationStack { EnvelopeSheet(mode: mode) }
        }
        .sheet(isPresented: Bindable(model).movingMoney) {
            NavigationStack { MoveMoneySheet(envelopes: summary.lines.map(\.envelope), month: month) }
        }
    }

    @ViewBuilder private func menu(for envelope: Envelope, in lines: [Budget.Line]) -> some View {
        let order = lines.map(\.envelope)
        let index = order.firstIndex { $0 === envelope } ?? 0
        Button("Edit Envelope…") { model.envelopeSheet = .edit(envelope.persistentModelID) }
        Divider()
        Button("Move Up") {
            var moved = order
            moved.swapAt(index, index - 1)
            model.reorder(moved, undoManager: undoManager)
        }
        .disabled(index == 0)
        Button("Move Down") {
            var moved = order
            moved.swapAt(index, index + 1)
            model.reorder(moved, undoManager: undoManager)
        }
        .disabled(index == order.count - 1)
        Divider()
        Button("Delete…", role: .destructive) { model.deleteEnvelope(envelope) }
    }
}

/// Column headings, sized like EnvelopeRow.
private struct EnvelopeHeader: View {
    var body: some View {
        HStack(spacing: Space.lg) {
            Text("Envelope").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("Assigned").frame(width: 100, alignment: .trailing)
            Text("Spent of Available").frame(minWidth: 120, alignment: .leading)
            Text("Spent").frame(width: 100, alignment: .trailing)
            Text("Available").frame(width: 112, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Space.sm)
    }
}

private struct AvailableCard: View {
    let amount: Decimal
    let overspent: Decimal
    let currency: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Available to Budget").font(.headline)
                MoneyText(amount: amount, currency: currency).font(.title.weight(.semibold))
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.sm)
        }
    }

    private var note: String {
        var parts = [amount < 0 ? "Over-assigned: more is assigned than you have received."
                     : amount == 0 ? "Every pound has a job." : "Money received that isn't assigned to an envelope yet."]
        if overspent > 0 { parts.append("Includes \(Money.string(overspent, currency: currency)) overspent in earlier months.") }
        return parts.joined(separator: " ")
    }
}

private struct EnvelopeRow: View {
    let line: Budget.Line
    let month: String
    let currency: String
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.envelope.name).font(.body.weight(.medium))
                Text(line.envelope.categories.compactMap { $0.category?.name }.sorted().joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            TextField("Assigned", text: $text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 100)
                .focused($editing)
                .onSubmit(save)
                .onExitCommand { reset(); editing = false }
                .onChange(of: editing) { _, now in if !now { save() } }
                .help("Assigned for \(Budget.title(of: month)). Return saves, Escape cancels, Tab moves on.")
                .accessibilityLabel("Assigned to \(line.envelope.name)")
            ProgressView(value: line.spentShare)
                .frame(maxWidth: .infinity)
                .tint(line.available < 0 ? Palette.moneyOut : Palette.accent)
                .frame(minWidth: 120)
                .accessibilityLabel("Spent \(Int(line.spentShare * 100)) percent of the money available")
            Text(Money.string(max(0, -line.activity), currency: currency))
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
                .help("Spent in \(Budget.title(of: month))")
            MoneyText(amount: line.available, currency: currency)
                .fontWeight(.semibold)
                .frame(width: 112, alignment: .trailing)
                .help("Available: rolled over \(Money.string(line.rolledOver, currency: currency)), moved in \(Money.string(line.movedIn, currency: currency)), moved out \(Money.string(line.movedOut, currency: currency))")
        }
        .padding(.vertical, Space.xs)
        .onAppear(perform: reset)
        .onChange(of: line.assigned) { _, _ in if !editing { reset() } }
        .onChange(of: month) { _, _ in reset() }
    }

    private func reset() {
        text = line.assigned.formatted(.number.precision(.fractionLength(2)))
    }

    private func save() {
        guard let amount = Money.parse(text), amount != line.assigned else { reset(); return }
        model.assign(amount, to: line.envelope, in: month, undoManager: undoManager)
    }
}

/// S-037: no envelopes yet.
private struct BudgetTemplates: View {
    let categories: [Category]
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xxl) {
                VStack(spacing: Space.sm) {
                    Text("Start Budgeting").font(.title2.weight(.semibold))
                    Text("Give every pound a job: put money into envelopes each month, and aim for Available to Budget to reach £0.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    ForEach(Envelopes.templates) { template in
                        GroupBox {
                            VStack(alignment: .leading, spacing: Space.sm) {
                                Text(template.name).font(.headline)
                                Text(template.description).font(.callout).foregroundStyle(.secondary)
                                Divider()
                                ForEach(template.envelopes, id: \.name) { Label($0.name, systemImage: "envelope") }
                                Spacer(minLength: Space.sm)
                                Button("Use \(template.name)") { model.applyTemplate(template, categories: categories) }
                                    .frame(maxWidth: .infinity)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(Space.sm)
                        }
                        .frame(width: 220)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Button("Start from Scratch…") { model.envelopeSheet = .add }
            }
            .padding(Space.section)
            .frame(maxWidth: .infinity)
        }
    }
}
