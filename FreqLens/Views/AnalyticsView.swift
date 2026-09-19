import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(LensStore.self) private var store
    @Binding var showConnection: Bool
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DataStatus()
                TimeFilterView()
                ReportAvailability()
                if let data = store.snapshot, let report = store.report {
                    winRate(report, currency: data.config.stakeCurrency)
                    LazyVGrid(columns: grid, spacing: 12) {
                        MetricTile(title: "盈利因子", value: report.profitFactor == .infinity ? "∞" : Fmt.number(report.profitFactor), detail: "盈利 / 亏损绝对值", symbol: "divide")
                        MetricTile(title: "单笔期望", value: amount(report.expectancy), detail: data.config.stakeCurrency + " / 笔", symbol: "plus.forwardslash.minus", color: LensTheme.pnl(report.expectancy))
                        MetricTile(title: "平均盈利", value: amount(report.averageWin), detail: "\(report.wins) 笔盈利交易", symbol: "arrow.up.right", color: LensTheme.tint)
                        MetricTile(title: "平均亏损", value: amount(report.averageLoss), detail: "\(report.losses) 笔亏损交易", symbol: "arrow.down.right", color: LensTheme.loss)
                    }
                    InteractiveProfitChart(days: report.daily, points: report.dailyPoints, currency: data.config.stakeCurrency, kind: .daily)
                    MonthlyCalendarView()
                    ranking(report)
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeading(title: "账户历史风险", detail: "全部历史 · 不受日期筛选影响")
                        LazyVGrid(columns: grid, spacing: 12) {
                            MetricTile(title: "历史最大回撤", value: Fmt.percent(data.profit.maxDrawdown), detail: "服务端账户历史峰值回落", symbol: "arrow.down.right")
                            MetricTile(title: "历史夏普比率", value: Fmt.number(data.profit.sharpe), detail: "服务端全历史统计", symbol: "waveform.path")
                        }
                    }
                }
                RefreshFootnote()
            }.padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 28)
        }.background(LensTheme.background).navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { DashboardToolbar(showConnection: $showConnection) }
            .refreshable { await store.refresh() }
    }

    private func winRate(_ report: PeriodReport, currency: String) -> some View {
        let values: [(String, Int, Color)] = [("盈利", report.wins, LensTheme.tint), ("亏损", report.losses, LensTheme.loss), ("持平", report.draws, LensTheme.muted.opacity(0.45))]
        return LensCard(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("胜率").font(.system(size: 13, weight: .medium)).foregroundStyle(LensTheme.muted)
                        Text(report.winrate.map { Fmt.number($0 * 100, digits: 1) + "%" } ?? "—")
                            .font(.system(size: 51, weight: .bold, design: .rounded)).tracking(-2)
                            .lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(LensTheme.tint)
                            .accessibilityIdentifier("periodWinrate")
                    }
                    Spacer(minLength: 8)
                    Chart {
                        if report.count == 0 || report.missingValues > 0 {
                            SectorMark(angle: .value("暂无数据", 1), innerRadius: .ratio(0.82)).foregroundStyle(LensTheme.grid)
                        } else {
                            ForEach(values, id: \.0) { value in
                                if value.1 > 0 {
                                    SectorMark(angle: .value("笔数", value.1), innerRadius: .ratio(0.82), angularInset: 2)
                                        .cornerRadius(3).foregroundStyle(value.2)
                                }
                            }
                        }
                    }.frame(width: 78, height: 78)
                        .accessibilityLabel("区间交易胜率 \(Fmt.percent(report.winrate))")
                }
                HStack(spacing: 18) {
                    ForEach(values, id: \.0) { value in
                        HStack(spacing: 5) {
                            Circle().fill(value.2).frame(width: 5, height: 5)
                            Text("\(value.1) \(value.0)")
                        }.font(.system(size: 11, design: .monospaced)).foregroundStyle(LensTheme.muted)
                    }
                }
                Divider().overlay(LensTheme.grid.opacity(0.5))
                HStack(alignment: .firstTextBaseline) {
                    Text("\(report.count) 笔已平仓").font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LensTheme.muted).accessibilityIdentifier("periodTradeCount")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(amount(report.profit, signed: true)).font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(LensTheme.pnl(report.profit)).monospacedDigit()
                        Text(currency).font(.system(size: 10, design: .monospaced)).foregroundStyle(LensTheme.muted)
                    }
                }
            }
        }
    }

    private func ranking(_ report: PeriodReport) -> some View {
        let pairs = Array(report.performance.prefix(10))
        let largest = max(pairs.map { abs($0.profitAbs) }.max() ?? 1, 0.01)
        return VStack(spacing: 14) {
            SectionHeading(title: "交易对表现", detail: "所选区间 · TOP 10")
            LensCard {
                VStack(spacing: 20) {
                    ForEach(Array(pairs.enumerated()), id: \.element.id) { index, pair in
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(LensTheme.muted)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(pair.pair).font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text(amount(pair.profitAbs, signed: true)).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(LensTheme.pnl(pair.profitAbs))
                                }
                                GeometryReader { geometry in
                                    Capsule().fill(LensTheme.background)
                                    Capsule().fill(LensTheme.pnl(pair.profitAbs).opacity(0.7)).frame(width: max(3, geometry.size.width * abs(pair.profitAbs) / largest))
                                }.frame(height: 4)
                                Text("\(pair.count) 笔交易").font(.system(size: 9)).foregroundStyle(LensTheme.muted)
                            }
                        }
                    }
                    if pairs.isEmpty { Text("该区间暂无可统计交易").font(.caption).foregroundStyle(LensTheme.muted) }
                }
            }
        }
    }
    private func amount(_ value: Double?, signed: Bool = false) -> String { store.privacyMode ? "••••" : Fmt.number(value, signed: signed) }
}
