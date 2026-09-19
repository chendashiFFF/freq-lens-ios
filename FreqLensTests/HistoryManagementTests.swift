import XCTest
import Synchronization
@testable import FreqLens

final class HistoryManagementTests: XCTestCase {
    func testCalendarIncludesFullLeapMonthAndDoesNotChangeSharedFilter() async throws {
        let february = DailyProfit.parseDay("2024-02-15")!
        let filter = CalendarMonth.filter(february)
        let report = PeriodReport(trades: [], filter: filter)
        XCTAssertEqual(report.daily.count, 29)
        XCTAssertEqual(report.daily.first?.date, "2024-02-01")
        XCTAssertEqual(report.daily.last?.date, "2024-02-29")
        let december = CalendarMonth.filter(DailyProfit.parseDay("2025-12-31")!)
        XCTAssertEqual(UTCDate.string(december.bounds()!.end), "2026-01-01")
    }

    @MainActor func testMonthlyReportUsesCompleteHistoryIndependentlyOfSharedRange() async throws {
        let store = LensStore(defaults: UserDefaults(suiteName: UUID().uuidString)!, forceDemo: true)
        try await waitForReport(store)
        store.timeFilter = TradeTimeFilter(preset: .today)
        try await waitForReport(store)
        let selectedID = store.report?.id
        let month = UTCDate.calendar.date(byAdding: .month, value: -1, to: Date())!
        let monthly = await store.report(for: CalendarMonth.filter(month))
        XCTAssertGreaterThan(monthly?.count ?? 0, 3)
        XCTAssertEqual(store.timeFilter.preset, .today)
        XCTAssertEqual(store.report?.id, selectedID)
    }

    func testDeletionPlanExcludesOpenTradesAndCutoffDay() throws {
        let cutoff = DailyProfit.parseDay("2026-07-01")!
        let old = Self.trade(1)
        var atBoundary = old; atBoundary.tradeId = 2; atBoundary.closeTimestamp = cutoff.timeIntervalSince1970 * 1_000
        var open = old; open.tradeId = 3; open.isOpen = true
        var missing = old; missing.tradeId = 4; missing.closeTimestamp = nil
        let page = TradePage(trades: [old, atBoundary, open, missing], tradesCount: 4, offset: 0, totalTrades: 4)
        let plan = try DeletionPlan(serverID: UUID(), cutoff: cutoff.addingTimeInterval(50), history: page)
        XCTAssertEqual(plan.trades.map(\.id), [1])
        XCTAssertEqual(plan.cutoff, cutoff)
        var invalid = page; invalid.totalTrades = 5
        XCTAssertThrowsError(try DeletionPlan(serverID: UUID(), cutoff: cutoff, history: invalid))
    }

    static func trade(_ id: Int = 1) -> Trade {
        Trade(tradeId: id, pair: "BTC/USDT", isOpen: false, amount: 1, stakeAmount: 100, openRate: 100,
              openTimestamp: DailyProfit.parseDay("2026-05-31")!.timeIntervalSince1970 * 1_000,
              closeTimestamp: DailyProfit.parseDay("2026-06-01")!.timeIntervalSince1970 * 1_000,
              closeProfitAbs: 1)
    }
    static func status(_ trade: Trade, open: Bool = false, pendingOrder: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["trade_id": trade.id, "pair": trade.pair,
            "open_timestamp": trade.openTimestamp, "close_timestamp": trade.closeTimestamp!,
            "is_open": open, "has_open_orders": pendingOrder, "orders": [["is_open": pendingOrder]]])
    }
}

extension NetworkTests {
    private func deletionClient(id: UUID = UUID()) -> FreqtradeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let profile = ServerProfile(id: id, name: "Fixture", address: URL(string: "https://example.com/api/v1")!, username: "test")
        return FreqtradeClient(profile: profile, tokens: Tokens(accessToken: "valid", refreshToken: "refresh"), session: URLSession(configuration: config))
    }

    func testHistoricalDeletionChecksStatusBeforeOnlyTheApprovedDelete() async throws {
        let trade = HistoryManagementTests.trade()
        let requests = Mutex<[String]>([])
        StubProtocol.handler.withLock { $0 = { request in
            requests.withLock { $0.append("\(request.httpMethod!) \(request.url!.path)") }
            if request.httpMethod == "GET" { return (200, try HistoryManagementTests.status(trade)) }
            return (200, Data(#"{"result":"success","trade_id":1,"cancel_order_count":0}"#.utf8))
        } }
        try await deletionClient().deleteClosedTrade(trade, before: DailyProfit.parseDay("2026-07-01")!)
        XCTAssertEqual(requests.withLock { $0 }, ["GET /api/v1/trade/1", "DELETE /api/v1/trades/1"])
    }

    func testOpenPositionOrPendingOrdersNeverReachDelete() async throws {
        for state in [(true, false), (false, true)] {
            let methods = Mutex<[String]>([])
            let trade = HistoryManagementTests.trade()
            StubProtocol.handler.withLock { $0 = { request in
                methods.withLock { $0.append(request.httpMethod!) }
                return (200, try HistoryManagementTests.status(trade, open: state.0, pendingOrder: state.1))
            } }
            do { try await deletionClient().deleteClosedTrade(trade, before: Date()); XCTFail("Unsafe trade must be refused") }
            catch HistoryDeletionError.unsafeTrade { }
            XCTAssertEqual(methods.withLock { $0 }, ["GET"])
        }
    }

    func testChangedTradeIdentityNeverReachesDelete() async throws {
        let trade = HistoryManagementTests.trade()
        var changed = trade; changed.openTimestamp += 1
        let status = try HistoryManagementTests.status(changed)
        let methods = Mutex<[String]>([])
        StubProtocol.handler.withLock { $0 = { request in
            methods.withLock { $0.append(request.httpMethod!) }
            return (200, status)
        } }
        do { try await deletionClient().deleteClosedTrade(trade, before: Date()); XCTFail("Changed identity must be refused") }
        catch HistoryDeletionError.unsafeTrade { }
        XCTAssertEqual(methods.withLock { $0 }, ["GET"])
    }

    func testUncertainDeleteIsNotRetried() async throws {
        for status in [502, 0] {
            let deletes = Mutex(0)
            let trade = HistoryManagementTests.trade()
            StubProtocol.handler.withLock { $0 = { request in
                if request.httpMethod == "GET" { return (200, try HistoryManagementTests.status(trade)) }
                deletes.withLock { $0 += 1 }
                if status == 0 { throw URLError(.timedOut) }
                return (status, Data())
            } }
            do { try await deletionClient().deleteClosedTrade(trade, before: Date()); XCTFail("Unconfirmed mutation must surface") }
            catch { }
            XCTAssertEqual(deletes.withLock { $0 }, 1)
        }
    }

    func testMissingSafetyFieldsAndUnexpectedResponseFailClosed() async throws {
        let trade = HistoryManagementTests.trade()
        let deletes = Mutex(0)
        StubProtocol.handler.withLock { $0 = { request in
            if request.httpMethod == "DELETE" { deletes.withLock { $0 += 1 } }
            return (200, Data(#"{"trade_id":1,"is_open":false}"#.utf8))
        } }
        do { try await deletionClient().deleteClosedTrade(trade, before: Date()); XCTFail("Required status fields cannot be omitted") }
        catch { }
        XCTAssertEqual(deletes.withLock { $0 }, 0)
        StubProtocol.handler.withLock { $0 = { request in
            if request.httpMethod == "GET" { return (200, try HistoryManagementTests.status(trade)) }
            return (200, Data(#"{"result":"success","trade_id":999,"cancel_order_count":0}"#.utf8))
        } }
        do { try await deletionClient().deleteClosedTrade(trade, before: Date()); XCTFail("Unexpected response must not be reported as success") }
        catch HistoryDeletionError.unexpectedResponse { }
    }

    @MainActor func testBatchStopsAfterFailureAndRefreshesConfirmedDeletion() async throws {
        let id = UUID()
        defer { TokenVault.delete(id) }
        let profile = ServerProfile(id: id, name: "Fixture", address: URL(string: "https://example.com/api/v1")!, username: "test")
        let prefs = UserDefaults(suiteName: UUID().uuidString)!
        prefs.set(try JSONEncoder().encode([profile]), forKey: "profiles")
        prefs.set(id.uuidString, forKey: "activeProfile")
        try TokenVault.save(Tokens(accessToken: "test", refreshToken: "test"), for: id)
        let trades = Mutex([HistoryManagementTests.trade(1), HistoryManagementTests.trade(2), HistoryManagementTests.trade(3)])
        let deletes = Mutex<[Int]>([])
        let demo = DemoData.snapshot()
        StubProtocol.handler.withLock { $0 = { request in
            let path = request.url!.path
            if request.httpMethod == "DELETE" {
                let id = Int(request.url!.lastPathComponent)!
                deletes.withLock { $0.append(id) }
                if id == 2 { return (500, Data()) }
                trades.withLock { $0.removeAll { $0.id == id } }
                return (200, try JSONSerialization.data(withJSONObject: ["result":"success", "trade_id":id, "cancel_order_count":0]))
            }
            if path.contains("/trade/") { return (200, try HistoryManagementTests.status(HistoryManagementTests.trade(Int(request.url!.lastPathComponent)!))) }
            switch request.url!.lastPathComponent {
            case "trades":
                let current = trades.withLock { $0 }
                return (200, try JSONEncoder().encode(TradePage(trades: current, tradesCount: current.count, offset: 0, totalTrades: current.count)))
            case "show_config": return (200, try JSONEncoder().encode(demo.config))
            case "profit": return (200, try JSONEncoder().encode(demo.profit))
            case "balance": return (200, try JSONEncoder().encode(demo.wallet))
            case "status": return (200, Data("[]".utf8))
            case "performance": return (200, Data("[]".utf8))
            case "daily": return (200, try JSONEncoder().encode(DailyResponse(data: [], stakeCurrency: "USDT")))
            default: throw URLError(.unsupportedURL)
            }
        } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let store = LensStore(defaults: prefs, diskCache: cache, clientFactory: { profile, tokens in
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
            return FreqtradeClient(profile: profile, tokens: tokens, session: URLSession(configuration: config))
        })
        let plan = try await store.previewDeletion(before: Date())
        XCTAssertEqual(plan.trades.count, 3)
        let result = await store.deleteHistory(plan)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(deletes.withLock { $0 }, [1, 2])
        XCTAssertEqual(store.snapshot?.history.trades.map(\.id), [2, 3])
        let saved = await cache.read(id)
        XCTAssertEqual(saved?.history.trades.map(\.id), [2, 3])
        let duplicate = await store.deleteHistory(plan)
        XCTAssertEqual(duplicate.deleted, 0)
        XCTAssertEqual(deletes.withLock { $0 }, [1, 2], "A confirmed plan may only be consumed once")
    }
}
