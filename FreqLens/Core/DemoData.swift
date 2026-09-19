import Foundation

enum DemoData {
    static func snapshot(now: Date = Date()) -> Snapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        let pairs = ["BTC/USDT", "ETH/USDT", "SOL/USDT", "LINK/USDT", "AVAX/USDT"]
        let prices = [64285.0, 3426.8, 148.62, 18.45, 35.82]
        let pattern = [42.8, 65.2, -36.5, 89.4, 53.7, -42.3, 76.1, 24.8, -28.4, 61.5, -19.2]
        var daily: [DailyProfit] = []
        var history: [Trade] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for day in 0..<90 {
            let date = today.addingTimeInterval(Double(day - 89) * 86_400)
            var sum = 0.0
            for index in 0..<3 {
                let sequence = day * 3 + index
                let slot = sequence % pairs.count
                let pnl = (pattern[sequence % pattern.count] * (0.8 + Double(day % 7) * 0.08) * 100).rounded() / 100
                sum += pnl
                let closed = date.addingTimeInterval(Double(index + 1) * 1_800)
                let opened = closed.addingTimeInterval(-Double(2 + sequence % 12) * 3_600)
                let stake = [1500.0, 1800, 1200, 1000, 900][slot]
                let entry = prices[slot] * (0.92 + Double(day) * 0.001)
                history.append(Trade(tradeId: sequence + 1, pair: pairs[slot], isOpen: false,
                    isShort: false, amount: stake / entry, stakeAmount: stake, openRate: entry,
                    openTimestamp: opened.timeIntervalSince1970 * 1_000,
                    closeTimestamp: closed.timeIntervalSince1970 * 1_000,
                    closeRate: entry * (1 + pnl / stake), closeProfitAbs: pnl, closeProfit: pnl / stake,
                    strategy: "Aurora Trend", enterTag: "trend_follow", exitReason: pnl > 0 ? "roi" : "stop_loss", leverage: 1, timeframe: 5))
            }
            daily.append(DailyProfit(date: formatter.string(from: date), absProfit: sum, relProfit: sum / 25_000, tradeCount: 3))
        }
        let currentPnl = [182.34, 96.18, -28.42, 36.31]
        let positions = (0..<4).map { i in
            let stake = [3500.0, 2250, 1400, 900][i]
            return Trade(tradeId: 271 + i, pair: pairs[i], isOpen: true, isShort: false,
                amount: stake / prices[i], stakeAmount: stake, openRate: prices[i],
                openTimestamp: now.addingTimeInterval(-Double([18, 7, 4, 2][i]) * 3600).timeIntervalSince1970 * 1_000,
                currentRate: prices[i] * (1 + currentPnl[i] / stake), profitAbs: currentPnl[i], profitRatio: currentPnl[i] / stake,
                totalProfitAbs: currentPnl[i], totalProfitRatio: currentPnl[i] / stake, realizedProfit: 0,
                strategy: "Aurora Trend", enterTag: "trend_follow", leverage: 1, stopLossAbs: prices[i] * 0.95, timeframe: 5)
        }
        let closedProfit = history.reduce(0) { $0 + ($1.pnl ?? 0) }
        let openProfit = currentPnl.reduce(0, +)
        let winning = history.filter { ($0.pnl ?? 0) > 0 }
        let losing = history.filter { ($0.pnl ?? 0) < 0 }
        let performance = pairs.map { pair in
            let trades = history.filter { $0.pair == pair }
            return PairPerformance(pair: pair, profitAbs: trades.reduce(0) { $0 + ($1.pnl ?? 0) },
                                   profitRatio: nil, count: trades.count)
        }
        let total = 25_000 + closedProfit + openProfit
        let occupied = positions.reduce(0) { $0 + $1.stakeAmount }
        let wallet = Wallet(currencies: [WalletAsset(currency: "USDT", free: total - occupied, balance: total,
                            used: occupied, estStake: total, estStakeBot: total)], total: total, totalBot: total,
                            stake: "USDT", startingCapital: 25_000)
        let profit = Profit(profitClosedCoin: closedProfit, profitClosedRatio: closedProfit / 25_000,
            profitAllCoin: closedProfit + openProfit, profitAllRatio: (closedProfit + openProfit) / 25_000,
            tradeCount: history.count + positions.count, closedTradeCount: history.count,
            winningTrades: winning.count, losingTrades: losing.count, winrate: Double(winning.count) / Double(history.count),
            profitFactor: winning.reduce(0) { $0 + ($1.pnl ?? 0) } / abs(losing.reduce(0) { $0 + ($1.pnl ?? 0) }),
            maxDrawdown: 0.0284, maxDrawdownAbs: 710, currentDrawdown: 0.0061,
            expectancy: closedProfit / Double(history.count), sharpe: 2.36, sortino: 3.18,
            avgDuration: "6:42:00", tradingVolume: 691_200)
        return Snapshot(config: BotConfig(botName: "Aurora", strategy: "Aurora Trend", exchange: "Binance",
            timeframe: "5m", stakeCurrency: "USDT", dryRun: true, state: "running", version: "2026.9",
            tradingMode: "spot", maxOpenTrades: 8), profit: profit, wallet: wallet, positions: positions,
            performance: performance, daily: daily,
            history: TradePage(trades: history.sorted { $0.id > $1.id }, tradesCount: history.count, offset: 0, totalTrades: history.count),
            fetchedAt: now)
    }

    static func candles(for trade: Trade) -> [Candle] {
        let target = trade.mark ?? trade.openRate
        let end = trade.closedAt ?? Date()
        return (0..<80).map { index in
            let progress = Double(index) / 79
            let wave = sin(Double(index) * 0.6) * trade.openRate * 0.0018
            let open = trade.openRate + (target - trade.openRate) * progress + wave
            let close = index == 79 ? target : open + cos(Double(index) * 1.2) * trade.openRate * 0.0015
            return Candle(date: end.addingTimeInterval(Double(index - 79) * 300), open: open,
                high: max(open, close) + trade.openRate * 0.001, low: min(open, close) - trade.openRate * 0.001,
                close: close, volume: 100 + Double(index % 9) * 32)
        }
    }
}
