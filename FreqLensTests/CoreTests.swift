import XCTest
import Synchronization
@testable import FreqLens

final class CoreTests: XCTestCase {
    func testReturnUsesStartingCapitalAcrossSelectedPeriodsAndDrawdowns() throws {
        let data = DemoData.snapshot(now: UTCDate.parse("2026-09-20")!)
        let report = PeriodReport(trades: data.history.trades, filter: TradeTimeFilter(preset: .month), now: data.fetchedAt)
        let ratio = try XCTUnwrap(Metrics.returnRatio(profit: report.profit, startingCapital: data.wallet.startingCapital))
        XCTAssertEqual(ratio, 0.0957372, accuracy: 0.0000001)
        XCTAssertNotEqual(ratio, data.profit.profitAllRatio)
        let days = [DailyProfit(date: "2026-09-01", absProfit: 100, tradeCount: 1),
                    DailyProfit(date: "2026-09-02", absProfit: -150, tradeCount: 1)]
        let returns = Metrics.curve(days, limit: 2).compactMap { Metrics.returnRatio(profit: $0.value, startingCapital: 1_000) }
        XCTAssertEqual(returns, [0, 0.1, -0.05])
        XCTAssertEqual(Metrics.returnRatio(profit: 0, startingCapital: 1_000), 0)
    }

    func testUnavailableOrInvalidCapitalNeverProducesAnEstimatedReturn() {
        for capital: Double? in [nil, 0, -1, .nan, .infinity] {
            XCTAssertNil(Metrics.returnRatio(profit: 100, startingCapital: capital))
        }
        for profit: Double? in [nil, .nan, .infinity] {
            XCTAssertNil(Metrics.returnRatio(profit: profit, startingCapital: 1_000))
        }
        XCTAssertNil(Metrics.returnRatio(profit: .greatestFiniteMagnitude, startingCapital: .leastNonzeroMagnitude))
    }

    func testAddressNormalizationAndRejection() throws {
        XCTAssertEqual(try APIAddress.normalize(" http://localhost:8080/ ").absoluteString, "http://localhost:8080/api/v1")
        XCTAssertEqual(try APIAddress.normalize("https://example.com/bot/api/v1/").absoluteString, "https://example.com/bot/api/v1")
        XCTAssertEqual(try APIAddress.normalize("https://example.com/bot").absoluteString, "https://example.com/bot/api/v1")
        for value in ["example.com", "ftp://example.com", "https://user:password@example.com", "https://example.com?token=x", "https://example.com#fragment"] {
            XCTAssertThrowsError(try APIAddress.normalize(value))
        }
    }

    func testCumulativeRealizedCurveSortsAndResetsAtSelectedPeriod() {
        let days = [DailyProfit(date: "2026-09-03", absProfit: -4, tradeCount: 1),
                    DailyProfit(date: "2026-09-01", absProfit: 100, tradeCount: 1),
                    DailyProfit(date: "2026-09-02", absProfit: 10, tradeCount: 1)]
        XCTAssertEqual(Metrics.curve(days, limit: 2).map(\.value), [0, 10, 6])
        XCTAssertTrue(Metrics.curve([], limit: 30).isEmpty)
    }

    func testDemoTotalsAreDerivedFromTrades() {
        let data = DemoData.snapshot()
        let closed = data.history.trades.reduce(0) { $0 + ($1.pnl ?? 0) }
        XCTAssertEqual(data.profit.profitClosedCoin, closed, accuracy: 0.0001)
        XCTAssertEqual(data.daily.reduce(0) { $0 + $1.absProfit }, closed, accuracy: 0.0001)
        XCTAssertEqual(data.wallet.botValue, 25_000 + data.profit.profitAllCoin, accuracy: 0.0001)
        XCTAssertEqual(data.profit.winningTrades + data.profit.losingTrades, data.profit.closedTradeCount)
    }

    func testPartialExitUsesTotalTradeProfitAndNullIsNotZero() throws {
        let json = #"{"trade_id":17,"pair":"BTC/USDT:USDT","is_open":true,"is_short":false,"amount":0.1,"stake_amount":50,"open_rate":100,"open_timestamp":1720000000000,"profit_abs":2,"profit_ratio":0.04,"total_profit_abs":-8,"total_profit_ratio":-0.16,"realized_profit":-10}"#
        let trade = try FreqtradeClient.decoder().decode(Trade.self, from: Data(json.utf8))
        XCTAssertEqual(trade.pnl, -8)
        XCTAssertEqual(trade.ratio, -0.16)
        XCTAssertEqual(trade.openedAt.timeIntervalSince1970, 1720000000)
        XCTAssertEqual(Fmt.number(nil), "—")
        XCTAssertEqual(Fmt.percent(nil), "—")
    }

    func testPaginationDeduplicatesAndKeepsLatest() {
        let trades = DemoData.snapshot().history.trades
        var updated = trades[2]
        updated.closeProfitAbs = 123
        let result = Metrics.mergeTrades(Array(trades.prefix(3)), [updated, trades[3]])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.first { $0.id == updated.id }?.pnl, 123)
    }

    func testNullRiskMetricsDecode() throws {
        let data = DemoData.snapshot().profit
        let encoded = try JSONEncoder().encode(data)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json["profitFactor"] = NSNull()
        json["sharpe"] = NSNull()
        let decoded = try FreqtradeClient.decoder().decode(Profit.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.profitFactor)
        XCTAssertNil(decoded.sharpe)
    }

    func testCandleColumnsAreResolvedByNameAndMalformedRowsSkipped() throws {
        let json = #"{"columns":["close","__date_ts","volume","high","open","low","enter_long"],"data":[[11,1720000000000,40,12,10,9,true],[12,null,40,13,11,10,null],[13,1720000300000,50,14,12,11,false],[5]]}"#
        let response = try FreqtradeClient.decoder().decode(CandleResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.candles.count, 2)
        XCTAssertEqual(response.candles[0].open, 10)
        XCTAssertEqual(response.candles[0].close, 11)
        XCTAssertEqual(response.candles[0].date.timeIntervalSince1970, 1720000000)
    }

    func testAllDataRoutesUseGetAndEncodePair() async throws {
        let profile = ServerProfile(id: UUID(), name: "Test", address: try APIAddress.normalize("https://example.com"), username: "test")
        let client = FreqtradeClient(profile: profile, tokens: Tokens(accessToken: "test", refreshToken: "test"))
        for endpoint in ReadEndpoint.allCases {
            let request = try await client.makeRequest(endpoint, query: ["pair": "BTC/USDT:USDT"], token: "test")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "BTC/USDT:USDT")
            XCTAssertFalse(["forceexit", "forceenter", "start", "stop", "reload_config"].contains(endpoint.path))
        }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let handler = Mutex<(@Sendable (URLRequest) throws -> (Int, Data))?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let action = Self.handler.withLock { $0 }
            let (status, data) = try XCTUnwrap(action)(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class NetworkTests: XCTestCase {
    struct Ping: Codable, Sendable { let value: Int }
    private func makeClient(id: UUID = UUID()) throws -> FreqtradeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let profile = ServerProfile(id: id, name: "Test", address: try APIAddress.normalize("https://example.com"), username: "test")
        return FreqtradeClient(profile: profile, tokens: Tokens(accessToken: "expired", refreshToken: "refresh"), session: URLSession(configuration: config))
    }
    override func tearDown() { StubProtocol.handler.withLock { $0 = nil }; super.tearDown() }

    func testTransientGatewayFailureRetriesGet() async throws {
        let count = Mutex(0)
        StubProtocol.handler.withLock { $0 = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            let attempt = count.withLock { $0 += 1; return $0 }
            return (attempt == 1 ? 502 : 200, Data(#"{"value":42}"#.utf8))
        } }
        let result: Ping = try await makeClient().get(.profit)
        XCTAssertEqual(result.value, 42)
        XCTAssertEqual(count.withLock { $0 }, 2)
    }

    func testConcurrentExpiredRequestsShareOneRefresh() async throws {
        let refreshes = Mutex(0)
        let id = UUID()
        defer { TokenVault.delete(id) }
        StubProtocol.handler.withLock { $0 = { request in
            if request.url?.lastPathComponent == "refresh" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refresh")
                refreshes.withLock { $0 += 1 }
                return (200, Data(#"{"access_token":"renewed"}"#.utf8))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer expired" { return (401, Data()) }
            return (200, Data(#"{"value":7}"#.utf8))
        } }
        let client = try makeClient(id: id)
        async let a: Ping = client.get(.profit)
        async let b: Ping = client.get(.balance)
        async let c: Ping = client.get(.status)
        let values = try await [a, b, c]
        XCTAssertEqual(values.map(\.value), [7, 7, 7])
        XCTAssertEqual(refreshes.withLock { $0 }, 1)
    }

    func testUnauthorizedRefreshSurfacesAuthenticationFailure() async throws {
        StubProtocol.handler.withLock { $0 = { _ in (401, Data()) } }
        do {
            let _: Ping = try await makeClient().get(.profit)
            XCTFail("Expected failure")
        } catch LensError.authentication { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
