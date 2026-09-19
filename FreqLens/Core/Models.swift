import Foundation

struct BotConfig: Codable, Sendable {
    var botName: String
    var strategy: String?
    var exchange: String
    var timeframe: String?
    var stakeCurrency: String
    var dryRun: Bool
    var state: String
    var version: String
    var tradingMode: String?
    var maxOpenTrades: Double?
}

struct Profit: Codable, Sendable {
    var profitClosedCoin: Double
    var profitClosedRatio: Double
    var profitAllCoin: Double
    var profitAllRatio: Double
    var tradeCount: Int
    var closedTradeCount: Int
    var winningTrades: Int
    var losingTrades: Int
    var winrate: Double
    var profitFactor: Double?
    var maxDrawdown: Double?
    var maxDrawdownAbs: Double?
    var currentDrawdown: Double?
    var expectancy: Double?
    var sharpe: Double?
    var sortino: Double?
    var avgDuration: String?
    var tradingVolume: Double?
}

struct Wallet: Codable, Sendable {
    var currencies: [WalletAsset]
    var total: Double
    var totalBot: Double?
    var stake: String
    var startingCapital: Double?
    var botValue: Double { totalBot ?? total }
}

struct WalletAsset: Codable, Identifiable, Sendable {
    var currency: String
    var free: Double
    var balance: Double
    var used: Double
    var estStake: Double
    var estStakeBot: Double?
    var side: String?
    var id: String { currency + (side ?? "") }
}

struct Trade: Codable, Identifiable, Hashable, Sendable {
    var tradeId: Int
    var pair: String
    var isOpen: Bool
    var isShort: Bool?
    var amount: Double
    var stakeAmount: Double
    var openRate: Double
    var openTimestamp: Double
    var closeTimestamp: Double?
    var closeRate: Double?
    var currentRate: Double?
    var profitAbs: Double?
    var profitRatio: Double?
    var closeProfitAbs: Double?
    var closeProfit: Double?
    var totalProfitAbs: Double?
    var totalProfitRatio: Double?
    var realizedProfit: Double?
    var strategy: String?
    var enterTag: String?
    var exitReason: String?
    var leverage: Double?
    var stopLossAbs: Double?
    var liquidationPrice: Double?
    var timeframe: Int?
    var id: Int { tradeId }
    var symbol: String { String(pair.split(separator: "/").first ?? Substring(pair)) }
    var pnl: Double? { isOpen ? (totalProfitAbs ?? profitAbs) : (closeProfitAbs ?? profitAbs) }
    var ratio: Double? { isOpen ? (totalProfitRatio ?? profitRatio) : (closeProfit ?? profitRatio) }
    var mark: Double? { isOpen ? currentRate : closeRate }
    var openedAt: Date { Date(timeIntervalSince1970: openTimestamp / 1_000) }
    var closedAt: Date? { closeTimestamp.map { Date(timeIntervalSince1970: $0 / 1_000) } }
    var direction: String { isShort == true ? "空头" : "多头" }
}

struct TradePage: Codable, Sendable {
    var trades: [Trade]
    var tradesCount: Int
    var offset: Int
    var totalTrades: Int
}

struct PairPerformance: Codable, Identifiable, Sendable {
    var pair: String
    var profitAbs: Double
    var profitRatio: Double?
    var count: Int
    var id: String { pair }
}

struct DailyResponse: Codable, Sendable {
    var data: [DailyProfit]
    var stakeCurrency: String
}

struct DailyProfit: Codable, Identifiable, Sendable {
    var date: String
    var absProfit: Double
    var relProfit: Double?
    var tradeCount: Int
    var id: String { date }
    var day: Date { Self.parseDay(date) ?? .distantPast }

    static func parseDay(_ string: String) -> Date? {
        UTCDate.parse(string)
    }
}

struct CurvePoint: Identifiable, Sendable {
    var date: Date
    var value: Double
    var id: Date { date }
}

enum Metrics {
    /// Return against the server's starting capital, never a sum of individual trade returns.
    static func returnRatio(profit: Double?, startingCapital: Double?) -> Double? {
        guard let profit, profit.isFinite, let startingCapital,
              startingCapital.isFinite, startingCapital > 0 else { return nil }
        let ratio = profit / startingCapital
        return ratio.isFinite && (ratio * 100).isFinite ? ratio : nil
    }

    /// Daily values are realized P&L in the stake currency, never account equity.
    static func curve(_ days: [DailyProfit], limit: Int) -> [CurvePoint] {
        let sorted = days.filter { DailyProfit.parseDay($0.date) != nil }.sorted { $0.date < $1.date }.suffix(limit)
        guard let first = sorted.first else { return [] }
        var result = [CurvePoint(date: first.day.addingTimeInterval(-86_400), value: 0)]
        var total = 0.0
        for day in sorted {
            total += day.absProfit
            result.append(CurvePoint(date: day.day, value: total))
        }
        return result
    }

    static func mergeTrades(_ old: [Trade], _ new: [Trade]) -> [Trade] {
        var byID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for trade in new { byID[trade.id] = trade }
        return byID.values.sorted { $0.id > $1.id }
    }
}

struct Snapshot: Codable, Sendable {
    var config: BotConfig
    var profit: Profit
    var wallet: Wallet
    var positions: [Trade]
    var performance: [PairPerformance]
    var daily: [DailyProfit]
    var history: TradePage
    var fetchedAt: Date
}

struct ServerProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var address: URL
    var username: String
}

struct Tokens: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
}

struct Candle: Identifiable, Sendable {
    var date: Date
    var open: Double
    var high: Double
    var low: Double
    var close: Double
    var volume: Double
    var id: Date { date }
}

enum JSONValue: Decodable, Sendable {
    case number(Double), text(String), other
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) { self = .number(number) }
        else if let text = try? container.decode(String.self) { self = .text(text) }
        else { self = .other }
    }
    var number: Double? { if case let .number(value) = self { return value }; return nil }
    var text: String? { if case let .text(value) = self { return value }; return nil }
}

struct CandleResponse: Decodable, Sendable {
    var columns: [String]
    var data: [[JSONValue]]
    var candles: [Candle] {
        guard let o = columns.firstIndex(of: "open"), let h = columns.firstIndex(of: "high"),
              let l = columns.firstIndex(of: "low"), let c = columns.firstIndex(of: "close") else { return [] }
        let time = columns.firstIndex(of: "__date_ts") ?? columns.firstIndex(of: "date")
        let volume = columns.firstIndex(of: "volume")
        return data.compactMap { row in
            guard let time, row.count > max(time, max(o, max(h, max(l, c)))),
                  let open = row[o].number, let high = row[h].number,
                  let low = row[l].number, let close = row[c].number,
                  [open, high, low, close].allSatisfy(\.isFinite) else { return nil }
            let date: Date?
            if let timestamp = row[time].number {
                date = Date(timeIntervalSince1970: timestamp / (timestamp > 100_000_000_000 ? 1_000 : 1))
            } else if let string = row[time].text {
                let parser = ISO8601DateFormatter()
                parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                date = parser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
            } else { date = nil }
            guard let date else { return nil }
            return Candle(date: date, open: open, high: high, low: low, close: close,
                          volume: volume.flatMap { row.indices.contains($0) ? row[$0].number : nil } ?? 0)
        }.sorted { $0.date < $1.date }
    }
}
