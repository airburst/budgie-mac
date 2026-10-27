import AppKit
import BudgieMacKit
import Charts
import SwiftData
import SwiftUI

/// M6: spending by category, income vs expenses, net worth, and summary
/// figures, for a period and a set of accounts.
struct ReportsPage: View {
    @Environment(AppModel.self) private var model
    @Query private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { !$0.softDeleted }, sort: \Account.name) private var accounts: [Account]
    @AppStorage("reports.period") private var period: Reports.Period = .last90
    @State private var chosen = Set<UUID>()
    private let currency = Locale.current.currency?.identifier ?? "GBP"

    var body: some View {
        if transactions.isEmpty {
            ContentUnavailableView {
                Label("No Reports Yet", systemImage: "chart.bar")
            } description: {
                Text("Reports appear once your accounts have transactions. Add an account, or bring your data over from Budgie.")
            } actions: {
                Button("Import from Budgie…") { model.importFlow.chooseFile() }
                    .buttonStyle(.borderedProminent)
            }
            .navigationTitle("Reports")
        } else {
            report
        }
    }

    @ViewBuilder private var report: some View {
        let range = period.range()
        let shownAccounts = chosen.isEmpty ? accounts : accounts.filter { chosen.contains($0.uuid) }
        let rows = Reports.transactions(transactions, in: range, accounts: chosen, currency: currency)
        let months = Reports.incomeVsExpenses(rows)
        let figures = Reports.figures(accounts: shownAccounts, months: months)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if shownAccounts.contains(where: { $0.currency != currency }) {
                    Label("Charts show \(currency) accounts. Figures below are given per currency.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: Space.lg) {
                    SpendingCard(slices: Reports.spending(rows), currency: currency)
                    IncomeExpensesCard(months: months, currency: currency)
                }
                .fixedSize(horizontal: false, vertical: true)
                NetWorthCard(points: Reports.netWorth(accounts: shownAccounts, range: range, currency: currency), currency: currency)
                FiguresRow(figures: figures, currency: currency)
            }
            .padding(Space.margin)
        }
        .navigationTitle("Reports")
        .navigationSubtitle("\(period.title) · \(Day.formatted(range.lowerBound, .abbreviated)) to \(Day.formatted(range.upperBound, .abbreviated))")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Period", selection: $period) {
                        ForEach(Reports.Period.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(period.title, systemImage: "calendar")
                }
                .help("Choose the period: \(period.title)")
                Menu {
                    Button("All Accounts") { chosen = [] }
                    Divider()
                    ForEach(accounts) { account in
                        Toggle(account.name, isOn: Binding(
                            get: { chosen.contains(account.uuid) },
                            set: { on in if on { chosen.insert(account.uuid) } else { chosen.remove(account.uuid) } }))
                    }
                } label: {
                    Label(chosen.isEmpty ? "All Accounts" : Words.count(chosen.count, "Account"), systemImage: "building.columns")
                        .labelStyle(.titleAndIcon)
                }
                .help("Choose which accounts to include")
            }
        }
    }
}

/// The reference categorical palette (dataviz skill), stepped for light and
/// dark, validated with its script. Slot order is fixed; Other is neutral.
enum ChartColors {
    static let series: [Color] = [
        Palette.dynamic(light: 0x2a78d6, dark: 0x3987e5), Palette.dynamic(light: 0xeb6834, dark: 0xd95926),
        Palette.dynamic(light: 0x1baf7a, dark: 0x199e70), Palette.dynamic(light: 0xeda100, dark: 0xc98500),
        Palette.dynamic(light: 0xe87ba4, dark: 0xd55181),
    ]
    static let other = Color.gray
}

/// A chart card with a title and a Show Values switch to a table.
private struct ChartCard<ChartContent: View, Values: View>: View {
    let title: String
    let headline: String?
    @ViewBuilder let chart: ChartContent
    @ViewBuilder let values: Values
    @State private var showValues = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        if let headline { Text(headline).font(.title3.weight(.semibold)).monospacedDigit() }
                    }
                    Spacer()
                    Toggle("Show Values", isOn: $showValues)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .help("Show the numbers as a table")
                }
                if showValues { values } else { chart }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.sm)
        }
    }
}

private struct SpendingCard: View {
    let slices: [Reports.Slice]
    let currency: String

    private var total: Decimal { slices.reduce(0) { $0 + $1.amount } }
    private func color(_ index: Int, _ slice: Reports.Slice) -> Color {
        slice.name == "Other" ? ChartColors.other : ChartColors.series[index % ChartColors.series.count]
    }

    var body: some View {
        ChartCard(title: "Spending by Category", headline: nil) {
            if slices.isEmpty {
                ContentUnavailableView("No spending in this period", systemImage: "chart.pie")
                    .frame(height: 220)
            } else {
                HStack(spacing: Space.lg) {
                    Chart(Array(slices.enumerated()), id: \.offset) { index, slice in
                        SectorMark(angle: .value("Spent", NSDecimalNumber(decimal: slice.amount).doubleValue),
                                   innerRadius: .ratio(0.62), angularInset: 1)
                            .cornerRadius(2)
                            .foregroundStyle(color(index, slice))
                    }
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            Text("Total").font(.caption).foregroundStyle(.secondary)
                            Text(Money.string(total, currency: currency)).font(.headline).monospacedDigit()
                        }
                    }
                    .frame(width: 200, height: 200)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        ForEach(Array(slices.enumerated()), id: \.offset) { index, slice in
                            HStack(spacing: Space.sm) {
                                Circle().fill(color(index, slice)).frame(width: 8, height: 8)
                                Text(slice.name).lineLimit(1)
                                Spacer()
                                Text(Money.string(slice.amount, currency: currency)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.callout)
                }
            }
        } values: {
            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                GridRow { Text("Category"); Text("Spent"); Text("Share") }.font(.caption).foregroundStyle(.secondary)
                ForEach(slices, id: \.name) { slice in
                    GridRow {
                        Text(slice.name)
                        Text(Money.string(slice.amount, currency: currency)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text(total > 0 ? (NSDecimalNumber(decimal: slice.amount / total).doubleValue).formatted(.percent.precision(.fractionLength(0))) : "—")
                            .monospacedDigit().gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }
}

private struct IncomeExpensesCard: View {
    let months: [Reports.MonthTotals]
    let currency: String

    var body: some View {
        ChartCard(title: "Income and Expenses", headline: nil) {
            if months.isEmpty {
                ContentUnavailableView("No income or expenses in this period", systemImage: "chart.bar")
                    .frame(height: 220)
            } else {
                Chart {
                    ForEach(months, id: \.month) { month in
                        BarMark(x: .value("Month", Budget.title(of: month.month)), y: .value("Amount", NSDecimalNumber(decimal: month.income).doubleValue))
                            .foregroundStyle(by: .value("Kind", "Income"))
                            .position(by: .value("Kind", "Income")) // grid: ok Swift Charts grouping, not layout
                            .cornerRadius(4)
                        BarMark(x: .value("Month", Budget.title(of: month.month)), y: .value("Amount", NSDecimalNumber(decimal: month.expenses).doubleValue))
                            .foregroundStyle(by: .value("Kind", "Expenses"))
                            .position(by: .value("Kind", "Expenses")) // grid: ok Swift Charts grouping, not layout
                            .cornerRadius(4)
                    }
                }
                .chartForegroundStyleScale(["Income": Palette.moneyIn, "Expenses": Palette.moneyOut])
                .chartLegend(position: .top, alignment: .leading)
                .chartYAxis { currencyAxis(currency) }
                .frame(height: 220)
            }
        } values: {
            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                GridRow { Text("Month"); Text("Income"); Text("Expenses"); Text("Difference") }.font(.caption).foregroundStyle(.secondary)
                ForEach(months, id: \.month) { month in
                    GridRow {
                        Text(Budget.title(of: month.month))
                        Text(Money.string(month.income, currency: currency)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text(Money.string(month.expenses, currency: currency)).monospacedDigit().gridColumnAlignment(.trailing)
                        MoneyText(amount: month.difference, currency: currency).gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }
}

private struct NetWorthCard: View {
    let points: [Reports.NetWorthPoint]
    let currency: String
    @Environment(AppModel.self) private var model

    var body: some View {
        // Signed headline: "-£573.48", never "£-573.48".
        let values = points.map { NSDecimalNumber(decimal: $0.netWorth).doubleValue }
        let low = values.min() ?? 0, high = values.max() ?? 0
        let pad = max((high - low) * 0.15, abs(high) * 0.02, 1)
        let domain = (low - pad)...(high + pad)
        return ChartCard(title: "Net Worth", headline: points.last.map { Money.string($0.netWorth, currency: currency) }) {
            Chart(points, id: \.month) { point in
                // Scaled to the data: the area starts at the bottom of the range, not at zero.
                AreaMark(x: .value("Month", Budget.title(of: point.month)),
                         yStart: .value("Base", domain.lowerBound),
                         yEnd: .value("Net Worth", NSDecimalNumber(decimal: point.netWorth).doubleValue))
                    .foregroundStyle(ChartColors.series[0].opacity(0.18))
                LineMark(x: .value("Month", Budget.title(of: point.month)), y: .value("Net Worth", NSDecimalNumber(decimal: point.netWorth).doubleValue))
                    .foregroundStyle(ChartColors.series[0])
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .symbol(.circle)
                if point.month == model.netWorthFocus {
                    // Hover or click: a guide, a bigger point, and the month's value.
                    RuleMark(x: .value("Month", Budget.title(of: point.month)))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    PointMark(x: .value("Month", Budget.title(of: point.month)), y: .value("Net Worth", NSDecimalNumber(decimal: point.netWorth).doubleValue))
                        .symbolSize(80)
                        .foregroundStyle(ChartColors.series[0])
                        .annotation(position: .topTrailing, spacing: Space.xs,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Budget.title(of: point.month)).font(.caption).foregroundStyle(.secondary)
                                Text(Money.string(point.netWorth, currency: currency)).font(.callout.weight(.semibold)).monospacedDigit()
                            }
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, Space.xs)
                            .background(.background.secondary, in: .rect(cornerRadius: Space.sm))
                        }
                }
            }
            .chartYScale(domain: domain)
            .chartYAxis { currencyAxis(currency) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(.rect)
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): focus(at: location, proxy: proxy, geometry: geometry)
                            case .ended: model.netWorthFocus = nil
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 0).onChanged { focus(at: $0.location, proxy: proxy, geometry: geometry) })
                }
            }
            .frame(height: 200)
        } values: {
            Grid(alignment: .leading, horizontalSpacing: Space.lg, verticalSpacing: Space.xs) {
                GridRow { Text("Month end"); Text("Net Worth") }.font(.caption).foregroundStyle(.secondary)
                ForEach(points, id: \.month) { point in
                    GridRow {
                        Text(Budget.title(of: point.month))
                        MoneyText(amount: point.netWorth, currency: currency).gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }

    /// The month nearest the pointer.
    private func focus(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let frame = proxy.plotFrame.map({ geometry[$0] }) else { return }
        let x = location.x - frame.origin.x
        let distance = { (point: Reports.NetWorthPoint) in abs((proxy.position(forX: Budget.title(of: point.month)) ?? .infinity) - x) } // grid: ok chart lookup, not layout
        model.netWorthFocus = points.min { distance($0) < distance($1) }?.month
    }
}

private func currencyAxis(_ currency: String) -> some AxisContent {
    AxisMarks { value in
        AxisGridLine()
        AxisValueLabel {
            if let amount = value.as(Double.self) {
                Text(Decimal(amount).formatted(.currency(code: currency).precision(.fractionLength(0))))
            }
        }
    }
}

/// S-048: per currency, so a EUR account is never added to a GBP total.
private struct FiguresRow: View {
    let figures: Reports.Figures
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Figure(title: "Total Assets", lines: perCurrency(figures.assets))
            Figure(title: "Total Debt", lines: perCurrency(figures.debt))
            Figure(title: "Monthly Surplus", lines: [figures.surplus.map { Money.string($0, currency: currency) } ?? "—"],
                   note: "Latest complete month in the period")
            Figure(title: "Saving Rate", lines: [figures.savingRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"],
                   note: "Surplus ÷ income for that month")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func perCurrency(_ values: [String: Decimal]) -> [String] {
        let codes = values.keys.sorted { ($0 == currency ? 0 : 1, $0) < ($1 == currency ? 0 : 1, $1) }
        return codes.isEmpty ? [Money.string(0, currency: currency)] : codes.map { Money.string(values[$0]!, currency: $0) }
    }
}

private struct Figure: View {
    let title: String
    let lines: [String]
    var note: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.callout).foregroundStyle(.secondary)
                ForEach(lines, id: \.self) { Text($0).font(.title3.weight(.semibold)).monospacedDigit() }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.xs)
        }
    }
}
