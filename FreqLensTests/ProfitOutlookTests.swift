import XCTest
@testable import FreqLens

final class ProfitOutlookTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-10T12:00:00Z")!
    private func outlook(_ snapshot: Snapshot, filter: TradeTimeFilter = TradeTimeFilter()) -> ProfitOutlook {
        ProfitOutlook(report: PeriodReport(trades: snapshot.history.trades, filter: filter, now: now), snapshot: snapshot, isCached: false)
    }

    func testMonthlyAnnualRatesUseClosedProfitOnlyAndStartingCapital() throws {
        var snapshot = DemoData.snapshot(now: now)
        let result = outlook(snapshot)
        XCTAssertEqual(result.observationDays, 30)
        XCTAssertEqual(try XCTUnwrap(result.monthlyRatio), 2393.43 / 25000, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.annualRatio), 2393.43 / 25000 / 30 * 365, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(result.estimatedTotal), 2679.84, accuracy: 0.001)
        snapshot.positions[0].totalProfitAbs = -10_000
        let loss = outlook(snapshot)
        XCTAssertLessThan(try XCTUnwrap(loss.estimatedTotal), 0)
        XCTAssertEqual(result.monthlyRatio, loss.monthlyRatio)
        XCTAssertEqual(result.annualRatio, loss.annualRatio)
    }

    func testPartialExitIsCountedOnceAndOlderTradesAreIncludedInValuation() throws {
        var trade = DemoData.snapshot(now: now).positions[0]
        trade.openTimestamp = now.addingTimeInterval(-300 * 86400).timeIntervalSince1970 * 1000
        trade.profitAbs = 2
        trade.realizedProfit = -10
        trade.totalProfitAbs = -8
        XCTAssertEqual(ProfitOutlook.currentPositionProfit([trade]), -8)
        trade.totalProfitAbs = nil
        XCTAssertEqual(ProfitOutlook.currentPositionProfit([trade]), -8)
        var snapshot = DemoData.snapshot(now: now)
        snapshot.positions = [trade]
        XCTAssertEqual(try XCTUnwrap(outlook(snapshot).estimatedTotal), 2393.43 - 8, accuracy: 0.001)
    }

    func testMissingValuationCannotBecomeZeroAndInvalidRateIsNotUsed() {
        var snapshot = DemoData.snapshot(now: now)
        snapshot.positions[0].totalProfitAbs = nil
        snapshot.positions[0].realizedProfit = nil
        XCTAssertNil(outlook(snapshot).estimatedTotal)
        snapshot = DemoData.snapshot(now: now)
        snapshot.positions[0].currentRate = nil // Backend may send zero total P&L when pricing failed.
        XCTAssertNil(outlook(snapshot).estimatedTotal)
        snapshot.positions[0].currentRate = .nan
        XCTAssertNil(outlook(snapshot).estimatedTotal)
        snapshot = DemoData.snapshot(now: now)
        snapshot.positions[0].totalProfitAbs = .infinity
        XCTAssertNil(outlook(snapshot).estimatedTotal)
        snapshot = DemoData.snapshot(now: now)
        snapshot.wallet.startingCapital = nil
        XCTAssertNil(outlook(snapshot).annualRatio)
        XCTAssertNotNil(outlook(snapshot).estimatedTotal) // Currency valuation still works.
    }

    func testHistoricalPeriodNeverAddsTodaysPositions() throws {
        let snapshot = DemoData.snapshot(now: now)
        let filter = TradeTimeFilter(preset: .custom, start: UTCDate.parse("2026-10-01")!, end: UTCDate.parse("2026-10-31")!)
        let result = outlook(snapshot, filter: filter)
        XCTAssertEqual(result.observationDays, 31)
        XCTAssertNotNil(result.annualRatio)
        XCTAssertNil(result.estimatedTotal)
        XCTAssertEqual(result.positionNote, "历史区间 · 不叠加当前持仓")
    }

    func testFutureDaysAndDaysBeforeKnownHistoryDoNotDiluteRates() {
        var snapshot = DemoData.snapshot(now: now)
        snapshot.history.trades = Array(snapshot.history.trades.prefix(3))
        let filter = TradeTimeFilter(preset: .custom, start: UTCDate.parse("2026-10-01")!, end: UTCDate.parse("2026-12-31")!)
        // Earliest retained trade opened the preceding evening, so only 2 observed UTC days.
        let report = PeriodReport(trades: snapshot.history.trades, filter: filter, now: now)
        XCTAssertEqual(report.observationDays, 2)
        XCTAssertTrue(report.includesReferenceDay)
        let future = TradeTimeFilter(preset: .custom, start: UTCDate.parse("2026-12-01")!, end: UTCDate.parse("2026-12-31")!)
        let result = outlook(snapshot, filter: future)
        XCTAssertEqual(result.observationDays, 0)
        XCTAssertNil(result.monthlyRatio)
        XCTAssertNil(result.estimatedTotal)
    }

    func testNegativeBreakevenAndNoTradesHaveDistinctRates() {
        XCTAssertEqual(ProfitOutlook.scale(-0.1, days: 30, target: 30), -0.1)
        XCTAssertEqual(ProfitOutlook.scale(0, days: 30, target: 365), 0)
        XCTAssertNil(ProfitOutlook.scale(0.1, days: 0, target: 365))
        XCTAssertNil(ProfitOutlook.scale(.greatestFiniteMagnitude, days: 1, target: 365))
        var snapshot = DemoData.snapshot(now: now)
        snapshot.history.trades = []
        XCTAssertNil(outlook(snapshot).monthlyRatio)
        snapshot.positions = []
        XCTAssertNil(outlook(snapshot).estimatedTotal)
    }

    func testMissingClosedProfitDisablesBothEstimateAndExtrapolation() {
        var snapshot = DemoData.snapshot(now: now)
        snapshot.history.trades[0].closeProfitAbs = nil
        let result = outlook(snapshot)
        XCTAssertNil(result.estimatedTotal)
        XCTAssertNil(result.annualRatio)
    }

    func testCachedSnapshotLabelsEstimateAndCrossDaySnapshotIsNotCurrent() {
        var snapshot = DemoData.snapshot(now: now)
        let report = PeriodReport(trades: snapshot.history.trades, filter: TradeTimeFilter(), now: now)
        let cached = ProfitOutlook(report: report, snapshot: snapshot, isCached: true)
        XCTAssertTrue(cached.isCached)
        XCTAssertNotNil(cached.estimatedTotal)
        snapshot.fetchedAt = now.addingTimeInterval(-86400)
        XCTAssertNil(ProfitOutlook(report: report, snapshot: snapshot, isCached: true).estimatedTotal)
    }
}
