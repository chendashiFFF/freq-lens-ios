import Foundation

struct DeletionPlan: Identifiable, Sendable {
    let id = UUID()
    let serverID: UUID?
    let cutoff: Date
    let trades: [Trade]

    init(serverID: UUID?, cutoff: Date, history: TradePage) throws {
        guard history.trades.count == history.totalTrades,
              Set(history.trades.map(\.id)).count == history.totalTrades else { throw LensError.incompleteHistory }
        self.serverID = serverID
        self.cutoff = UTCDate.calendar.startOfDay(for: cutoff)
        self.trades = history.trades.filter {
            !$0.isOpen && $0.closedAt.map { $0 < UTCDate.calendar.startOfDay(for: cutoff) } == true
        }.sorted { ($0.closeTimestamp ?? 0) < ($1.closeTimestamp ?? 0) }
    }
}

enum HistoryDeletionError: LocalizedError {
    case serverChanged, unsafeTrade(Int), unexpectedResponse, unconfirmed
    var errorDescription: String? {
        switch self {
        case .serverChanged: "服务器或预览已变更，请重新预览。"
        case .unsafeTrade(let id): "交易 #\(id) 的状态或日期已变化，或存在未完成委托，已停止删除。"
        case .unexpectedResponse: "服务器返回的删除结果无法确认，已停止。请刷新核对。"
        case .unconfirmed: "删除结果未确认，已停止后续请求。请刷新核对，避免重复操作。"
        }
    }
}

/// Required fields intentionally fail closed on incompatible servers.
struct DeletionTradeStatus: Decodable, Sendable {
    struct Order: Decodable, Sendable { let isOpen: Bool }
    let tradeId: Int
    let pair: String
    let openTimestamp: Double
    let closeTimestamp: Double?
    let isOpen: Bool
    let hasOpenOrders: Bool
    let orders: [Order]

    func permitsDeletion(of expected: Trade, before cutoff: Date) -> Bool {
        tradeId == expected.id && pair == expected.pair && openTimestamp == expected.openTimestamp &&
        closeTimestamp == expected.closeTimestamp && !isOpen && !hasOpenOrders &&
        orders.allSatisfy { !$0.isOpen } &&
        closeTimestamp.map { Date(timeIntervalSince1970: $0 / 1_000) < cutoff } == true
    }
}

struct DeletionResponse: Decodable, Sendable {
    let result: String
    let tradeId: Int
    let cancelOrderCount: Int
}

struct DeletionSummary: Sendable {
    var deleted = 0
    var total: Int
    var stopped = false
    var error: String?
}
