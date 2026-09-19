import SwiftUI
import Charts

struct TradeDetailView: View {
    var trade: Trade
    @Environment(LensStore.self) private var store
    @State private var candles: [Candle] = []
    @State private var isLoading = true
    @State private var chartError: String?
    private var current: Trade {
        store.snapshot?.positions.first { $0.id == trade.id } ?? store.snapshot?.history.trades.first { $0.id == trade.id } ?? trade
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DataStatus()
                HStack(spacing: 12) {
                    CoinIcon(symbol: current.symbol, size: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(current.pair).font(.title2.weight(.semibold))
                        Text("\(current.direction) · \(current.isOpen ? "持仓中" : "已平仓") · #\(current.id)")
                            .font(.caption).foregroundStyle(LensTheme.muted)
                    }
                    Spacer()
                }
                LensCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(current.isOpen ? "持仓总收益" : "已实现收益") · \(store.snapshot?.config.stakeCurrency ?? "")")
                            .font(.caption).foregroundStyle(LensTheme.muted)
                        Text(store.privacyMode ? "••••••" : Fmt.number(current.pnl, signed: true))
                            .font(.system(size: 40, weight: .medium, design: .rounded)).foregroundStyle(LensTheme.pnl(current.pnl))
                        Text(Fmt.percent(current.ratio, signed: true)).font(.subheadline.weight(.medium)).foregroundStyle(LensTheme.pnl(current.ratio))
                    }
                }
                candleCard
                LensCard {
                    VStack(spacing: 18) {
                        SectionHeading(title: "交易信息")
                        detail("开仓均价", Fmt.price(current.openRate))
                        detail(current.isOpen ? "当前价格" : "平仓价格", Fmt.price(current.mark))
                        detail("当前投入金额", store.privacyMode ? "••••" : Fmt.number(current.stakeAmount))
                        if current.isOpen, let realized = current.realizedProfit {
                            detail("当前浮动收益", store.privacyMode ? "••••" : Fmt.number(current.profitAbs, signed: true))
                            detail("已实现部分", store.privacyMode ? "••••" : Fmt.number(realized, signed: true))
                        }
                        detail("持有数量", store.privacyMode ? "••••" : Fmt.number(current.amount, digits: 6))
                        detail("杠杆", Fmt.number(current.leverage ?? 1, digits: 1) + "×")
                        if let stop = current.stopLossAbs { detail("止损价格", Fmt.price(stop)) }
                        if let liquidation = current.liquidationPrice, liquidation > 0 { detail("强平价格", Fmt.price(liquidation)) }
                        Divider()
                        detail("开仓时间", current.openedAt.formatted(.dateTime.year().month().day().hour().minute()))
                        if let date = current.closedAt { detail("平仓时间", date.formatted(.dateTime.year().month().day().hour().minute())) }
                        detail("持仓时长", Fmt.duration(from: current.openedAt, to: current.closedAt ?? Date()))
                        detail("策略", current.strategy ?? "—")
                        if let tag = current.enterTag, !tag.isEmpty { detail("入场标签", tag) }
                        if let exit = current.exitReason, !exit.isEmpty { detail("离场原因", exit) }
                    }
                }
                RefreshFootnote()
            }.padding(22)
        }.background(LensTheme.background).navigationTitle("交易详情").navigationBarTitleDisplayMode(.inline)
            .task(id: store.snapshot?.fetchedAt) { await loadCandles() }
    }

    private var candleCard: some View {
        LensCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "价格走势", detail: "\(store.snapshot?.config.timeframe ?? "5m") · K 线")
                if isLoading { ProgressView().frame(maxWidth: .infinity).frame(height: 200) }
                else if let chartError {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line").font(.title2)
                        Text("K 线暂不可用").font(.subheadline)
                        Text(chartError).font(.caption).multilineTextAlignment(.center)
                        Button("重试") { Task { await loadCandles() } }.buttonStyle(.bordered)
                    }.foregroundStyle(LensTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 18)
                } else if candles.isEmpty {
                    ContentUnavailableView("暂无 K 线", systemImage: "chart.xyaxis.line", description: Text("服务器尚未缓存此交易对的行情。"))
                } else {
                    InteractiveCandleChart(candles: candles)
                    Text("显示服务器最新行情，不代表该笔交易的历史区间。")
                        .font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                }
            }
        }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 12)).foregroundStyle(LensTheme.muted)
            Spacer(minLength: 20)
            Text(value).font(.system(size: 12, weight: .medium)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
    private func loadCandles() async {
        isLoading = candles.isEmpty
        chartError = nil
        do { candles = try await store.candles(for: trade) }
        catch { if !Task.isCancelled { chartError = error.localizedDescription } }
        isLoading = false
    }
}
