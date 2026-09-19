import Foundation

enum UTCDate {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    // Foundation's DateFormatter is thread-safe. Reuse it instead of creating
    // hundreds of ICU formatters whenever a chart or statistic is rendered.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func parse(_ text: String) -> Date? { formatter.date(from: text) }
}

struct PeriodKey: Hashable, Sendable {
    var start: Date?
    var end: Date?

    init(_ filter: TradeTimeFilter, now: Date) {
        let bounds = filter.bounds(now: now)
        start = bounds?.start
        end = bounds?.end
    }
}

struct TradeTimeFilter: Codable, Equatable, Sendable {
    enum Preset: String, Codable, CaseIterable, Sendable {
        case today, week, month, quarter, all, custom
        var title: String {
            switch self {
            case .today: "今天"
            case .week: "近7天"
            case .month: "近30天"
            case .quarter: "近90天"
            case .all: "全部"
            case .custom: "自定义"
            }
        }
    }
    var preset: Preset = .month
    var start = Date()
    var end = Date()

    /// Calendar days in UTC, including the full end day, expressed as [start, end).
    func bounds(now: Date = Date()) -> DateInterval? {
        let calendar = UTCDate.calendar
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        switch preset {
        case .all: return nil
        case .custom:
            let first = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            return DateInterval(start: first, end: calendar.date(byAdding: .day, value: 1, to: last)!)
        default:
            let days = preset == .today ? 1 : (preset == .week ? 7 : (preset == .month ? 30 : 90))
            return DateInterval(start: calendar.date(byAdding: .day, value: 1 - days, to: today)!, end: tomorrow)
        }
    }

    func contains(_ trade: Trade, now: Date = Date()) -> Bool {
        guard !trade.isOpen, let date = trade.closedAt else { return false }
        guard let interval = bounds(now: now) else { return true }
        return date >= interval.start && date < interval.end
    }

    var title: String {
        preset == .custom ? "\(UTCDate.string(start)) 至 \(UTCDate.string(end))" : preset.title
    }
}

struct PeriodReport: Sendable {
    let id = UUID()
    var trades: [Trade]
    var daily: [DailyProfit]
    var performance: [PairPerformance]
    var wins: Int
    var losses: Int
    var draws: Int
    var missingValues: Int
    var profit: Double?
    var winrate: Double?
    var profitFactor: Double?
    var averageWin: Double?
    var averageLoss: Double?
    var expectancy: Double?
    var averageDuration: TimeInterval?
    var cumulativePoints: [CurvePoint]
    var dailyPoints: [CurvePoint]
    var count: Int { trades.count }

    init(trades allTrades: [Trade], filter: TradeTimeFilter, now: Date = Date()) {
        let interval = filter.bounds(now: now)
        trades = allTrades.filter { trade in
            guard !trade.isOpen, let date = trade.closedAt else { return false }
            return interval.map { date >= $0.start && date < $0.end } ?? true
        }.sorted { ($0.closeTimestamp ?? 0) > ($1.closeTimestamp ?? 0) }
        let values = trades.compactMap(\.pnl).filter(\.isFinite)
        let positives = values.filter { $0 > 0 }
        let negatives = values.filter { $0 < 0 }
        wins = positives.count
        losses = negatives.count
        draws = values.filter { $0 == 0 }.count
        missingValues = trades.count - values.count
        profit = missingValues == 0 ? values.reduce(0, +) : nil
        winrate = !trades.isEmpty && missingValues == 0 ? Double(wins) / Double(trades.count) : nil
        let grossWin = positives.reduce(0, +)
        let grossLoss = abs(negatives.reduce(0, +))
        profitFactor = missingValues > 0 || trades.isEmpty ? nil : (grossLoss > 0 ? grossWin / grossLoss : (grossWin > 0 ? .infinity : nil))
        averageWin = positives.isEmpty || missingValues > 0 ? nil : grossWin / Double(positives.count)
        averageLoss = negatives.isEmpty || missingValues > 0 ? nil : -grossLoss / Double(negatives.count)
        let tradeCount = trades.count
        expectancy = tradeCount == 0 ? nil : profit.map { $0 / Double(tradeCount) }
        averageDuration = trades.isEmpty ? nil : trades.reduce(0) { $0 + max(0, ($1.closedAt ?? $1.openedAt).timeIntervalSince($1.openedAt)) } / Double(trades.count)

        let calendar = UTCDate.calendar
        let grouped = Dictionary(grouping: trades) { UTCDate.string($0.closedAt!) }
        let start = interval?.start ?? calendar.startOfDay(for: trades.last?.closedAt ?? now)
        let finish = interval?.end ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var date = start
        daily = []
        while date < finish {
            let key = UTCDate.string(date)
            let dayTrades = grouped[key] ?? []
            daily.append(DailyProfit(date: key, absProfit: dayTrades.reduce(0) { $0 + ($1.pnl ?? 0) }, tradeCount: dayTrades.count))
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        // A missing P&L must never silently become a zero-valued chart or ranking.
        if missingValues > 0 { daily = [] }
        cumulativePoints = Metrics.curve(daily, limit: daily.count)
        dailyPoints = daily.map { CurvePoint(date: $0.day, value: $0.absProfit) }
        performance = missingValues > 0 ? [] : Dictionary(grouping: trades, by: \.pair).map { pair, trades in
            PairPerformance(pair: pair, profitAbs: trades.reduce(0) { $0 + ($1.pnl ?? 0) }, count: trades.count)
        }.sorted { $0.profitAbs > $1.profitAbs }
    }
}
