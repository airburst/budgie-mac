import BudgieMacKit
import Charts
import SwiftData
import SwiftUI

/// S-034 and S-035: an account's projected balance from its scheduled
/// transactions. Unticking a row is a what-if: nothing stored changes.
struct ForecastView: View {
    let account: Account
    @Environment(AppModel.self) private var model
    @Query private var schedules: [ScheduledTransaction]
    @State private var end = Forecast.defaultEnd()
    @State private var excluded = Set<String>()
    @State private var selection: String?
    @State private var showingHelp = false

    var body: some View {
        let rows = Forecast.rows(for: account, schedules: schedules, through: end)
        let balances = Forecast.balances(rows, start: account.balance, excluded: excluded)
        let currency = account.currency
        VStack(spacing: 0) {
            chart(rows, balances: balances, currency: currency)
                .frame(height: 220)
                .padding(Space.margin)
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Scheduled", systemImage: "calendar")
                } description: {
                    Text("No scheduled transactions touch \(account.name) before \(Day.formatted(end, .abbreviated)).")
                }
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Include") { row in
                        Toggle("Include", isOn: Binding(
                            get: { !excluded.contains(row.id) },
                            set: { on in if on { excluded.remove(row.id) } else { excluded.insert(row.id) } }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .help("Untick to see the balance without this one. Nothing is changed.")
                    }
                    .width(56)
                    TableColumn("Date") { Text(Day.formatted($0.date)).monospacedDigit() }
                        .width(min: 80, ideal: 96)
                    TableColumn("Payee") { row in
                        Label(row.payee, systemImage: row.isTransfer ? "arrow.left.arrow.right" : "calendar")
                            .lineLimit(1)
                            .opacity(excluded.contains(row.id) ? 0.5 : 1)
                    }
                    TableColumn("Amount") { MoneyText(amount: $0.amount, currency: currency) }
                        .width(min: 90, ideal: 110)
                        .alignment(.trailing)
                    TableColumn("Projected Balance") { row in
                        let balance = balances[row.id] ?? 0
                        Text(Money.string(balance, currency: currency))
                            .monospacedDigit()
                            .foregroundStyle(balance < 0 ? Palette.moneyOut : Color.primary)
                    }
                    .width(min: 110, ideal: 130)
                    .alignment(.trailing)
                }
            }
        }
        .inspector(isPresented: .constant(selection != nil)) {
            if let row = rows.first(where: { $0.id == selection }) {
                ForecastDetails(row: row, balance: balances[row.id] ?? 0, included: !excluded.contains(row.id), currency: currency)
                    .inspectorColumnWidth(min: 220, ideal: 260)
            }
        }
        .navigationTitle("Forecast \(account.name)")
        .navigationSubtitle("Balance today \(Money.string(account.balance, currency: currency))")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Register", systemImage: "chevron.left") { model.forecastFor = nil }
                    .help("Back to the register (Escape)")
            }
            ToolbarItemGroup {
                DatePicker("Until", selection: $end, in: Day.today..., displayedComponents: .date)
                    .environment(\.timeZone, Day.calendar.timeZone)
                    .help("How far ahead to project")
                Button("Show All", systemImage: "checklist.checked") { excluded = [] }
                    .disabled(excluded.isEmpty)
                    .help("Include every projected transaction again")
                Button("Help", systemImage: "questionmark.circle") { showingHelp.toggle() }
                    .popover(isPresented: $showingHelp) { ForecastHelp() }
            }
        }
        .onExitCommand { model.forecastFor = nil }
    }

    private func chart(_ rows: [ForecastRow], balances: [String: Decimal], currency: String) -> some View {
        let points = [(Day.today, account.balance)] + rows.map { ($0.date, balances[$0.id] ?? 0) }
        return Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.0), y: .value("Balance", NSDecimalNumber(decimal: point.1).doubleValue))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Palette.accent)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Decimal(amount).formatted(.currency(code: currency).precision(.fractionLength(0))))
                    }
                }
            }
        }
        .accessibilityLabel("Projected balance of \(account.name)")
    }
}

/// Row details (S-035): date, amount, projected balance, status, source, category, memo.
private struct ForecastDetails: View {
    let row: ForecastRow
    let balance: Decimal
    let included: Bool
    let currency: String

    var body: some View {
        Form {
            LabeledContent("Date", value: Day.formatted(row.date, .long))
            LabeledContent("Amount") { MoneyText(amount: row.amount, currency: currency) }
            LabeledContent("Projected Balance", value: Money.string(balance, currency: currency))
            LabeledContent("Status", value: included ? "Included" : "Left out of this forecast")
            LabeledContent("Source", value: row.isTransfer ? "Scheduled transfer “\(row.payee)”" : "Scheduled transaction “\(row.payee)”")
            LabeledContent("Category", value: row.categoryPath ?? "None")
            LabeledContent("Memo", value: row.notes ?? "None")
        }
        .formStyle(.grouped)
    }
}

/// S-035: what the forecast shows and what the ticks do.
private struct ForecastHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("About the Forecast").font(.headline)
            Text("The line starts at today's balance and steps at each scheduled transaction up to the date you choose. The dashed line is zero.")
            Text("Untick a row to see the balance without it. Ticks are a what-if: nothing in your accounts or schedules changes.")
            Text("Paused scheduled transactions are left out. Transfers into this account count as deposits.")
        }
        .font(.callout)
        .frame(width: 300, alignment: .leading)
        .padding(Space.lg)
    }
}
