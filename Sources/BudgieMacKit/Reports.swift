import Foundation

/// M6: the numbers behind Reports, following Budgie's `useReportsData.ts`.
/// Charts cover one currency (the Mac's own by default); summary figures are
/// given per currency, so a EUR account is never added to a GBP total.
public enum Reports {
    public enum Period: String, CaseIterable, Sendable {
        case last30, last60, last90, thisMonth, lastMonth, thisYear

        public var title: String {
            switch self {
            case .last30: "Last 30 Days"
            case .last60: "Last 60 Days"
            case .last90: "Last 90 Days"
            case .thisMonth: "This Month"
            case .lastMonth: "Last Month"
            case .thisYear: "This Year"
            }
        }

        /// First and last day, inclusive. "Last 90 Days" starts 90 days
        /// before today, as Budgie, so it spans 91 days.
        public func range(today: Date = Day.today) -> ClosedRange<Date> {
            let calendar = Day.calendar
            let monthStart = Day.parse(Budget.month(of: today) + "-01")!
            switch self {
            case .last30: return calendar.date(byAdding: .day, value: -30, to: today)!...today
            case .last60: return calendar.date(byAdding: .day, value: -60, to: today)!...today
            case .last90: return calendar.date(byAdding: .day, value: -90, to: today)!...today
            case .thisMonth: return monthStart...today
            case .lastMonth:
                let start = calendar.date(byAdding: .month, value: -1, to: monthStart)!
                return start...calendar.date(byAdding: .day, value: -1, to: monthStart)!
            case .thisYear:
                return Day.parse("\(calendar.component(.year, from: today))-01-01")!...today
            }
        }
    }

    public struct Slice: Equatable, Sendable {
        public var name: String
        public var amount: Decimal
    }

    public struct MonthTotals: Equatable, Sendable {
        public var month: String
        public var income: Decimal = 0
        public var expenses: Decimal = 0
        public var difference: Decimal { income - expenses }
    }

    public struct NetWorthPoint: Equatable, Sendable {
        public var month: String
        public var netWorth: Decimal
    }

    /// The transactions a report looks at: in range, in the chosen accounts
    /// (empty = all), in one currency.
    public static func transactions(_ all: [Transaction], in range: ClosedRange<Date>, accounts: Set<UUID>, currency: String) -> [Transaction] {
        all.filter { transaction in
            guard let account = transaction.account, account.currency == currency, range.contains(transaction.date) else { return false }
            return accounts.isEmpty || accounts.contains(account.uuid)
        }
    }

    /// S-044: expense categories by spending, top five and Other. Transfers and
    /// income are left out; categories don't roll up to their parent (as Budgie).
    public static func spending(_ transactions: [Transaction]) -> [Slice] {
        var byCategory: [String: Decimal] = [:]
        for transaction in transactions where !transaction.isTransfer {
            guard let category = transaction.category, category.kind == .expense else { continue }
            byCategory[category.name, default: 0] += abs(transaction.amount)
        }
        let sorted = byCategory.sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        var slices = sorted.prefix(5).map { Slice(name: $0.key, amount: $0.value) }
        let other = sorted.dropFirst(5).reduce(Decimal(0)) { $0 + $1.value }
        if other > 0 { slices.append(Slice(name: "Other", amount: other)) }
        return slices
    }

    /// S-045: income and expenses per month, transfers left out.
    public static func incomeVsExpenses(_ transactions: [Transaction]) -> [MonthTotals] {
        var months: [String: MonthTotals] = [:]
        for transaction in transactions where !transaction.isTransfer {
            let m = Budget.month(of: transaction.date)
            var totals = months[m] ?? MonthTotals(month: m)
            switch transaction.category?.kind {
            case .income: totals.income += transaction.amount
            case .expense: totals.expenses += abs(transaction.amount)
            default: break
            }
            months[m] = totals
        }
        return months.values.sorted { $0.month < $1.month }
    }

    /// S-046: net worth at the end of each month in range = the chosen
    /// accounts' balances on that day, in one currency.
    public static func netWorth(accounts: [Account], range: ClosedRange<Date>, currency: String) -> [NetWorthPoint] {
        let shown = accounts.filter { $0.currency == currency }
        var points: [NetWorthPoint] = []
        var month = Budget.month(of: range.lowerBound)
        let last = Budget.month(of: range.upperBound)
        while month <= last {
            let monthEnd = Day.calendar.date(byAdding: .day, value: -1, to: Day.parse(Budget.month(month, adding: 1) + "-01")!)!
            let end = min(monthEnd, range.upperBound)
            let total = shown.reduce(Decimal(0)) { $0 + $1.balance(on: end) }
            points.append(NetWorthPoint(month: month, netWorth: total))
            month = Budget.month(month, adding: 1)
        }
        return points
    }

    public struct Figures: Equatable, Sendable {
        /// Per currency, by code.
        public var assets: [String: Decimal] = [:]
        public var debt: [String: Decimal] = [:]
        /// For the latest complete month in range (or the latest month).
        public var surplus: Decimal?
        /// nil when that month had no income: shown as "—".
        public var savingRate: Double?
    }

    static let assetTypes: Set<AccountType> = [.bank, .investment, .cash]

    /// S-048: Total Assets and Total Debt per currency, as of today (entries
    /// dated later are left out, as in Net Worth and the forecast); Monthly Surplus and
    /// Saving Rate (surplus ÷ income) for the latest complete month in range.
    public static func figures(accounts: [Account], months: [MonthTotals], today: Date = Day.today) -> Figures {
        var figures = Figures()
        for account in accounts {
            if assetTypes.contains(account.type) {
                figures.assets[account.currency, default: 0] += account.balance(on: today)
            } else {
                figures.debt[account.currency, default: 0] += abs(account.balance(on: today))
            }
        }
        let thisMonth = Budget.month(of: today)
        if let month = months.last(where: { $0.month < thisMonth }) ?? months.last {
            figures.surplus = month.difference
            if month.income > 0 {
                figures.savingRate = NSDecimalNumber(decimal: month.difference / month.income).doubleValue
            }
        }
        return figures
    }
}
