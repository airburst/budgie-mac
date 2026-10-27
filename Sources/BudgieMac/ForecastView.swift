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
    @State private var choosingEnd = false

    var body: some View {
        let start = Forecast.startBalance(of: account)
        let rows = Forecast.rows(for: account, schedules: schedules, through: end)
        let balances = Forecast.balances(rows, start: start, excluded: excluded)
        let currency = account.currency
        VStack(spacing: 0) {
            ForecastChart(points: Forecast.points(rows, balances: balances, start: start, end: end),
                          accountName: account.name, currency: currency)
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
                        Label(row.payee, systemImage: row.isTransfer ? "arrow.left.arrow.right" : row.isScheduled ? "calendar" : "list.bullet")
                            .help(row.isScheduled ? "Scheduled" : "In the register, dated after today")
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
        .navigationSubtitle("Balance today \(Money.string(start, currency: currency))")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Back to Register", systemImage: "chevron.left") { model.forecastFor = nil }
                    .help("Back to the register (Escape)")
            }
            ToolbarItemGroup {
                Button { choosingEnd.toggle() } label: {
                    Label("Until \(Day.formatted(end))", systemImage: "calendar").labelStyle(.titleAndIcon).monospacedDigit()
                }
                .help("How far ahead to project")
                .popover(isPresented: $choosingEnd) {
                    DatePicker("Until", selection: $end, in: Day.today..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .environment(\.timeZone, Day.calendar.timeZone)
                        .padding(Space.md)
                }
                Button("Show All", systemImage: "checklist.checked") { excluded = [] }
                    .disabled(excluded.isEmpty)
                    .help("Include every projected transaction again")
                Button("Help", systemImage: "questionmark.circle") { showingHelp.toggle() }
                    .popover(isPresented: $showingHelp) { ForecastHelp() }
            }
        }
        .onExitCommand { model.forecastFor = nil }
        .onDisappear { model.forecastFocus = nil }
    }
}

/// The projected balance as a stepped line. Hovering or clicking shows a
/// dashed guide, a point on the line, and that day's date and balance.
private struct ForecastChart: View {
    let points: [ForecastPoint]
    let accountName: String
    let currency: String
    @Environment(AppModel.self) private var model

    /// The balance on a day is the last point on or before it.
    private var focused: ForecastPoint? {
        guard let day = model.forecastFocus else { return nil }
        return points.last { $0.date <= day } ?? points.first
    }

    /// As Net Worth: scaled to the data, but always showing zero.
    private var domain: ClosedRange<Double> {
        let values = points.map { Self.double($0.balance) }
        let low = min(values.min() ?? 0, 0), high = max(values.max() ?? 0, 0)
        let pad = max((high - low) * 0.15, abs(high) * 0.02, 1)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        let domain = domain
        Chart {
            ForEach(points, id: \.date) { point in
                // The same area and line as the Net Worth chart, stepped on each day.
                AreaMark(x: .value("Date", point.date),
                         yStart: .value("Base", domain.lowerBound),
                         yEnd: .value("Balance", Self.double(point.balance)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(ChartColors.series[0].opacity(0.18))
                LineMark(x: .value("Date", point.date), y: .value("Balance", Self.double(point.balance)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(ChartColors.series[0])
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if let focused, let day = model.forecastFocus {
                RuleMark(x: .value("Day", day))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                PointMark(x: .value("Day", day), y: .value("Balance", Self.double(focused.balance)))
                    .symbolSize(80)
                    .foregroundStyle(ChartColors.series[0])
                    .annotation(position: .topTrailing, spacing: Space.xs,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Day.formatted(day, .abbreviated)).font(.caption).foregroundStyle(.secondary)
                            Text(Money.string(focused.balance, currency: currency)).font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, Space.xs)
                        .background(.background.secondary, in: .rect(cornerRadius: Space.sm))
                    }
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: (points.first?.date ?? Day.today)...(points.last?.date ?? Day.today))
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location): focus(at: location, proxy: proxy, geometry: geometry)
                        case .ended: model.forecastFocus = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0).onChanged { focus(at: $0.location, proxy: proxy, geometry: geometry) })
            }
        }
        .accessibilityLabel("Projected balance of \(accountName)")
        .accessibilityValue(focused.map { "\(Day.formatted($0.date, .abbreviated)), \(Money.string($0.balance, currency: currency))" } ?? "")
    }

    /// Snaps the pointer to a whole day inside the forecast.
    private func focus(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame.map({ geometry[$0] }),
              let date: Date = proxy.value(atX: location.x - frame.origin.x),
              let first = points.first?.date, let last = points.last?.date else { return }
        let day = Day.calendar.startOfDay(for: date)
        model.forecastFocus = min(max(day, first), last)
    }

    private static func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
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
            LabeledContent("Source", value: row.isScheduled
                ? (row.isTransfer ? "Scheduled transfer “\(row.payee)”" : "Scheduled transaction “\(row.payee)”")
                : "In the register, dated after today")
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
            Text("The line starts at today's balance and steps at each scheduled transaction up to the date you choose. Register entries dated after today come in on their own day. The dashed line is zero.")
            Text("Point at the chart, or click it, to see the balance on any day.")
            Text("Untick a row to see the balance without it. Ticks are a what-if: nothing in your accounts or schedules changes.")
            Text("Paused scheduled transactions are left out. Transfers into this account count as deposits.")
        }
        .font(.callout)
        .frame(width: 300, alignment: .leading)
        .padding(Space.lg)
    }
}
