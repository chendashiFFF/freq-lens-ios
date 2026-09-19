import Foundation
import Security

enum LensError: LocalizedError {
    case invalidAddress, authentication, http(Int), invalidResponse, invalidData, incompleteHistory, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入完整的 http:// 或 https:// 地址，不含账号、查询参数或片段。"
        case .authentication: "登录信息已失效，请重新连接服务器。"
        case .http(let status): "服务器返回 HTTP \(status)，请检查 API 服务和地址。"
        case .invalidResponse: "服务器未返回有效响应。请确认地址指向 Freqtrade API。"
        case .invalidData: "接口数据格式不匹配，请确认 Freqtrade 版本。"
        case .incompleteHistory: "交易历史暂未完整读取，请刷新后重试。"
        case .keychain: "无法安全保存登录信息，请重试。"
        }
    }
}

enum APIAddress {
    static func normalize(_ input: String) throws -> URL {
        guard var parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw LensError.invalidAddress
        }
        parts.scheme = parts.scheme?.lowercased()
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/api/v1") { path += "/api/v1" }
        parts.path = path
        guard let url = parts.url else { throw LensError.invalidAddress }
        return url
    }
}

/// An explicit allowlist keeps trading and bot-control routes out of the client.
enum ReadEndpoint: Sendable, CaseIterable {
    case config, profit, balance, status, performance, daily, trades, candles
    var path: String {
        switch self {
        case .config: "show_config"
        case .profit: "profit"
        case .balance: "balance"
        case .status: "status"
        case .performance: "performance"
        case .daily: "daily"
        case .trades: "trades"
        case .candles: "pair_candles"
        }
    }
}

enum TokenVault {
    static func save(_ tokens: Tokens, for id: UUID) throws {
        let data = try JSONEncoder().encode(tokens)
        let query = baseQuery(id)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw LensError.keychain(result) }
        } else if status != errSecSuccess { throw LensError.keychain(status) }
    }

    static func read(_ id: UUID) -> Tokens? {
        var query = baseQuery(id)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: data)
    }

    static func delete(_ id: UUID) { SecItemDelete(baseQuery(id) as CFDictionary) }
    private static func baseQuery(_ id: UUID) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: "studio.freqlens.tokens", kSecAttrAccount: id.uuidString]
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Never forward authentication to an unexpected host or downgraded URL.
        completionHandler(nil)
    }
}

actor FreqtradeClient {
    let profile: ServerProfile
    private var tokens: Tokens
    private let session: URLSession
    private var refreshTask: Task<Tokens, Error>?

    init(profile: ServerProfile, tokens: Tokens, session: URLSession? = nil) {
        self.profile = profile
        self.tokens = tokens
        self.session = session ?? Self.makeSession()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 35
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func login(profile: ServerProfile, password: String) async throws -> Tokens {
        var request = URLRequest(url: profile.address.appendingPathComponent("token/login"))
        request.httpMethod = "POST"
        let basic = Data("\(profile.username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        let session = makeSession()
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        try validate(response)
        do { return try decoder().decode(Tokens.self, from: data) }
        catch { throw LensError.invalidData }
    }

    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LensError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw LensError.authentication }
        guard (200..<300).contains(http.statusCode) else { throw LensError.http(http.statusCode) }
    }

    func get<T: Decodable & Sendable>(_ endpoint: ReadEndpoint, query: [String: String] = [:]) async throws -> T {
        let originalToken = tokens.accessToken
        var request = try makeRequest(endpoint, query: query, token: originalToken)
        var (data, response) = try await readWithRetry(request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            if tokens.accessToken == originalToken { try await refresh() }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await readWithRetry(request)
        }
        try Self.validate(response)
        do { return try Self.decoder().decode(T.self, from: data) }
        catch { throw LensError.invalidData }
    }

    private func readWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        for attempt in 0..<3 {
            let result = try await session.data(for: request)
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            if ![502, 503, 504].contains(status) || attempt == 2 { return result }
            try await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
        }
        throw LensError.invalidResponse
    }

    func makeRequest(_ endpoint: ReadEndpoint, query: [String: String], token: String) throws -> URLRequest {
        guard var parts = URLComponents(url: profile.address.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw LensError.invalidAddress
        }
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw LensError.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func refresh() async throws {
        if let refreshTask { tokens = try await refreshTask.value; return }
        let current = tokens
        let address = profile.address
        let session = session
        let id = profile.id
        let task = Task<Tokens, Error> {
            var request = URLRequest(url: address.appendingPathComponent("token/refresh"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(current.refreshToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            try Self.validate(response)
            struct Access: Decodable { let accessToken: String }
            let access = try Self.decoder().decode(Access.self, from: data)
            let renewed = Tokens(accessToken: access.accessToken, refreshToken: current.refreshToken)
            try TokenVault.save(renewed, for: id)
            return renewed
        }
        refreshTask = task
        defer { refreshTask = nil }
        tokens = try await task.value
    }

    func snapshot() async throws -> Snapshot {
        async let config: BotConfig = get(.config)
        async let profit: Profit = get(.profit)
        async let wallet: Wallet = get(.balance)
        async let status: [Trade] = get(.status)
        async let performance: [PairPerformance] = get(.performance)
        async let daily: DailyResponse = get(.daily, query: ["timescale": "90"])
        async let history: TradePage = fullHistory()
        return try await Snapshot(config: config, profit: profit, wallet: wallet, positions: status,
                                  performance: performance, daily: daily.data, history: history, fetchedAt: Date())
    }

    /// Fetch complete closed history before exposing any period statistics.
    /// Retry a changing/overlapping pagination window once; never publish a partial result.
    func fullHistory() async throws -> TradePage {
        for attempt in 0..<2 {
            do {
                let first: TradePage = try await get(.trades, query: ["limit": "500", "offset": "0", "order_by_id": "false"])
                var trades = first.trades
                let expected = first.totalTrades
                guard first.offset == 0, expected >= trades.count else { throw LensError.incompleteHistory }
                while trades.count < expected {
                    try Task.checkCancellation()
                    let page: TradePage = try await get(.trades, query: ["limit": "500", "offset": String(trades.count), "order_by_id": "false"])
                    guard !page.trades.isEmpty, page.offset == trades.count, page.totalTrades == expected else { throw LensError.incompleteHistory }
                    trades.append(contentsOf: page.trades)
                }
                guard trades.count == expected, Set(trades.map(\.id)).count == expected,
                      trades.allSatisfy({ !$0.isOpen && $0.closedAt != nil }) else { throw LensError.incompleteHistory }
                if expected > first.trades.count {
                    let head: TradePage = try await get(.trades, query: ["limit": "1", "offset": "0", "order_by_id": "false"])
                    guard head.totalTrades == expected, head.trades.first?.id == first.trades.first?.id else { throw LensError.incompleteHistory }
                }
                return TradePage(trades: trades, tradesCount: trades.count, offset: 0, totalTrades: expected)
            } catch LensError.incompleteHistory {
                if attempt == 1 { throw LensError.incompleteHistory }
            }
        }
        throw LensError.incompleteHistory
    }

    func history(offset: Int) async throws -> TradePage {
        try await get(.trades, query: ["limit": "100", "offset": String(offset), "order_by_id": "false"])
    }

    func candles(pair: String, timeframe: String) async throws -> [Candle] {
        let response: CandleResponse = try await get(.candles, query: ["pair": pair, "timeframe": timeframe, "limit": "240"])
        return response.candles
    }

    /// The only destructive route: a confirmed historical trade, with a fresh
    /// status check immediately before deletion. Never retry an ambiguous DELETE.
    func deleteClosedTrade(_ expected: Trade, before cutoff: Date) async throws {
        guard expected.id > 0, !expected.isOpen, let date = expected.closedAt, date < cutoff else {
            throw HistoryDeletionError.unsafeTrade(expected.id)
        }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let oldToken = tokens.accessToken
            var check = URLRequest(url: profile.address.appendingPathComponent("trade/\(expected.id)"))
            check.setValue("Bearer \(oldToken)", forHTTPHeaderField: "Authorization")
            var (data, response) = try await readWithRetry(check)
            if (response as? HTTPURLResponse)?.statusCode == 401 {
                if tokens.accessToken == oldToken { try await refresh() }
                check.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
                (data, response) = try await readWithRetry(check)
            }
            try Self.validate(response)
            let status = try Self.decoder().decode(DeletionTradeStatus.self, from: data)
            guard status.permitsDeletion(of: expected, before: cutoff) else { throw HistoryDeletionError.unsafeTrade(expected.id) }
            try Task.checkCancellation()
            var deletion = URLRequest(url: profile.address.appendingPathComponent("trades/\(expected.id)"))
            deletion.httpMethod = "DELETE"
            let mutationToken = tokens.accessToken
            deletion.setValue("Bearer \(mutationToken)", forHTTPHeaderField: "Authorization")
            let result: (Data, URLResponse)
            do { result = try await session.data(for: deletion) }
            catch { throw HistoryDeletionError.unconfirmed }
            if (result.1 as? HTTPURLResponse)?.statusCode == 401, attempt == 0 {
                if tokens.accessToken == mutationToken { try await refresh() }
                continue // A definite authentication rejection; re-check trade before retrying.
            }
            try Self.validate(result.1)
            guard let decoded = try? Self.decoder().decode(DeletionResponse.self, from: result.0),
                  decoded.result == "success", decoded.tradeId == expected.id, decoded.cancelOrderCount == 0 else {
                throw HistoryDeletionError.unexpectedResponse
            }
            return
        }
        throw LensError.authentication
    }
}
