import BudgieMacKit
import SwiftData
import SwiftUI

/// S-025: every scheduled transaction, with a due-date calendar and the next
/// 7 days' summary (S-032), sorted and filtered (S-031).
struct ScheduledPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Query private var schedules: [ScheduledTransaction]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @State private var view = ScheduleView(defaults: .standard)
    @State private var selection = Set<ScheduledTransaction.ID>()
    @State private var month = Day.today

    var body: some View {
        let shown = view.apply(schedules)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.lg) {
                DueCalendar(month: $month, schedules: shown) { day in
                    selection = Set(shown.filter { $0.active && $0.nextDueDate == day }.map(\.id))
                }
                DueSoonCard(summary: Scheduling.dueSoon(shown))
                Spacer()
            }
            .frame(width: 240)
            .padding(Space.lg)
            Divider()
            if schedules.isEmpty {
                ContentUnavailableView {
                    Label("No Scheduled Transactions", systemImage: "calendar")
                } description: {
                    Text("Add rent, salary and other repeating transactions to see what's coming and record them in one click.")
                } actions: {
                    Button("Add Scheduled Transaction…") { model.scheduleSheet = .add }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                table(shown)
            }
        }
        .navigationTitle("Scheduled")
        .toolbar { toolbar }
        .sheet(item: Bindable(model).scheduleSheet) { mode in
            NavigationStack { ScheduleSheet(mode: mode) }
        }
        .onChange(of: view) { _, new in new.save(to: .standard) }
    }

    private func table(_ shown: [ScheduledTransaction]) -> some View {
        Table(shown, selection: $selection) {
            TableColumn("Due") { schedule in
                Text(schedule.nextDueDate.map { Day.formatted($0) } ?? "—").monospacedDigit()
                    .foregroundStyle(schedule.active ? .primary : .secondary)
            }
            .width(min: 76, ideal: 84)
            TableColumn("Payee") { schedule in
                Text(schedule.payee).lineLimit(1)
                    .foregroundStyle(schedule.active ? .primary : .secondary)
            }
            .width(min: 110, ideal: 150)
            TableColumn("Amount") { schedule in
                MoneyText(amount: schedule.amount, currency: schedule.account?.currency ?? "GBP")
                    .opacity(schedule.active ? 1 : 0.6)
            }
            .width(min: 80, ideal: 96)
            .alignment(.trailing)
            TableColumn("Frequency") { schedule in
                if schedule.active {
                    Text(schedule.frequencyLabel).lineLimit(1)
                } else {
                    Label("Paused · \(schedule.frequencyLabel)", systemImage: "pause.circle")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                        .help("Paused: left out of the forecast, automatic recording and the 7-day summary")
                }
            }
                .width(min: 80, ideal: 130)
            TableColumn("Account") { schedule in
                Text(schedule.transferToAccount.map { "\(schedule.account?.name ?? "") → \($0.name)" } ?? schedule.account?.name ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
        }
        .contextMenu(forSelectionType: ScheduledTransaction.ID.self) { ids in
            if let schedule = schedules.first(where: { ids.contains($0.id) }) {
                Button("Record…") { model.transactionSheet = .record(schedule.persistentModelID) }
                    .disabled(schedule.nextDueDate == nil)
                Button("Skip…") { model.skip(schedule) }
                    .disabled(schedule.nextDueDate == nil)
                Divider()
                Button("Edit…") { model.scheduleSheet = .edit(schedule.persistentModelID) }
                Button(schedule.active ? "Pause" : "Resume") { model.setActive(schedule, !schedule.active, undoManager: undoManager) }
                Divider()
                Button("Delete…", role: .destructive) { model.deleteSchedule(schedule) }
            }
        } primaryAction: { ids in
            if let schedule = schedules.first(where: { ids.contains($0.id) }) { model.scheduleSheet = .edit(schedule.persistentModelID) }
        }
        .onDeleteCommand {
            if let schedule = schedules.first(where: { selection.contains($0.id) }) { model.deleteSchedule(schedule) }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Menu("Accounts", systemImage: view.accounts.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                Button("All Accounts") { view.accounts = [] }
                Divider()
                ForEach(accounts) { account in
                    Toggle(account.name, isOn: Binding(
                        get: { view.accounts.contains(account.uuid) },
                        set: { on in if on { view.accounts.insert(account.uuid) } else { view.accounts.remove(account.uuid) } }))
                }
            }
            .help(view.accounts.isEmpty ? "Showing all accounts" : "Showing \(Words.count(view.accounts.count, "account"))")
            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort By", selection: $view.sort) {
                    ForEach(ScheduleSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            }
            .help("Sort by \(view.sort.title.lowercased())")
        }
        ToolbarItem {
            Button("Add Scheduled Transaction", systemImage: "plus") { model.scheduleSheet = .add }
                .help("Add a scheduled transaction")
        }
    }
}

/// A month with a dot on each day something is next due. Clicking a day selects its schedules.
private struct DueCalendar: View {
    @Binding var month: Date
    let schedules: [ScheduledTransaction]
    let select: (Date) -> Void

    var body: some View {
        let calendar = Day.calendar
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let length = calendar.range(of: .day, in: .month, for: first)!.count
        let lead = (calendar.component(.weekday, from: first) + 5) % 7
        let due = Set(schedules.filter(\.active).compactMap(\.nextDueDate))
        GroupBox {
            VStack(spacing: Space.sm) {
                HStack {
                    Button("Previous Month", systemImage: "chevron.left") { month = calendar.date(byAdding: .month, value: -1, to: first)! }
                    Spacer()
                    Text(first.formatted(.dateTime.month(.wide).year().locale(.current))).font(.headline)
                    Spacer()
                    Button("Next Month", systemImage: "chevron.right") { month = calendar.date(byAdding: .month, value: 1, to: first)! }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                    GridRow {
                        ForEach(RRule.dayNames, id: \.self) { Text($0.prefix(2)).font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(0..<6, id: \.self) { week in
                        GridRow {
                            ForEach(0..<7, id: \.self) { column in
                                let number = week * 7 + column - lead + 1
                                if number >= 1 && number <= length {
                                    let day = calendar.date(byAdding: .day, value: number - 1, to: first)!
                                    Button { select(day) } label: {
                                        VStack(spacing: 2) {
                                            Text("\(number)").monospacedDigit()
                                                .fontWeight(day == Day.today ? .bold : .regular)
                                            Circle().fill(due.contains(day) ? Palette.accent : .clear).frame(width: 4, height: 4)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Day.formatted(day, .long) + (due.contains(day) ? ", payment due" : ""))
                                } else {
                                    Color.clear.frame(height: 1)
                                }
                            }
                        }
                    }
                }
                Text("A dot marks a next due date.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(Space.xs)
        }
    }
}

private struct DueSoonCard: View {
    let summary: Scheduling.DueSoon
    let currency = Locale.current.currency?.identifier ?? "GBP"

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("Due in Next 7 Days").font(.headline)
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("Income").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: summary.income, currency: currency).font(.title3.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Outgoing").font(.caption).foregroundStyle(.secondary)
                        MoneyText(amount: -summary.outgoing, currency: currency).font(.title3.weight(.semibold))
                    }
                }
                Text(Words.count(summary.count, "transaction")).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.xs)
        }
    }
}
