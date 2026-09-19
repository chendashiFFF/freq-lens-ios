import SwiftUI

enum CalendarMonth {
    static func start(_ date: Date) -> Date { UTCDate.calendar.dateInterval(of: .month, for: date)!.start }
    static func filter(_ date: Date) -> TradeTimeFilter {
        let start = start(date)
        let next = UTCDate.calendar.date(byAdding: .month, value: 1, to: start)!
        return TradeTimeFilter(preset: .custom, start: start, end: next.addingTimeInterval(-1))
    }
    static func title(_ date: Date) -> String {
        let parts = UTCDate.calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year!) 年 \(parts.month!) 月"
    }
}

struct MonthlyCalendarView: View {
    @Environment(LensStore.self) private var store
    @State private var month = CalendarMonth.start(Date())
    @State private var report: PeriodReport?
    @State private var selectedDay: DailyProfit?
    @State private var isLoading = true

    private var currentMonth: Date { CalendarMonth.start(Date()) }
    private var firstMonth: Date {
        CalendarMonth.start(store.snapshot?.history.trades.compactMap(\.closedAt).min() ?? Date())
    }
    private var requestID: String { "\(month.timeIntervalSince1970)/\(store.activeID?.uuidString ?? "demo")/\(store.snapshot?.fetchedAt.timeIntervalSince1970 ?? 0)" }

    var body: some View {
        LensCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("收益日历").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    if isLoading { ProgressView().controlSize(.mini) }
                    Text("按月 · UTC").font(.system(size: 10)).foregroundStyle(LensTheme.muted)
                }
                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                        .disabled(month <= firstMonth).accessibilityLabel("上个月").accessibilityIdentifier("calendarPreviousMonth")
                    Spacer()
                    Text(CalendarMonth.title(month)).font(.system(size: 16, weight: .semibold, design: .rounded))
                        .accessibilityIdentifier("calendarMonth")
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                        .disabled(month >= currentMonth).accessibilityLabel("下个月").accessibilityIdentifier("calendarNextMonth")
                }.buttonStyle(.plain)
                let days = report?.daily ?? []
                let daysByDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })
                let offset = (UTCDate.calendar.component(.weekday, from: month) + 5) % 7
                let count = UTCDate.calendar.range(of: .day, in: .month, for: month)!.count
                let maxValue = max(days.map { abs($0.absProfit) }.max() ?? 1, 0.01)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 6) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                        Text($0).font(.system(size: 10)).foregroundStyle(LensTheme.muted).padding(.bottom, 3)
                            .accessibilityIdentifier("calendarWeekday-\($0)")
                    }
                    // One identity space keeps padding cells distinct from dates after changing months.
                    ForEach(-offset..<count, id: \.self) { index in
                        if index < 0 {
                            Color.clear.frame(height: 35).accessibilityHidden(true)
                        } else {
                        let date = UTCDate.calendar.date(byAdding: .day, value: index, to: month)!
                        let day = daysByDate[UTCDate.string(date)]
                        let future = date > UTCDate.calendar.startOfDay(for: Date())
                        let color = day.map { $0.absProfit == 0 ? LensTheme.muted : LensTheme.pnl($0.absProfit) } ?? LensTheme.muted
                        Button { selectedDay = day } label: {
                            Text("\(index + 1)").font(.system(size: 12, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity).frame(height: 35)
                                .foregroundStyle(future ? LensTheme.muted.opacity(0.4) : color)
                                .background(color.opacity(day.map { 0.07 + abs($0.absProfit) / maxValue * 0.27 } ?? 0.04), in: RoundedRectangle(cornerRadius: 9))
                                .overlay { if selectedDay?.date == day?.date, day != nil { RoundedRectangle(cornerRadius: 9).stroke(LensTheme.tint, lineWidth: 1.5) } }
                        }.buttonStyle(.plain).disabled(future || day == nil || isLoading)
                            .accessibilityIdentifier("calendarDay-\(index + 1)")
                            .accessibilityLabel("\(UTCDate.string(date))，\(day.map { Fmt.number($0.absProfit, signed: true) } ?? "暂无数据")")
                        }
                    }
                }
                HStack {
                    Text(selectedDay.map { "\($0.date) · \($0.tradeCount) 笔" } ?? report.map { "\($0.count) 笔" } ?? "计算中…")
                    Spacer()
                    Text(store.privacyMode ? "••••" : Fmt.number(selectedDay?.absProfit ?? report?.profit, signed: true))
                        .foregroundStyle(LensTheme.pnl(selectedDay?.absProfit ?? report?.profit))
                }.font(.system(size: 11, design: .monospaced)).foregroundStyle(LensTheme.muted)
                    .accessibilityIdentifier("calendarSummary")
                if !isLoading, report == nil || (report?.missingValues ?? 0) > 0 {
                    Text("该月数据暂不完整").font(.caption).foregroundStyle(LensTheme.loss)
                }
            }
        }
        .task(id: requestID) {
            isLoading = true
            selectedDay = nil
            let value = await store.report(for: CalendarMonth.filter(month))
            guard !Task.isCancelled else { return }
            report = value
            isLoading = false
        }
    }
    private func shift(_ delta: Int) {
        month = UTCDate.calendar.date(byAdding: .month, value: delta, to: month)!
        report = nil
        selectedDay = nil
        isLoading = true
    }
}
