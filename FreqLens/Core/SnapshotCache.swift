import Foundation

/// Serial disk access outside the main actor; files remain isolated per server.
actor SnapshotCache {
    private let directory: URL?

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        self.directory = directory
    }

    func read(_ id: UUID) -> Snapshot? {
        guard let url = url(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    func write(_ snapshot: Snapshot, id: UUID) {
        guard let directory, let url = url(id), let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func url(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("snapshot-\(id.uuidString).json")
    }

    func remove(_ id: UUID) throws {
        if let url = url(id), FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

enum ReportWorker {
    static func build(history: TradePage, filter: TradeTimeFilter, now: Date) async -> PeriodReport? {
        let work = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  history.trades.count == history.totalTrades,
                  Set(history.trades.map(\.id)).count == history.totalTrades else { return nil as PeriodReport? }
            return PeriodReport(trades: history.trades, filter: filter, now: now)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    static func warm(history: TradePage, now: Date) async -> [PeriodKey: PeriodReport] {
        let work = Task.detached(priority: .utility) {
            var reports: [PeriodKey: PeriodReport] = [:]
            for preset in TradeTimeFilter.Preset.allCases where preset != .custom {
                guard !Task.isCancelled else { break }
                let filter = TradeTimeFilter(preset: preset)
                reports[PeriodKey(filter, now: now)] = PeriodReport(trades: history.trades, filter: filter, now: now)
            }
            return reports
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }
}
