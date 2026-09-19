import XCTest
import Synchronization
@testable import FreqLens

private actor ReportGate {
    private var pending: CheckedContinuation<Void, Never>?
    var waiting: Bool { pending != nil }
    func suspend() async { await withCheckedContinuation { pending = $0 } }
    func release() { pending?.resume(); pending = nil }
}

@MainActor
final class ReportCacheTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: UUID().uuidString)! }

    func testCachedSelectionIsImmediateAndReportReadsDoNotRecompute() async throws {
        let calls = Mutex(0)
        let store = LensStore(defaults: defaults(), forceDemo: true, prewarmReports: false, buildReport: { history, filter, now in
            calls.withLock { $0 += 1 }
            return await ReportWorker.build(history: history, filter: filter, now: now)
        })
        try await waitForReport(store)
        let monthID = try XCTUnwrap(store.report?.id)
        store.timeFilter = TradeTimeFilter(preset: .week)
        XCTAssertTrue(store.isComputingReport)
        XCTAssertEqual(store.reportFilter?.preset, .month)
        XCTAssertEqual(store.report?.id, monthID, "Keep the labelled previous result while preparing")
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 21)
        let start = ContinuousClock.now
        for _ in 0..<50 {
            store.timeFilter = TradeTimeFilter(preset: .month)
            XCTAssertFalse(store.isComputingReport)
            XCTAssertEqual(store.report?.id, monthID)
            store.timeFilter = TradeTimeFilter(preset: .week)
            XCTAssertEqual(store.report?.count, 21)
        }
        let duration = ContinuousClock.now - start
        print("100 cached time-range switches: \(duration)")
        XCTAssertLessThan(duration, .seconds(1))
        XCTAssertEqual(calls.withLock { $0 }, 2)
    }

    func testLateResultCannotOverrideLastSelectionOrBlockMainActor() async throws {
        let gate = ReportGate()
        let store = LensStore(defaults: defaults(), forceDemo: true, prewarmReports: false, buildReport: { history, filter, now in
            if filter.preset == .week { await gate.suspend() }
            // Deliberately ignore cancellation to simulate an already finishing calculation.
            return PeriodReport(trades: history.trades, filter: filter, now: now)
        })
        try await waitForReport(store)
        store.timeFilter = TradeTimeFilter(preset: .week)
        for _ in 0..<100 {
            if await gate.waiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let waiting = await gate.waiting
        XCTAssertTrue(waiting)
        XCTAssertTrue(store.isComputingReport)
        store.timeFilter = TradeTimeFilter(preset: .month)
        XCTAssertFalse(store.isComputingReport, "Cached controls remain usable during another calculation")
        store.timeFilter = TradeTimeFilter(preset: .quarter)
        try await waitForReport(store)
        let lastID = store.report?.id
        await gate.release()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.reportFilter?.preset, .quarter)
        XCTAssertEqual(store.report?.id, lastID)
        XCTAssertEqual(store.report?.count, 270)
    }

    func testPresetPrewarmingAvoidsLoadingOnFirstVisit() async throws {
        let store = LensStore(defaults: defaults(), forceDemo: true)
        try await waitForReport(store)
        // Prewarming runs at utility priority, independently from the displayed report.
        try await Task.sleep(for: .milliseconds(500))
        for preset in [TradeTimeFilter.Preset.today, .week, .quarter, .all] {
            store.timeFilter = TradeTimeFilter(preset: preset)
            XCTAssertFalse(store.isComputingReport)
            XCTAssertEqual(store.reportFilter?.preset, preset)
        }
    }

    func testDiskCacheRestoresOfflineAndIsolatesServers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let a = ServerProfile(id: UUID(), name: "A", address: URL(string: "https://a.example/api/v1")!, username: "test")
        let b = ServerProfile(id: UUID(), name: "B", address: URL(string: "https://b.example/api/v1")!, username: "test")
        let first = DemoData.snapshot()
        var second = first
        second.history.trades = Array(first.history.trades.prefix(3))
        second.history.totalTrades = 3
        for i in second.history.trades.indices { second.history.trades[i].closeProfitAbs = -5 }
        await cache.write(first, id: a.id)
        await cache.write(second, id: b.id)
        let prefs = defaults()
        prefs.set(try JSONEncoder().encode([a, b]), forKey: "profiles")
        prefs.set(a.id.uuidString, forKey: "activeProfile")
        let store = LensStore(defaults: prefs, diskCache: cache)
        XCTAssertTrue(store.isLoadingCache)
        try await waitForReport(store)
        XCTAssertTrue(store.isCached)
        XCTAssertEqual(store.snapshot?.history.totalTrades, 270)
        XCTAssertEqual(store.report?.count, 90)
        store.timeFilter = TradeTimeFilter(preset: .week)
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 21)
        await store.select(b)
        try await waitForReport(store)
        XCTAssertEqual(store.report?.count, 3)
        XCTAssertEqual(store.report?.profit, -15)
        XCTAssertEqual(store.report?.winrate, 0)
        let old = await cache.read(a.id)
        XCTAssertEqual(old?.history.totalTrades, 270)
    }

    func testChangedCachedHistoryInvalidatesPreparedReports() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SnapshotCache(directory: directory)
        let profile = ServerProfile(id: UUID(), name: "A", address: URL(string: "https://a.example/api/v1")!, username: "test")
        var snapshot = DemoData.snapshot()
        await cache.write(snapshot, id: profile.id)
        let store = LensStore(defaults: defaults(), forceDemo: true, diskCache: cache)
        await store.select(profile)
        try await waitForReport(store)
        let original = store.report?.id
        snapshot.history.trades[0].closeProfitAbs = -10_000
        await cache.write(snapshot, id: profile.id)
        await store.select(profile)
        try await waitForReport(store)
        XCTAssertNotEqual(store.report?.id, original)
        XCTAssertLessThan(try XCTUnwrap(store.report?.profit), 0)
    }

    func testIncompleteOrDuplicateHistoryIsNotCachedAsAValidReport() async {
        var history = DemoData.snapshot().history
        history.totalTrades += 1
        let incomplete = await ReportWorker.build(history: history, filter: TradeTimeFilter(), now: Date())
        XCTAssertNil(incomplete)
        history.totalTrades -= 1
        history.trades[0] = history.trades[1]
        let duplicate = await ReportWorker.build(history: history, filter: TradeTimeFilter(), now: Date())
        XCTAssertNil(duplicate)
    }

    func testCacheKeysNormalizePresetsCustomDaysAndUTCMidnight() throws {
        let date = try XCTUnwrap(DailyProfit.parseDay("2026-09-19"))
        let weekA = TradeTimeFilter(preset: .week, start: date, end: date)
        let weekB = TradeTimeFilter(preset: .week, start: .distantPast, end: .distantFuture)
        XCTAssertEqual(PeriodKey(weekA, now: date), PeriodKey(weekB, now: date.addingTimeInterval(100)))
        XCTAssertNotEqual(PeriodKey(weekA, now: date), PeriodKey(weekA, now: date.addingTimeInterval(86_400)))
        let customA = TradeTimeFilter(preset: .custom, start: date, end: date)
        let customB = TradeTimeFilter(preset: .custom, start: date.addingTimeInterval(1), end: date.addingTimeInterval(100))
        XCTAssertEqual(PeriodKey(customA, now: date), PeriodKey(customB, now: date))
    }
}
