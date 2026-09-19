import SwiftUI

struct HistoryView: View {
    @Environment(LensStore.self) private var store
    @Binding var showConnection: Bool
    @State private var search = ""
    @State private var filter = 0
    @State private var showDeletion = false
    private var trades: [Trade] {
        (store.report?.trades ?? []).filter { trade in
            !trade.isOpen && (search.isEmpty || trade.pair.localizedCaseInsensitiveContains(search) || String(trade.id).contains(search)) &&
            (filter == 0 || (filter == 1 && (trade.pnl ?? 0) > 0) || (filter == 2 && (trade.pnl ?? 0) < 0))
        }.sorted { ($0.closeTimestamp ?? 0) > ($1.closeTimestamp ?? 0) }
    }
    private var groups: [(String, [Trade])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = UTCDate.calendar.timeZone
        let grouped = Dictionary(grouping: trades) { formatter.string(from: $0.closedAt ?? $0.openedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                DataStatus()
                TimeFilterView()
                ReportAvailability()
                if let data = store.snapshot, let report = store.report {
                    LensCard {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("平仓").font(.caption).foregroundStyle(LensTheme.muted)
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("\(report.count)").accessibilityIdentifier("historyPeriodCount").font(.system(size: 52, weight: .bold, design: .rounded))
                                    Text("笔交易").font(.caption).foregroundStyle(LensTheme.muted)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text("已实现收益 · \(data.config.stakeCurrency)").font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                                Text(store.privacyMode ? "••••" : Fmt.number(report.profit, signed: true))
                                    .font(.system(size: 21, weight: .medium, design: .rounded)).foregroundStyle(LensTheme.pnl(report.profit))
                            }
                        }
                    }
                    Picker("收益筛选", selection: $filter) {
                        Text("全部").tag(0)
                        Text("盈利").tag(1)
                        Text("亏损").tag(2)
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("\(trades.count) 笔匹配交易").font(.caption)
                        Spacer()
                        Text("区间胜率 \(Fmt.percent(report.winrate))").font(.system(size: 10))
                    }.foregroundStyle(LensTheme.muted)
                    ForEach(groups, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(group.0).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(LensTheme.muted)
                            LensCard(padding: 16) {
                                VStack(spacing: 0) {
                                    ForEach(Array(group.1.enumerated()), id: \.element.id) { index, trade in
                                        if index > 0 { Divider().opacity(0.4) }
                                        NavigationLink(value: trade) { TradeRow(trade: trade) }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    if trades.isEmpty {
                        ContentUnavailableView("暂无匹配交易", systemImage: "magnifyingglass", description: Text("试试其他时间范围、交易对或筛选条件。"))
                    }
                }
                RefreshFootnote()
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
        }.background(LensTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                DashboardToolbar(showConnection: $showConnection)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDeletion = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel("删除历史记录").accessibilityIdentifier("historyDeletionButton")
                }
            }
            .sheet(isPresented: $showDeletion) { HistoryDeletionView() }
            .searchable(text: $search, prompt: "搜索交易对或交易编号")
            .refreshable { await store.refresh() }
            .navigationDestination(for: Trade.self) { TradeDetailView(trade: $0) }
    }
}
