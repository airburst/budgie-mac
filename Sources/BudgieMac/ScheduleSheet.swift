import BudgieMacKit
import SwiftData
import SwiftUI

enum ScheduleSheetMode: Identifiable, Hashable {
    case add
    case edit(PersistentIdentifier)

    var id: Self { self }
}

/// S-026 Add Scheduled Transaction, S-027 Edit (with Active/Paused).
struct ScheduleSheet: View {
    let mode: ScheduleSheetMode
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @Query(filter: #Predicate<Category> { !$0.softDeleted }) private var categories: [Category]
    @State private var draft = ScheduleDraft()
    @State private var loaded = false

    private var editing: ScheduledTransaction? {
        if case .edit(let id) = mode { return context.model(for: id) as? ScheduledTransaction }
        return nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Account", selection: $draft.account) {
                    ForEach(accounts) { Text($0.name).tag(Account?.some($0)) }
                }
                TextField("Payee", text: $draft.payee, prompt: Text("Rent, Salary…"))
                Picker("Category", selection: $draft.category) {
                    Text("None").tag(Category?.none)
                    ForEach(Suggestions.categories(categories, matching: "")) { Text($0.path).tag(Category?.some($0)) }
                }
                Picker("Transfer", selection: $draft.transferTo) {
                    Text("None").tag(Account?.none)
                    ForEach(accounts.filter { $0 !== draft.account }) { Text($0.name).tag(Account?.some($0)) }
                }
                .help("Move the money to (withdrawal) or from (deposit) another of your accounts")
            }
            Section {
                TextField("Withdrawal", text: $draft.withdrawal, prompt: Text("0.00"))
                    .onChange(of: draft.withdrawal) { _, new in if !new.isEmpty { draft.deposit = "" } }
                TextField("Deposit", text: $draft.deposit, prompt: Text("0.00"))
                    .onChange(of: draft.deposit) { _, new in if !new.isEmpty { draft.withdrawal = "" } }
            }
            Section("Repeat") {
                DatePicker(editing == nil ? "First Date" : "Next Due", selection: $draft.nextDue, displayedComponents: .date)
                    .environment(\.timeZone, Day.calendar.timeZone)
                RecurrenceFields(form: $draft.recurrence)
            }
            Section {
                Toggle("Record Automatically", isOn: $draft.autoPost)
                if draft.autoPost {
                    Stepper("\(draft.daysInAdvance) days before it's due", value: $draft.daysInAdvance, in: 0...30)
                }
                TextField("Notes", text: $draft.notes, axis: .vertical)
                if editing != nil {
                    Picker("Status", selection: $draft.active) {
                        Text("Active").tag(true)
                        Text("Paused").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .help("A paused scheduled transaction is left out of the forecast, automatic recording and the 7-day summary")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editing == nil ? "Add Scheduled Transaction" : "Edit Scheduled Transaction")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Add" : "Save") {
                    model.save(draft, editing: editing, undoManager: undoManager)
                    dismiss()
                }
                .disabled(!draft.isValid())
            }
        }
        .frame(width: 480)
        .frame(minHeight: 520)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let editing {
                draft = ScheduleDraft(editing)
            } else {
                draft = ScheduleDraft(account: accounts.first { $0.uuid == model.openAccount } ?? accounts.first)
            }
        }
    }
}

/// Frequency, its day rules, and how it ends.
struct RecurrenceFields: View {
    @Binding var form: RecurrenceForm

    var body: some View {
        Picker("Frequency", selection: $form.frequency) {
            ForEach(RecurrenceForm.Frequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        switch form.frequency {
        case .once:
            EmptyView()
        case .daily:
            Stepper(form.interval == 1 ? "Every day" : "Every \(form.interval) days", value: $form.interval, in: 1...365)
        case .weekly:
            Picker("Which", selection: $form.weekPosition) {
                Text("Every week").tag(RecurrenceForm.WeekPosition.every)
                Text("First in the month").tag(RecurrenceForm.WeekPosition.first)
                Text("Second in the month").tag(RecurrenceForm.WeekPosition.second)
                Text("Third in the month").tag(RecurrenceForm.WeekPosition.third)
                Text("Fourth in the month").tag(RecurrenceForm.WeekPosition.fourth)
                Text("Fifth in the month").tag(RecurrenceForm.WeekPosition.fifth)
                Text("Last in the month").tag(RecurrenceForm.WeekPosition.last)
            }
            LabeledContent("On") {
                HStack(spacing: Space.xs) {
                    ForEach(0..<7, id: \.self) { day in
                        Toggle(String(RRule.dayNames[day].prefix(3)), isOn: member(of: \.weekdays, day))
                            .toggleStyle(.button)
                            .help(RRule.dayNames[day])
                    }
                }
            }
        case .monthly:
            Picker("Every", selection: $form.interval) {
                Text("Month").tag(1)
                Text("2 Months").tag(2)
                Text("3 Months").tag(3)
                Text("4 Months").tag(4)
                Text("6 Months").tag(6)
            }
            LabeledContent("On Days") {
                Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                    ForEach(0..<5, id: \.self) { row in
                        GridRow {
                            ForEach(1...7, id: \.self) { column in
                                let day = row * 7 + column
                                if day <= 31 {
                                    Toggle("\(day)", isOn: member(of: \.monthDays, day))
                                        .toggleStyle(.button)
                                        .monospacedDigit()
                                } else if day == 32 {
                                    Toggle("Last Day", isOn: member(of: \.monthDays, -1))
                                        .toggleStyle(.button)
                                        .gridCellColumns(4)
                                }
                            }
                        }
                    }
                }
            }
        case .yearly:
            Stepper(form.interval == 1 ? "Every year on the due date" : "Every \(form.interval) years", value: $form.interval, in: 1...10)
        }
        if form.frequency != .once {
            Picker("Ends", selection: $form.end) {
                Text("Never").tag(RecurrenceForm.End.never)
                Text("On Date").tag(RecurrenceForm.End.onDate)
                Text("After a Number of Times").tag(RecurrenceForm.End.afterCount)
            }
            switch form.end {
            case .never: EmptyView()
            case .onDate:
                DatePicker("End Date", selection: $form.endDate, displayedComponents: .date)
                    .environment(\.timeZone, Day.calendar.timeZone)
            case .afterCount:
                Stepper("After \(form.endCount) times", value: $form.endCount, in: 1...999)
            }
        }
    }

    private func member(of keyPath: WritableKeyPath<RecurrenceForm, Set<Int>>, _ value: Int) -> Binding<Bool> {
        Binding(get: { form[keyPath: keyPath].contains(value) },
                set: { on in if on { form[keyPath: keyPath].insert(value) } else { form[keyPath: keyPath].remove(value) } })
    }
}
