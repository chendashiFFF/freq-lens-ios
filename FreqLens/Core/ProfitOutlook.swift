import Foundation

/// Historical simple-rate equivalents and a separate current position valuation.
/// Neither interpolates historical mark-to-market prices nor predicts future fills.
struct ProfitOutlook: Sendable {
    let observationDays: Int
    let monthlyRatio: Double?
    let annualRatio: Double?
    let positionCount: Int
    let positionProfit: Double?
    let estimatedTotal: Double?
    let snapshotDate: Date
    let isCached: Bool
    let positionNote: String?

    init(report: PeriodReport, snapshot: Snapshot, isCached: Bool) {
        observationDays = report.observationDays
        snapshotDate = snapshot.fetchedAt
        self.isCached = isCached
        positionCount = snapshot.positions.count
        let ratio = report.count > 0 ? Metrics.returnRatio(profit: report.profit, startingCapital: snapshot.wallet.startingCapital) : nil
        monthlyRatio = Self.scale(ratio, days: observationDays, target: 30)
        annualRatio = Self.scale(ratio, days: observationDays, target: 365)

        // A current valuation must never appear on a past-only period or use a
        // snapshot from another UTC day. Missing data is not a zero estimate.
        if !report.includesReferenceDay {
            positionNote = "历史区间 · 不叠加当前持仓"
            positionProfit = nil; estimatedTotal = nil
        } else if UTCDate.calendar.startOfDay(for: snapshot.fetchedAt) != report.referenceDay {
            positionNote = "持仓快照已跨日 · 等待同步"
            positionProfit = nil; estimatedTotal = nil
        } else if snapshot.positions.isEmpty {
            positionNote = "暂无持仓"
            positionProfit = nil; estimatedTotal = nil
        } else if let realized = report.profit, realized.isFinite,
                  let openProfit = Self.currentPositionProfit(snapshot.positions),
                  (realized + openProfit).isFinite {
            positionProfit = openProfit
            estimatedTotal = realized + openProfit
            positionNote = nil
        } else {
            positionNote = "持仓估值数据不完整"
            positionProfit = nil; estimatedTotal = nil
        }
    }

    static func scale(_ ratio: Double?, days: Int, target: Int) -> Double? {
        guard let ratio, ratio.isFinite, days > 0, target > 0 else { return nil }
        let value = ratio / Double(days) * Double(target)
        return value.isFinite && (value * 100).isFinite ? value : nil
    }

    static func currentPositionProfit(_ positions: [Trade]) -> Double? {
        var total = 0.0
        for trade in positions {
            guard trade.isOpen, let price = trade.currentRate, price.isFinite, price > 0 else { return nil }
            let value: Double
            if let combined = trade.totalProfitAbs {
                value = combined // Already includes partial exits: never add realizedProfit twice.
            } else if let floating = trade.profitAbs, let realized = trade.realizedProfit {
                value = floating + realized
            } else {
                return nil // Cannot establish whether an older server omitted partial-exit P&L.
            }
            guard value.isFinite, (total + value).isFinite else { return nil }
            total += value
        }
        return total
    }
}
