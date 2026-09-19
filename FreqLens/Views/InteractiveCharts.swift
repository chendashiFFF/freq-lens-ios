import SwiftUI
import Charts

struct InteractiveProfitChart: View {
    enum Kind { case cumulative, daily }
    var days: [DailyProfit]
    var points: [CurvePoint]
    var currency: String
    var kind: Kind = .cumulative
    var startingCapital: Double? = nil
    @Environment(LensStore.self) private var store
    @State private var selectedDate: Date?
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
    private var headlineValue: Double? {
        let amount = selected?.value ?? total
        return showsPercent ? Metrics.returnRatio(profit: amount, startingCapital: startingCapital).map { $0 * 100 } : amount
    }
    private func formatted(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "—" }
        return Fmt.number(value, signed: signed) + (showsPercent ? "%" : "")
    }

    private var selected: CurvePoint? {
        selectedDate.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }
    private var fullDomain: ClosedRange<Date> {
        let first = points.first?.date ?? Date()
        let last = (points.last?.date ?? first).addingTimeInterval(86_400)
        return first...max(first.addingTimeInterval(86_400), last)
    }
    private var rangeKey: String { "\(days.first?.date ?? "")/\(days.last?.date ?? "")" }
    private var total: Double { days.reduce(0) { $0 + $1.absProfit } }
    private var yDomain: ClosedRange<Double> {
        let low = min(0, displayedPoints.map(\.value).min() ?? 0)
        let high = max(0, displayedPoints.map(\.value).max() ?? 0)
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
                        .foregroundStyle((selected?.value ?? total) < 0 ? LensTheme.loss : LensTheme.tint)
                        .accessibilityIdentifier(kind == .cumulative ? "profitChartValue" : "dailyChartValue")
                    Spacer()
                    Text(readout).font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                        .accessibilityIdentifier(kind == .cumulative ? "profitReadout" : "dailyReadout")
                }
                if days.isEmpty {
                    ContentUnavailableView("暂无可绘制数据", systemImage: "chart.xyaxis.line").frame(height: 200)
                } else {
                    baseChart.chartXScale(domain: fullDomain)
                        .chartXSelection(value: $selectedDate)
                        .chartGesture { proxy in
                            DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) }
                        }.frame(height: 200)
                        .accessibilityHint("拖动查看日期和收益")
                        .accessibilityIdentifier(kind == .cumulative ? "profitChart" : "dailyChart")
                        .opacity(store.privacyMode ? 0 : 1).accessibilityHidden(store.privacyMode)
                        .overlay { if store.privacyMode { Text("金额已隐藏").font(.caption).foregroundStyle(LensTheme.muted) } }
                }
                HStack {
                    Text("\(days.first?.date ?? "—") — \(days.last?.date ?? "—")")
                        .accessibilityIdentifier(kind == .cumulative ? "profitViewport" : "dailyViewport")
                    Spacer(minLength: 4)
                    if showsPercent { Text("相对初始资金").accessibilityIdentifier("profitReturnBasis") }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(LensTheme.muted)
            }
        }
        .onChange(of: rangeKey) { _, _ in selectedDate = nil }
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
        guard let selected else { return "区间合计" }
        let count = days.first { $0.day == selected.date }?.tradeCount ?? 0
        return "\(UTCDate.string(selected.date))\n\(kind == .cumulative ? (showsPercent ? "累计收益率" : "累计收益") : "\(count) 笔平仓")"
    }

    private var baseChart: some View {
        Chart { marks }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(String(UTCDate.string(date).suffix(5))).font(.system(size: 9)).foregroundStyle(LensTheme.muted) }
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

    @ChartContentBuilder private var marks: some ChartContent {
        if kind == .cumulative {
            ForEach(displayedPoints) { point in
                AreaMark(x: .value("日期", point.date), yStart: .value("基线", 0), yEnd: .value("累计收益", point.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("日期", point.date), y: .value("累计收益", point.value))
                    .foregroundStyle(tint).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
        } else {
            ForEach(points) { point in
                BarMark(x: .value("日期", point.date, unit: .day, calendar: UTCDate.calendar), y: .value("当日盈亏", point.value))
                    .foregroundStyle(point.value < 0 ? LensTheme.loss : LensTheme.tint).cornerRadius(4)
            }
        }
        RuleMark(y: .value("零", 0)).foregroundStyle(LensTheme.grid).lineStyle(StrokeStyle(lineWidth: 0.8))
        if let selected {
            RuleMark(x: .value("所选日期", selected.date)).foregroundStyle(LensTheme.muted)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(x: .value("日期", selected.date), y: .value("收益", headlineValue ?? 0))
                .foregroundStyle(LensTheme.pnl(selected.value)).symbolSize(45)
        }
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
