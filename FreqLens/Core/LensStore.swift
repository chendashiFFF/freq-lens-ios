import Foundation
import Observation

@Observable @MainActor
final class LensStore {
    private(set) var snapshot: Snapshot? {
        didSet {
            let changed = oldValue?.history.trades != snapshot?.history.trades || oldValue?.history.totalTrades != snapshot?.history.totalTrades
            updateReport(invalidate: changed)
        }
    }
    private(set) var profiles: [ServerProfile] = []
    private(set) var activeID: UUID?
    private(set) var isRefreshing = false
    private(set) var isLoadingHistory = false
    private(set) var isConnecting = false
    private(set) var isCached = false
    private(set) var isLoadingCache = false
    private(set) var isComputingReport = false
    private(set) var report: PeriodReport?
    private(set) var reportFilter: TradeTimeFilter?
    private(set) var isDeletingHistory = false
    private(set) var deletionCompleted = 0
    private(set) var deletionTotal = 0
    @ObservationIgnored private var stopDeletionRequested = false
    @ObservationIgnored private var pendingDeletionID: UUID?
    var errorMessage: String?
    var historyError: String?
    var connectionError: String?
    var privacyMode = false
    var timeFilter = TradeTimeFilter() {
        didSet {
            guard oldValue != timeFilter else { return }
            if let data = try? JSONEncoder().encode(timeFilter) { defaults.set(data, forKey: "timeFilter") }
            updateReport()
        }
    }
    private var client: FreqtradeClient?
    private var generation = UUID()
    private var nextHistoryOffset = 0
    private var paginationEnded = false
    private var defaults: UserDefaults
    @ObservationIgnored private let diskCache: SnapshotCache
    @ObservationIgnored private var cacheLoadTask: Task<Void, Never>?
    @ObservationIgnored private var reportTask: Task<Void, Never>?
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var reports: [PeriodKey: PeriodReport] = [:]
    @ObservationIgnored private var reportDay: Date?
    @ObservationIgnored private var reportKey: PeriodKey?
    @ObservationIgnored private var reportRevision = UUID()
    @ObservationIgnored private var historyRevision = UUID()
    @ObservationIgnored private let buildReport: @Sendable (TradePage, TradeTimeFilter, Date) async -> PeriodReport?
    @ObservationIgnored private let prewarmReports: Bool
    @ObservationIgnored private let clientFactory: @Sendable (ServerProfile, Tokens) -> FreqtradeClient

    var isDemo: Bool { activeID == nil }
    var activeProfile: ServerProfile? { profiles.first { $0.id == activeID } }
    var canLoadHistory: Bool {
        !isDemo && !paginationEnded && nextHistoryOffset < (snapshot?.history.totalTrades ?? 0)
    }
    var isStale: Bool { isCached || errorMessage != nil }
    init(defaults: UserDefaults = .standard, forceDemo: Bool = false,
         diskCache: SnapshotCache = SnapshotCache(), prewarmReports: Bool = true,
         clientFactory: @escaping @Sendable (ServerProfile, Tokens) -> FreqtradeClient = { FreqtradeClient(profile: $0, tokens: $1) },
         buildReport: @escaping @Sendable (TradePage, TradeTimeFilter, Date) async -> PeriodReport? = ReportWorker.build) {
        self.defaults = defaults
        self.diskCache = diskCache
        self.buildReport = buildReport
        self.prewarmReports = prewarmReports
        self.clientFactory = clientFactory
        if !forceDemo, let data = defaults.data(forKey: "timeFilter"), let filter = try? JSONDecoder().decode(TradeTimeFilter.self, from: data) {
            timeFilter = filter
        }
        if let data = defaults.data(forKey: "profiles") {
            profiles = (try? JSONDecoder().decode([ServerProfile].self, from: data)) ?? []
        }
        if !forceDemo, let saved = defaults.string(forKey: "activeProfile"),
           let id = UUID(uuidString: saved), let profile = profiles.first(where: { $0.id == id }) {
            activeID = id
            if let tokens = TokenVault.read(id) { client = clientFactory(profile, tokens) }
            else { errorMessage = "登录信息已失效，请重新连接服务器。" }
        } else { snapshot = DemoData.snapshot() }
        if let activeID { restoreCache(activeID) }
        else { updateReport(invalidate: true) }
    }

    func refresh() async {
        await cacheLoadTask?.value
        guard !Task.isCancelled else { return }
        guard !isRefreshing, !isLoadingHistory, !isDeletingHistory else { return }
        if isDemo { snapshot = DemoData.snapshot(); return }
        guard let client else { return }
        let revision = generation
        isRefreshing = true
        defer { if revision == generation { isRefreshing = false } }
        do {
            let fresh = try await client.snapshot()
            guard revision == generation, !Task.isCancelled else { return }
            // Reload the loaded window so server-side removals or old positions closing
            // cannot leave ghost rows or cause offset pagination to skip trades.
            nextHistoryOffset = fresh.history.trades.count
            paginationEnded = false
            snapshot = fresh
            isCached = false
            errorMessage = nil
            if let activeID { await diskCache.write(fresh, id: activeID) }
        } catch {
            guard revision == generation, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func connect(name: String, address: String, username: String, password: String) async -> Bool {
        guard !isConnecting, !isDeletingHistory else { return false }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }
        do {
            let url = try APIAddress.normalize(address)
            let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let existing = profiles.first { $0.address == url && $0.username == username }
            var profile = ServerProfile(id: existing?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: url, username: username)
            let tokens = try await FreqtradeClient.login(profile: profile, password: password)
            let connection = clientFactory(profile, tokens)
            let fresh = try await connection.snapshot()
            try Task.checkCancellation()
            try TokenVault.save(tokens, for: profile.id)
            if profile.name.isEmpty { profile.name = fresh.config.botName }
            profiles.removeAll { $0.id == profile.id }
            profiles.append(profile)
            generation = UUID()
            clearReports()
            cacheLoadTask?.cancel()
            isLoadingCache = false
            activeID = profile.id
            client = connection
            snapshot = fresh
            isRefreshing = false
            isLoadingHistory = false
            isCached = false
            errorMessage = nil
            historyError = nil
            nextHistoryOffset = fresh.history.trades.count
            paginationEnded = false
            persistProfiles()
            await diskCache.write(fresh, id: profile.id)
            return true
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    func select(_ profile: ServerProfile?) async {
        guard !isDeletingHistory else { return }
        pendingDeletionID = nil
        generation = UUID()
        clearReports()
        cacheLoadTask?.cancel()
        cacheLoadTask = nil
        isLoadingCache = false
        activeID = profile?.id
        errorMessage = nil
        historyError = nil
        connectionError = nil
        isRefreshing = false
        isLoadingHistory = false
        isCached = false
        paginationEnded = false
        if let profile {
            snapshot = nil
            nextHistoryOffset = 0
            restoreCache(profile.id)
            if let tokens = TokenVault.read(profile.id) { client = clientFactory(profile, tokens) }
            else { client = nil; errorMessage = "登录信息已失效，请重新连接服务器。" }
        } else {
            client = nil
            snapshot = DemoData.snapshot()
            nextHistoryOffset = 0
        }
        persistProfiles()
        await refresh()
    }

    func loadMoreHistory() async {
        guard canLoadHistory, !isLoadingHistory, !isRefreshing, let client else { return }
        let revision = generation
        isLoadingHistory = true
        historyError = nil
        defer { if generation == revision { isLoadingHistory = false } }
        do {
            let page = try await client.history(offset: nextHistoryOffset)
            guard revision == generation, !Task.isCancelled else { return }
            snapshot?.history.trades = Metrics.mergeTrades(snapshot?.history.trades ?? [], page.trades)
            snapshot?.history.totalTrades = page.totalTrades
            nextHistoryOffset += page.trades.count
            paginationEnded = page.trades.isEmpty
            if let snapshot, let activeID { await diskCache.write(snapshot, id: activeID) }
        } catch {
            if revision == generation { historyError = error.localizedDescription }
        }
    }

    func candles(for trade: Trade) async throws -> [Candle] {
        if isDemo { return DemoData.candles(for: trade) }
        guard let client else { throw LensError.authentication }
        return try await client.candles(pair: trade.pair, timeframe: snapshot?.config.timeframe ?? "\(trade.timeframe ?? 5)m")
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "profiles") }
        defaults.set(activeID?.uuidString, forKey: "activeProfile")
    }

    private func restoreCache(_ id: UUID) {
        let revision = generation
        let cache = diskCache
        isLoadingCache = true
        cacheLoadTask = Task { [weak self] in
            let saved = await cache.read(id)
            guard let self, !Task.isCancelled, self.generation == revision, self.activeID == id else { return }
            self.isLoadingCache = false
            if self.snapshot == nil, let saved {
                self.snapshot = saved
                self.isCached = true
                self.nextHistoryOffset = saved.history.trades.count
            }
        }
    }

    private func clearReports() {
        reportTask?.cancel()
        warmTask?.cancel()
        warmTask = nil
        reports.removeAll()
        report = nil
        reportFilter = nil
        reportKey = nil
        reportRevision = UUID()
        historyRevision = UUID()
        isComputingReport = false
    }

    /// A selection never fetches data. It uses a prepared result immediately,
    /// or computes from the last complete snapshot away from the UI thread.
    private func updateReport(invalidate: Bool = false, now: Date = Date()) {
        let day = UTCDate.calendar.startOfDay(for: now)
        if invalidate || reportDay != day {
            reports.removeAll()
            warmTask?.cancel()
            warmTask = nil
            historyRevision = UUID()
            reportKey = nil
            reportDay = day
        }
        guard let history = snapshot?.history else { clearReports(); return }
        let filter = timeFilter
        let key = PeriodKey(filter, now: now)
        if reportKey == key, report != nil, !isComputingReport { reportFilter = filter; return }
        reportTask?.cancel()
        reportRevision = UUID()
        let revision = reportRevision
        if let cached = reports[key] {
            report = cached
            reportFilter = filter
            reportKey = key
            isComputingReport = false
            return
        }
        isComputingReport = true
        let builder = buildReport
        reportTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let prepared = await builder(history, filter, now)
            guard let self, !Task.isCancelled, self.reportRevision == revision else { return }
            self.report = prepared
            self.reportFilter = prepared == nil ? nil : filter
            self.reportKey = key
            self.isComputingReport = false
            if let prepared {
                // Bound custom-date entries while retaining the selected result.
                if self.reports.count >= 12 { self.reports.removeAll() }
                self.reports[key] = prepared
                self.warmReports(history: history, now: now)
            }
        }
    }

    private func warmReports(history: TradePage, now: Date) {
        guard prewarmReports, warmTask == nil else { return }
        let presets = TradeTimeFilter.Preset.allCases.filter { $0 != .custom }
        guard presets.contains(where: { reports[PeriodKey(TradeTimeFilter(preset: $0), now: now)] == nil }) else { return }
        let revision = historyRevision
        warmTask = Task { [weak self] in
            let prepared = await ReportWorker.warm(history: history, now: now)
            guard let self, !Task.isCancelled, self.historyRevision == revision else { return }
            self.reports.merge(prepared, uniquingKeysWith: { existing, _ in existing })
            self.warmTask = nil
        }
    }

    func report(for filter: TradeTimeFilter) async -> PeriodReport? {
        guard let history = snapshot?.history else { return nil }
        let now = Date()
        let key = PeriodKey(filter, now: now)
        if let cached = reports[key] { return cached }
        let revision = historyRevision
        let prepared = await buildReport(history, filter, now)
        guard !Task.isCancelled, revision == historyRevision else { return nil }
        if let prepared {
            if reports.count >= 12 { reports.removeAll() }
            reports[key] = prepared
        }
        return prepared
    }

    func previewDeletion(before cutoff: Date) async throws -> DeletionPlan {
        guard !isDeletingHistory, cutoff <= Date() else { throw HistoryDeletionError.serverChanged }
        let id = activeID
        let revision = generation
        let history: TradePage
        if isDemo, let snapshot { history = snapshot.history }
        else if let client { history = try await client.fullHistory() }
        else { throw LensError.authentication }
        try Task.checkCancellation()
        guard revision == generation, id == activeID else { throw HistoryDeletionError.serverChanged }
        let plan = try DeletionPlan(serverID: id, cutoff: cutoff, history: history)
        pendingDeletionID = plan.id
        return plan
    }

    func stopDeletingHistory() { stopDeletionRequested = true }

    func deleteHistory(_ plan: DeletionPlan) async -> DeletionSummary {
        var result = DeletionSummary(total: plan.trades.count)
        guard !isDeletingHistory, !isConnecting, let id = activeID, let client,
              plan.serverID == id, pendingDeletionID == plan.id, !plan.trades.isEmpty else {
            result.error = HistoryDeletionError.serverChanged.localizedDescription
            return result
        }
        // Invalidate the preview immediately, so a double tap cannot replay it.
        pendingDeletionID = nil
        isDeletingHistory = true
        deletionCompleted = 0
        deletionTotal = plan.trades.count
        stopDeletionRequested = false
        generation = UUID()
        cacheLoadTask?.cancel()
        isLoadingCache = false
        isRefreshing = false
        snapshot = nil
        clearReports()
        // Remove the disk snapshot before the first mutation, including if the
        // app is suspended or killed partway through this non-atomic batch.
        do { try await diskCache.remove(id) }
        catch {
            isDeletingHistory = false
            result.error = "无法清理本机缓存，尚未执行删除。请解锁设备后重试。"
            return result
        }
        for trade in plan.trades {
            if stopDeletionRequested || Task.isCancelled { result.stopped = true; break }
            do {
                try await client.deleteClosedTrade(trade, before: plan.cutoff)
                result.deleted += 1
                deletionCompleted = result.deleted
            } catch {
                result.error = error.localizedDescription
                break
            }
        }
        do {
            let fresh = try await client.snapshot()
            snapshot = fresh
            nextHistoryOffset = fresh.history.trades.count
            paginationEnded = false
            isCached = false
            errorMessage = nil
            await diskCache.write(fresh, id: id)
        } catch {
            errorMessage = "删除后的数据同步失败，请刷新核对。"
            result.error = [result.error, errorMessage].compactMap { $0 }.joined(separator: "\n")
        }
        isDeletingHistory = false
        return result
    }
}
