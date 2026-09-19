import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(LensStore.self) private var store
    @Binding var showConnection: Bool
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DataStatus()
                if let data = store.snapshot {
                    hero(data)
                    TimeFilterView()
                    ReportAvailability()
                    if let report = store.report {
                        InteractiveProfitChart(days: report.daily, points: report.cumulativePoints, currency: data.config.stakeCurrency)
                    }
                    LazyVGrid(columns: grid, spacing: 12) {
                        MetricTile(title: "净收益", value: hidden(Fmt.number(store.report?.profit)),
                                   detail: "所选区间 · \(store.report?.count ?? 0) 笔平仓", symbol: "arrow.up.right", color: LensTheme.pnl(store.report?.profit))
                        MetricTile(title: "胜率", value: Fmt.percent(store.report?.winrate),
                                   detail: "\(store.report?.wins ?? 0) 盈利 / \(store.report?.losses ?? 0) 亏损", symbol: "scope")
                        MetricTile(title: "持仓盈亏", value: hidden(Fmt.number(openPnL(data), signed: true)),
                                   detail: "\(data.positions.count) 笔持仓 · 含已实现部分", symbol: "waveform.path", color: LensTheme.pnl(openPnL(data)))
                        MetricTile(title: "历史最大回撤", value: Fmt.percent(data.profit.maxDrawdown),
                                   detail: "账户历史峰值回落", symbol: "arrow.down.right")
                    }
                    if !data.positions.isEmpty {
                        VStack(spacing: 14) {
                            SectionHeading(title: "正在持仓", detail: "\(data.positions.count) 个仓位")
                            LensCard(padding: 16) {
                                VStack(spacing: 0) {
                                    ForEach(Array(data.positions.prefix(3).enumerated()), id: \.element.id) { index, trade in
                                        if index > 0 { Divider().opacity(0.45) }
                                        NavigationLink(value: trade) { TradeRow(trade: trade) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    botSummary(data)
                } else if store.isRefreshing || store.isLoadingCache {
                    ProgressView("正在读取数据…").frame(maxWidth: .infinity).padding(.vertical, 100)
                } else {
                    ContentUnavailableView("等待连接", systemImage: "network", description: Text("通过右上角连接你的 Freqtrade 服务器。"))
                }
                RefreshFootnote()
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
        }
        .background(LensTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbar { DashboardToolbar(showConnection: $showConnection) }
        .refreshable { await store.refresh() }
        .navigationDestination(for: Trade.self) { TradeDetailView(trade: $0) }
    }

    private func hero(_ data: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("资产").font(.system(size: 14, weight: .medium)).foregroundStyle(LensTheme.muted).accessibilityIdentifier("assetTitle")
                Text(data.config.stakeCurrency).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(LensTheme.muted)
                Button { store.privacyMode.toggle() } label: {
                    Image(systemName: store.privacyMode ? "eye.slash" : "eye").font(.system(size: 12)).foregroundStyle(LensTheme.muted)
                }.accessibilityLabel(store.privacyMode ? "显示金额" : "隐藏金额")
            }
            Text(hidden(Fmt.number(data.wallet.botValue)))
                .font(.system(size: 58, weight: .bold, design: .rounded)).tracking(-2.5).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55).contentTransition(.numericText())
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: data.profit.profitAllCoin >= 0 ? "arrow.up.right" : "arrow.down.right").font(.system(size: 10, weight: .bold))
                    Text(Fmt.percent(data.profit.profitAllRatio, signed: true)).font(.system(size: 12, weight: .semibold, design: .rounded))
                }.foregroundStyle(LensTheme.pnl(data.profit.profitAllCoin))
                    .padding(.horizontal, 9).padding(.vertical, 6).background(LensTheme.pnl(data.profit.profitAllCoin).opacity(0.09), in: Capsule())
                Text("总收益 \(hidden(Fmt.number(data.profit.profitAllCoin, signed: true)))")
                    .font(.system(size: 11)).foregroundStyle(LensTheme.muted)
            }
        }.padding(.vertical, 2)
    }

    private func botSummary(_ data: Snapshot) -> some View {
        LensCard(padding: 18) {
            HStack(spacing: 13) {
                Image(systemName: "cpu").font(.system(size: 23)).foregroundStyle(LensTheme.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(data.config.strategy ?? data.config.botName).font(.system(size: 14, weight: .semibold))
                    Text("\(data.config.exchange.capitalized) · \(data.config.timeframe ?? "—") · \(data.config.dryRun ? "模拟交易" : "实盘")")
                        .font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                }
                Spacer()
                Text(data.config.state == "running" ? "运行中" : data.config.state)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(LensTheme.tint)
            }
        }
    }
    private func hidden(_ text: String) -> String { store.privacyMode ? "••••••" : text }
    private func openPnL(_ data: Snapshot) -> Double? {
        guard data.positions.allSatisfy({ $0.pnl != nil }) else { return nil }
        return data.positions.reduce(0) { $0 + ($1.pnl ?? 0) }
    }
}
