import XCTest
@testable import FreqLens

final class PeriodTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-09-19T20:00:00Z")!
    private func trade(_ id: Int, at date: String, pnl: Double?) -> Trade {
        let closed = ISO8601DateFormatter().date(from: date)!
        return Trade(tradeId: id, pair: id % 2 == 0 ? "ETH/USDT" : "BTC/USDT", isOpen: false,
                     amount: 1, stakeAmount: 100, openRate: 100,
                     openTimestamp: closed.addingTimeInterval(-3_600).timeIntervalSince1970 * 1_000,
                     closeTimestamp: closed.timeIntervalSince1970 * 1_000,
                     closeProfitAbs: pnl, closeProfit: pnl.map { $0 / 100 })
    }

    func testUTCWeekIsInclusiveOfTodayAndContainsSevenCalendarDays() throws {
        let filter = TradeTimeFilter(preset: .week)
        let bounds = try XCTUnwrap(filter.bounds(now: now))
        XCTAssertEqual(UTCDate.string(bounds.start), "2026-09-13")
        XCTAssertEqual(UTCDate.string(bounds.end), "2026-09-20")
        XCTAssertTrue(filter.contains(trade(1, at: "2026-09-13T00:00:00Z", pnl: 1), now: now))
        XCTAssertFalse(filter.contains(trade(2, at: "2026-09-12T23:59:59Z", pnl: 1), now: now))
    }

    func testCustomRangeIncludesEndDayButExcludesNextMidnight() {
        let filter = TradeTimeFilter(preset: .custom, start: DailyProfit.parseDay("2026-09-01")!, end: DailyProfit.parseDay("2026-09-03")!)
        XCTAssertTrue(filter.contains(trade(1, at: "2026-09-03T23:59:59Z", pnl: 5), now: now))
        XCTAssertFalse(filter.contains(trade(2, at: "2026-09-04T00:00:00Z", pnl: 5), now: now))
    }

    func testPeriodWinrateIncludesBreakevenAndUsesClosedTradesOnly() throws {
        var open = trade(5, at: "2026-09-18T10:00:00Z", pnl: 999)
        open.isOpen = true
        let trades = [trade(1, at: "2026-09-18T12:00:00Z", pnl: 12),
                      trade(2, at: "2026-09-19T00:00:00Z", pnl: -4),
                      trade(3, at: "2026-09-19T12:00:00Z", pnl: 0),
                      trade(4, at: "2026-08-01T00:00:00Z", pnl: 500), open]
        let report = PeriodReport(trades: trades, filter: TradeTimeFilter(preset: .week), now: now)
        XCTAssertEqual(report.count, 3)
        XCTAssertEqual(report.wins, 1)
        XCTAssertEqual(report.losses, 1)
        XCTAssertEqual(report.draws, 1)
        XCTAssertEqual(try XCTUnwrap(report.winrate), 1 / 3, accuracy: 0.00001)
        XCTAssertEqual(report.profit, 8)
        XCTAssertEqual(report.profitFactor, 3)
        XCTAssertEqual(report.daily.count, 7)
        XCTAssertEqual(report.daily.reduce(0) { $0 + $1.absProfit }, 8)
        XCTAssertEqual(report.performance.reduce(0) { $0 + $1.profitAbs }, 8)
        XCTAssertEqual(report.averageDuration, 3_600)
    }

    func testPeriodIsBasedOnCloseDateEvenWhenEntryIsOutsideWindow() {
        var oldPosition = trade(1, at: "2026-09-19T12:00:00Z", pnl: -8)
        oldPosition.openTimestamp = DailyProfit.parseDay("2025-01-01")!.timeIntervalSince1970 * 1_000
        oldPosition.realizedProfit = -10
        oldPosition.profitAbs = 2
        let report = PeriodReport(trades: [oldPosition], filter: TradeTimeFilter(preset: .today), now: now)
        XCTAssertEqual(report.count, 1)
        XCTAssertEqual(report.profit, -8)
        XCTAssertEqual(report.winrate, 0)
    }

    func testEmptyRangeHasNoWinrateAndAllWinningRangeHasInfiniteFactor() {
        let empty = PeriodReport(trades: [], filter: TradeTimeFilter(preset: .today), now: now)
        XCTAssertNil(empty.winrate)
        XCTAssertNil(empty.profitFactor)
        XCTAssertEqual(empty.profit, 0)
        XCTAssertEqual(empty.daily.count, 1)
        let winning = PeriodReport(trades: [trade(1, at: "2026-09-19T10:00:00Z", pnl: 2)], filter: TradeTimeFilter(preset: .today), now: now)
        XCTAssertEqual(winning.profitFactor, .infinity)
    }

    func testMissingPnlCannotTurnIntoZeroOrIncompleteWinrate() {
        let report = PeriodReport(trades: [trade(1, at: "2026-09-19T10:00:00Z", pnl: nil), trade(2, at: "2026-09-19T11:00:00Z", pnl: 1)],
                                  filter: TradeTimeFilter(preset: .today), now: now)
        XCTAssertEqual(report.missingValues, 1)
        XCTAssertNil(report.profit)
        XCTAssertNil(report.winrate)
        XCTAssertTrue(report.daily.isEmpty)
        XCTAssertTrue(report.performance.isEmpty)
    }

    @MainActor func testSharedFilterRecomputesAllPeriodStatistics() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LensStore(defaults: defaults, forceDemo: true)
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 90)
        store.timeFilter = TradeTimeFilter(preset: .week)
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 21)
        store.timeFilter = TradeTimeFilter(preset: .all)
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 270)
    }
}

@MainActor
func waitForReport(_ store: LensStore) async throws {
    for _ in 0..<500 {
        if !store.isComputingReport && !store.isLoadingCache { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Report did not finish within 5 seconds")
}

extension NetworkTests {
    func testFullHistoryLoadsBeyondFirstPageBeforeReturning() async throws {
        let trades = DemoData.snapshot().history.trades
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let profile = ServerProfile(id: UUID(), name: "Test", address: try APIAddress.normalize("https://example.com"), username: "test")
        StubProtocol.handler.withLock { $0 = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(items.first { $0.name == "offset" }!.value!)!
            let limit = Int(items.first { $0.name == "limit" }!.value!)!
            XCTAssertEqual(items.first { $0.name == "order_by_id" }?.value, "false")
            let slice = Array(trades.dropFirst(offset).prefix(limit == 1 ? 1 : 100))
            let page = TradePage(trades: slice, tradesCount: slice.count, offset: offset, totalTrades: trades.count)
            return (200, try JSONEncoder().encode(page))
        } }
        let client = FreqtradeClient(profile: profile, tokens: Tokens(accessToken: "valid", refreshToken: "valid"), session: URLSession(configuration: config))
        let result = try await client.fullHistory()
        XCTAssertEqual(result.trades.count, 270)
        XCTAssertEqual(Set(result.trades.map(\.id)).count, 270)
    }

    func testTruncatedHistoryFailsRatherThanPublishingPartialStats() async throws {
        let trades = Array(DemoData.snapshot().history.trades.prefix(100))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let profile = ServerProfile(id: UUID(), name: "Test", address: try APIAddress.normalize("https://example.com"), username: "test")
        StubProtocol.handler.withLock { $0 = { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let offset = Int(items.first { $0.name == "offset" }!.value!)!
            let slice = offset == 0 ? trades : []
            return (200, try JSONEncoder().encode(TradePage(trades: slice, tradesCount: slice.count, offset: offset, totalTrades: 200)))
        } }
        let client = FreqtradeClient(profile: profile, tokens: Tokens(accessToken: "valid", refreshToken: "valid"), session: URLSession(configuration: config))
        do { _ = try await client.fullHistory(); XCTFail("Incomplete history must fail") }
        catch LensError.incompleteHistory { }
    }
}
