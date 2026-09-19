import SwiftUI

struct PositionsView: View {
    @Environment(LensStore.self) private var store
    @Binding var showConnection: Bool
    @State private var sortByProfit = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DataStatus()
                if let data = store.snapshot {
                    summary(data)
                    HStack {
                        SectionHeading(title: "当前仓位", detail: "\(data.positions.count) 笔")
                        Menu {
                            Button("按收益排序") { sortByProfit = true }
                            Button("按开仓时间") { sortByProfit = false }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down").font(.system(size: 12)).padding(10)
                        }.glassEffect().accessibilityLabel("持仓排序")
                    }
                    if data.positions.isEmpty {
                        ContentUnavailableView("暂无持仓", systemImage: "tray", description: Text("策略开仓后，数据会自动出现在这里。"))
                    }
                    ForEach(sorted(data.positions)) { trade in
                        NavigationLink(value: trade) { positionCard(trade, currency: data.config.stakeCurrency) }.buttonStyle(.plain)
                    }
                }
                RefreshFootnote()
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
        }.background(LensTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { DashboardToolbar(showConnection: $showConnection) }
            .refreshable { await store.refresh() }
            .navigationDestination(for: Trade.self) { TradeDetailView(trade: $0) }
    }

    private func summary(_ data: Snapshot) -> some View {
        let total = data.positions.allSatisfy { $0.pnl != nil } ? data.positions.reduce(0) { $0 + ($1.pnl ?? 0) } : nil
        let stake = data.positions.reduce(0) { $0 + $1.stakeAmount }
        return LensCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("持仓总收益 · \(data.config.stakeCurrency)").font(.caption).foregroundStyle(LensTheme.muted)
                Text(store.privacyMode ? "••••••" : Fmt.number(total, signed: true))
                    .font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(LensTheme.pnl(total)).monospacedDigit()
                HStack(spacing: 20) {
                    Label("\(data.positions.count) 个仓位", systemImage: "square.stack.3d.up")
                    Text("投入 \(store.privacyMode ? "••••" : Fmt.number(stake))")
                }.font(.system(size: 11)).foregroundStyle(LensTheme.muted)
                Text("包含持仓内已实现收益").font(.system(size: 10)).foregroundStyle(LensTheme.muted)
            }
        }
    }

    private func positionCard(_ trade: Trade, currency: String) -> some View {
        LensCard {
            VStack(spacing: 18) {
                HStack(spacing: 11) {
                    CoinIcon(symbol: trade.symbol, size: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(trade.pair).font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 6) {
                            Text(trade.direction).foregroundStyle(trade.isShort == true ? LensTheme.loss : LensTheme.tint)
                            Text("· \(Fmt.number(trade.leverage ?? 1, digits: 0))× · \(Fmt.duration(from: trade.openedAt))").foregroundStyle(LensTheme.muted)
                        }.font(.system(size: 10, weight: .medium))
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(LensTheme.muted)
                }
                HStack(alignment: .lastTextBaseline) {
                    Text(store.privacyMode ? "••••" : Fmt.number(trade.pnl, signed: true))
                        .font(.system(size: 30, weight: .medium, design: .rounded)).monospacedDigit()
                    Spacer()
                    Text(Fmt.percent(trade.ratio, signed: true)).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(LensTheme.pnl(trade.pnl).opacity(0.08), in: Capsule())
                }.foregroundStyle(LensTheme.pnl(trade.pnl))
                if let realized = trade.realizedProfit, realized != 0 {
                    HStack {
                        Text("当前浮动 \(store.privacyMode ? "••••" : Fmt.number(trade.profitAbs, signed: true))")
                        Spacer()
                        Text("已实现 \(store.privacyMode ? "••••" : Fmt.number(realized, signed: true))")
                    }.font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                }
                Divider().opacity(0.5)
                HStack {
                    valueColumn("开仓均价", value: Fmt.price(trade.openRate))
                    Spacer()
                    valueColumn("当前价格", value: Fmt.price(trade.currentRate))
                    Spacer()
                    valueColumn("当前投入 \(currency)", value: store.privacyMode ? "••••" : Fmt.number(trade.stakeAmount))
                }
            }
        }
    }
    private func valueColumn(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 10)).foregroundStyle(LensTheme.muted)
            Text(value).font(.system(size: 13, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
    private func sorted(_ trades: [Trade]) -> [Trade] {
        sortByProfit ? trades.sorted { ($0.pnl ?? -.infinity) > ($1.pnl ?? -.infinity) } : trades.sorted { $0.openTimestamp > $1.openTimestamp }
    }
}
