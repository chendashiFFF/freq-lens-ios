import SwiftUI
import Charts

struct InteractiveProfitChart: View {
    enum Kind { case cumulative, daily }
    var days: [DailyProfit]
    var points: [CurvePoint]
    var currency: String
    var kind: Kind = .cumulative
    var startingCapital: Double? = nil
    var outlook: ProfitOutlook? = nil
    @Environment(LensStore.self) private var store
    @State private var selectedX: Double?
    @State private var showOutlookExplanation = false
    @AppStorage("overviewProfitPercent") private var prefersPercent = false

    private var supportsPercent: Bool {
        Metrics.returnRatio(profit: total, startingCapital: startingCapital) != nil &&
        points.allSatisfy { Metrics.returnRatio(profit: $0.value, startingCapital: startingCapital) != nil }
    }
    private var showsPercent: Bool { kind == .cumulative && prefersPercent && supportsPercent }
    private var displayedPoints: [CurvePoint] {
        guard showsPercent else { return points }
        return points.compactMap { point in
            Metrics.returnRatio(profit: point.value, startingCapital: startingCapital)
                .map { CurvePoint(date: point.date, value: $0 * 100) }
        }
    }
    private var projectionValue: Double? {
        guard let amount = outlook?.estimatedTotal else { return nil }
        return displayValue(amount)
    }
    private func displayValue(_ amount: Double) -> Double? {
        showsPercent ? Metrics.returnRatio(profit: amount, startingCapital: startingCapital).map { $0 * 100 } : amount
    }
    private var lastX: Double { Double(max(0, points.count - 1)) }
    // A separate valuation column, not a future date or an invented daily price.
    private var projectionX: Double { lastX + max(1.5, lastX * 0.23) }
    private var selectingProjection: Bool {
        projectionValue != nil && selectedX.map { $0 > (lastX + projectionX) / 2 } == true
    }
    private var headlineValue: Double? {
        guard !days.isEmpty else { return nil }
        return selectingProjection ? projectionValue : displayValue(selected?.value ?? total)
    }
    private func formatted(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "—" }
        return Fmt.number(value, signed: signed) + (showsPercent ? "%" : "")
    }
    private var selected: CurvePoint? {
        guard let selectedX, !selectingProjection, !points.isEmpty else { return nil }
        return points[min(points.count - 1, max(0, Int(selectedX.rounded())))]
    }
    private var fullDomain: ClosedRange<Double> {
        if kind == .daily { return -0.5...max(0.5, lastX + 0.5) }
        return 0...max(1, projectionValue == nil ? lastX : projectionX)
    }
    private var axisValues: [Double] {
        let history = [0, Int(lastX / 2), Int(lastX)].map(Double.init)
        return Array(Set(history)).sorted() + (projectionValue == nil ? [] : [projectionX])
    }
    private var rangeKey: String { "\(days.first?.date ?? "")/\(days.last?.date ?? "")" }
    private var total: Double { days.reduce(0) { $0 + $1.absProfit } }
    private var yDomain: ClosedRange<Double> {
        let values = displayedPoints.map(\.value) + [projectionValue].compactMap { $0 }
        let low = min(0, values.min() ?? 0)
        let high = max(0, values.max() ?? 0)
        let pad = max((high - low) * 0.12, 0.01)
        return (low < 0 ? low - pad : 0)...(high + pad)
    }
    private var tint: Color { total < 0 ? LensTheme.loss : LensTheme.tint }

    var body: some View {
        LensCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind == .cumulative ? (showsPercent ? "累计收益率" : "累计收益") : "每日收益")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(LensTheme.muted)
                    Spacer()
                    if kind == .cumulative {
                        HStack(spacing: 2) {
                            unitButton(currency, percent: false)
                            unitButton("%", percent: true)
                        }.padding(3).background(LensTheme.background, in: Capsule())
                    } else {
                        Text(currency).font(.system(size: 10, design: .monospaced)).foregroundStyle(LensTheme.muted)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(store.privacyMode ? "••••" : formatted(headlineValue, signed: true))
                        .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .foregroundStyle((headlineValue ?? 0) < 0 ? LensTheme.loss : LensTheme.tint)
                        .accessibilityIdentifier(kind == .cumulative ? "profitChartValue" : "dailyChartValue")
                    Spacer()
                    Text(readout).font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                        .accessibilityIdentifier(kind == .cumulative ? "profitReadout" : "dailyReadout")
                }
                if days.isEmpty {
                    ContentUnavailableView("暂无可绘制数据", systemImage: "chart.xyaxis.line").frame(height: 200)
                } else {
                    baseChart.chartXScale(domain: fullDomain)
                        .chartXSelection(value: $selectedX)
                        .chartGesture { proxy in
                            DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) }
                        }.frame(height: 200)
                        .accessibilityHint(kind == .cumulative ? "拖动查看历史收益；最右侧现价列为含持仓的估值" : "拖动查看每日已平仓收益")
                        .accessibilityIdentifier(kind == .cumulative ? "profitChart" : "dailyChart")
                        .opacity(store.privacyMode ? 0 : 1).accessibilityHidden(store.privacyMode)
                        .overlay { if store.privacyMode { Text("金额已隐藏").font(.caption).foregroundStyle(LensTheme.muted) } }
                }
                if let outlook, kind == .cumulative { outlookSummary(outlook) }
                HStack {
                    Text("\(days.first?.date ?? "—") — \(days.last?.date ?? "—")")
                        .accessibilityIdentifier(kind == .cumulative ? "profitViewport" : "dailyViewport")
                    Spacer(minLength: 4)
                    if showsPercent { Text("相对初始资金").accessibilityIdentifier("profitReturnBasis") }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(LensTheme.muted)
            }
        }
        .onChange(of: rangeKey) { _, _ in selectedX = nil }
        .sheet(isPresented: $showOutlookExplanation) { outlookExplanation }
    }

    private func unitButton(_ title: String, percent: Bool) -> some View {
        Button { prefersPercent = percent } label: {
            Text(title).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(showsPercent == percent ? LensTheme.background : LensTheme.muted)
                .padding(.horizontal, 11).frame(minHeight: 32)
                .background(showsPercent == percent ? LensTheme.tint : .clear, in: Capsule())
        }.buttonStyle(.plain)
            .disabled(percent && !supportsPercent)
            .opacity(percent && !supportsPercent ? 0.4 : 1)
            .accessibilityLabel(percent ? "收益百分比" : "收益金额 \(currency)")
            .accessibilityValue(showsPercent == percent ? "已选择" : "未选择")
            .accessibilityHint(percent ? (supportsPercent ? "相对机器人初始资金" : "服务器未提供有效初始资金") : "以账户币种显示")
            .accessibilityIdentifier(percent ? "profitUnit-percent" : "profitUnit-amount")
    }

    private var readout: String {
        if selectingProjection { return "现价估值\n含 \(outlook?.positionCount ?? 0) 笔持仓" }
        guard let selected else { return "区间合计" }
        let count = days.first { $0.day == selected.date }?.tradeCount ?? 0
        return "\(UTCDate.string(selected.date))\n\(kind == .cumulative ? (showsPercent ? "累计收益率" : "累计收益") : "\(count) 笔平仓")"
    }

    private var baseChart: some View {
        Chart { marks }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: axisValues) { value in
                    AxisValueLabel(anchor: value.as(Double.self) == 0 ? .topLeading : (value.as(Double.self) == (projectionValue == nil ? lastX : projectionX) ? .topTrailing : .top), collisionResolution: .disabled) {
                        if let index = value.as(Double.self) {
                            Text(index > lastX ? "现价" : axisDate(index))
                                .font(.system(size: 9)).foregroundStyle(LensTheme.muted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(LensTheme.grid)
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(showsPercent ? Fmt.number(number) + "%" : Fmt.compact(number))
                                .font(.system(size: 9)).foregroundStyle(LensTheme.muted)
                        }
                    }
                }
            }
    }

    private func axisDate(_ index: Double) -> String {
        guard points.indices.contains(Int(index)) else { return "" }
        return String(UTCDate.string(points[Int(index)].date).suffix(5))
    }

    @ChartContentBuilder private var marks: some ChartContent {
        if kind == .cumulative {
            cumulativeMarks
            projectionMarks
        } else {
            dailyMarks
        }
        RuleMark(y: .value("零", 0)).foregroundStyle(LensTheme.grid).lineStyle(StrokeStyle(lineWidth: 0.8))
        selectionMarks
    }

    @ChartContentBuilder private var cumulativeMarks: some ChartContent {
        ForEach(Array(displayedPoints.enumerated()), id: \.element.id) { index, point in
            AreaMark(x: .value("观测点", Double(index)), yStart: .value("基线", 0), yEnd: .value("累计收益", point.value))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("观测点", Double(index)), y: .value("累计收益", point.value), series: .value("口径", "已平仓"))
                .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5))
        }
    }

    @ChartContentBuilder private var projectionMarks: some ChartContent {
        if let projectionValue, let last = displayedPoints.last {
            RuleMark(x: .value("估值分隔", lastX + (projectionX - lastX) * 0.15))
                .foregroundStyle(LensTheme.grid).lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
            LineMark(x: .value("观测点", lastX), y: .value("含持仓估值", last.value), series: .value("口径", "含持仓"))
                .foregroundStyle(LensTheme.pnl(outlook?.positionProfit))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            LineMark(x: .value("观测点", projectionX), y: .value("含持仓估值", projectionValue), series: .value("口径", "含持仓"))
                .foregroundStyle(LensTheme.pnl(outlook?.positionProfit))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            PointMark(x: .value("观测点", projectionX), y: .value("含持仓估值", projectionValue))
                .foregroundStyle(LensTheme.pnl(outlook?.positionProfit)).symbolSize(selectingProjection ? 55 : 30)
        }
    }

    @ChartContentBuilder private var dailyMarks: some ChartContent {
        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
            RectangleMark(xStart: .value("日期起点", Double(index) - 0.325), xEnd: .value("日期终点", Double(index) + 0.325),
                          yStart: .value("收益下界", min(0, point.value)), yEnd: .value("收益上界", max(0, point.value)))
                .foregroundStyle(point.value < 0 ? LensTheme.loss : LensTheme.tint).cornerRadius(2)
        }
    }

    @ChartContentBuilder private var selectionMarks: some ChartContent {
        if let selected, let index = points.firstIndex(where: { $0.id == selected.id }) {
            RuleMark(x: .value("所选日期", Double(index))).foregroundStyle(LensTheme.muted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("观测点", Double(index)), y: .value("收益", headlineValue ?? 0))
                .foregroundStyle(LensTheme.pnl(selected.value)).symbolSize(45)
        }
    }

    private func outlookSummary(_ outlook: ProfitOutlook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Capsule().fill(tint).frame(width: 15, height: 2)
                    Text("已平仓")
                }
                if let projectionValue {
                    HStack(spacing: 5) {
                        LineSample().stroke(LensTheme.pnl(outlook.positionProfit), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 18, height: 2)
                        Text("含持仓")
                    }
                    Spacer(minLength: 0)
                    Text(store.privacyMode ? "••••" : formatted(projectionValue, signed: true))
                        .fontWeight(.semibold).foregroundStyle(LensTheme.pnl(projectionValue))
                        .accessibilityIdentifier("profitEstimateValue")
                } else {
                    Spacer(minLength: 0)
                    Text(outlook.positionNote ?? "")
                }
            }.font(.system(size: 10)).foregroundStyle(LensTheme.muted)
            Divider().overlay(LensTheme.grid.opacity(0.5))
            HStack(alignment: .top) {
                rateTile("月化参考", ratio: outlook.monthlyRatio, id: "monthlyReturn")
                Spacer()
                rateTile("年化参考", ratio: outlook.annualRatio, id: "annualReturn")
                Spacer()
                Button { showOutlookExplanation = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(LensTheme.muted)
                        .frame(width: 32, height: 32)
                }.buttonStyle(.plain).accessibilityLabel("收益估算口径").accessibilityIdentifier("profitOutlookInfo")
            }
            Text(outlook.observationDays < 7 ? "样本不足 7 天 · 单利折算，仅供参考" : "基于已平仓 · \(outlook.observationDays) 天 · 单利折算")
                .font(.system(size: 9)).foregroundStyle(LensTheme.muted)
            if projectionValue != nil {
                Text("\(outlook.isCached ? "缓存估值" : "估值") \(outlook.snapshotDate.formatted(.dateTime.hour().minute())) · 未平仓部分随行情变化")
                    .font(.system(size: 9)).foregroundStyle(LensTheme.muted)
            }
        }
    }

    private func rateTile(_ title: String, ratio: Double?, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(LensTheme.muted)
            Text(store.privacyMode ? "••••" : Fmt.percent(ratio, signed: true))
                .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(LensTheme.pnl(ratio))
                .accessibilityIdentifier(id)
        }
    }

    private var outlookExplanation: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("月化 / 年化").font(.headline)
                    Text("区间已平仓收益 ÷ 服务器初始资金 ÷ 观测天数 × 30 / 365。采用单利，不假设复利，也不计入当前持仓。")
                    Text("观测天数按 UTC 自然日计算，今天计 1 天；不计未来日期，也不计早于最早保留交易开仓日的时间。全部范围从最早平仓日开始。短区间和删除历史后的结果代表性较弱，折算不是收益承诺。")
                    Text("实线 / 虚线").font(.headline)
                    Text("实线是所选区间内已平仓收益。虚线只连接到右侧独立的现价估值列：区间已平仓收益 + 当前持仓总盈亏，包含当前持仓分批退出的已实现部分。横向间距仅用于排版，不代表未来日期。")
                    Text("当前持仓可能在区间开始前开仓，因此含持仓值不是严格的区间净值收益。过去区间不叠加今天的持仓；数据缺失时不估算。现价估值不保证最终成交价格、手续费或资金费。")
                }.font(.subheadline).foregroundStyle(LensTheme.muted).padding(24)
            }.background(LensTheme.background).navigationTitle("计算口径").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showOutlookExplanation = false } } }
        }.presentationDetents([.large])
    }

}

struct InteractiveCandleChart: View {
    var candles: [Candle]
    @State private var selectedDate: Date?
    private var interval: Double {
        guard candles.count > 1 else { return 300 }
        return max(1, candles[1].date.timeIntervalSince(candles[0].date))
    }
    private var fullDomain: ClosedRange<Date> {
        let first = candles.first?.date ?? Date()
        return first...(candles.last?.date ?? first).addingTimeInterval(interval)
    }
    private var selected: Candle? {
        selectedDate.flatMap { date in candles.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }
    private var yDomain: ClosedRange<Double> {
        let lower = candles.map(\.low).min() ?? 0
        let upper = candles.map(\.high).max() ?? 1
        let pad = max((upper - lower) * 0.15, max(abs(upper) * 0.0001, 0.000001))
        return (lower - pad)...(upper + pad)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let candle = selected {
                VStack(alignment: .leading, spacing: 6) {
                    Text(candle.date.formatted(.dateTime.month().day().hour().minute())).font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                    HStack {
                        candleValue("开", candle.open); Spacer(); candleValue("高", candle.high)
                        Spacer(); candleValue("低", candle.low); Spacer(); candleValue("收", candle.close)
                    }
                }.accessibilityElement(children: .combine).accessibilityIdentifier("candleReadout")
            } else {
                Text("\(candles.count) 根")
                    .font(.system(size: 10)).foregroundStyle(LensTheme.muted)
            }
            baseChart.chartXScale(domain: fullDomain).chartXSelection(value: $selectedDate)
                .chartGesture { proxy in
                    DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) }
                }.frame(height: 220).accessibilityIdentifier("candlestickChart")
                .accessibilityHint("拖动查看每根 K 线的开、高、低、收")
            Text("\(fullDomain.lowerBound.formatted(.dateTime.month().day().hour().minute())) — \(fullDomain.upperBound.formatted(.dateTime.month().day().hour().minute()))")
                .font(.system(size: 9)).foregroundStyle(LensTheme.muted).accessibilityIdentifier("candleViewport")
        }
        .onChange(of: candles.first?.date) { _, _ in selectedDate = nil }
    }
    private var baseChart: some View {
        Chart {
            ForEach(candles) { candle in
                RuleMark(x: .value("时间", candle.date), yStart: .value("最低", candle.low), yEnd: .value("最高", candle.high))
                    .foregroundStyle(candle.close >= candle.open ? LensTheme.tint : LensTheme.loss).lineStyle(StrokeStyle(lineWidth: 1))
                BarMark(x: .value("时间", candle.date), yStart: .value("开盘", candle.open), yEnd: .value("收盘", candle.close), width: .ratio(0.65))
                    .foregroundStyle(candle.close >= candle.open ? LensTheme.tint : LensTheme.loss)
            }
            if let selected {
                RuleMark(x: .value("选择时间", selected.date)).foregroundStyle(LensTheme.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("选择收盘", selected.close)).foregroundStyle(LensTheme.muted.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { _ in AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9)).foregroundStyle(LensTheme.muted) } }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(LensTheme.grid); AxisValueLabel().font(.system(size: 9)).foregroundStyle(LensTheme.muted) } }
    }
    private func candleValue(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9)).foregroundStyle(LensTheme.muted)
            Text(Fmt.price(value)).font(.system(size: 10, weight: .medium, design: .monospaced)).minimumScaleFactor(0.6).lineLimit(1)
        }
    }
}

private struct LineSample: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
