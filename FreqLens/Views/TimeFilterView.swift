import SwiftUI

struct TimeFilterView: View {
    @Environment(LensStore.self) private var store
    @State private var showCustom = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                filterButtons
                ScrollView(.horizontal) { filterButtons }.scrollIndicators(.hidden)
            }
            if store.isComputingReport {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini).tint(LensTheme.tint)
                    Text(store.reportFilter.map { "切换中 · 暂显示\($0.title)" } ?? "计算中…")
                }.font(.system(size: 11)).foregroundStyle(LensTheme.muted)
                    .accessibilityIdentifier("periodLoading")
            } else if store.timeFilter.preset == .custom {
                Text(store.timeFilter.title).font(.system(size: 11, design: .monospaced)).foregroundStyle(LensTheme.tint)
                    .accessibilityIdentifier("customRangeLabel")
            }
        }
        .sheet(isPresented: $showCustom) { CustomRangeView(filter: store.timeFilter) }
        .sensoryFeedback(.selection, trigger: store.timeFilter.preset)
    }

    private var filterButtons: some View {
        HStack(spacing: 6) {
            ForEach(TradeTimeFilter.Preset.allCases, id: \.self) { preset in
                Button {
                    if preset == .custom { showCustom = true }
                    else { store.timeFilter = TradeTimeFilter(preset: preset) }
                } label: {
                    Text(preset.title).font(.system(size: 11, weight: .medium)).fixedSize()
                        .padding(.horizontal, 12).padding(.vertical, 12)
                        .foregroundStyle(store.timeFilter.preset == preset ? LensTheme.selectionText : LensTheme.muted)
                        .background(store.timeFilter.preset == preset ? LensTheme.selection : LensTheme.card, in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("range-\(preset.rawValue)")
                    .accessibilityAddTraits(store.timeFilter.preset == preset ? .isSelected : [])
            }
        }
    }
}

struct CustomRangeView: View {
    var filter: TradeTimeFilter
    @Environment(LensStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("开始日期", selection: $start, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("rangeStartDate")
                    DatePicker("结束日期", selection: $end, in: ...Date(), displayedComponents: .date)
                        .accessibilityIdentifier("rangeEndDate")
                } footer: {
                    Text("包含开始日和结束日的全部已平仓交易。日期按 UTC 计算，总览、分析和历史会同步更新。")
                }
                if start > end {
                    Text("结束日期不能早于开始日期。").foregroundStyle(LensTheme.loss)
                }
                Button("应用时间筛选") {
                    store.timeFilter = TradeTimeFilter(preset: .custom, start: start, end: end)
                    dismiss()
                }.disabled(start > end).accessibilityIdentifier("applyTimeRange")
            }
            .environment(\.timeZone, UTCDate.calendar.timeZone)
            .navigationTitle("自定义时间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear {
                let interval = filter.bounds() ?? TradeTimeFilter().bounds()!
                start = interval.start
                end = UTCDate.calendar.date(byAdding: .day, value: -1, to: interval.end)!
            }
        }.presentationDetents([.medium, .large])
    }
}

struct ReportAvailability: View {
    @Environment(LensStore.self) private var store
    var body: some View {
        if store.report == nil {
            LensCard {
                HStack(spacing: 12) {
                    if store.isComputingReport || store.isRefreshing || store.isLoadingCache { ProgressView() }
                    else { Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(LensTheme.tint) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.isComputingReport ? "整理统计…" : (store.isRefreshing || store.isLoadingCache ? "读取历史…" : "历史未完整"))
                            .font(.subheadline.weight(.medium))
                        Text(store.isComputingReport ? "正在使用本机数据计算" : "完整历史用于计算胜率")
                            .font(.caption).foregroundStyle(LensTheme.muted)
                    }
                    if !store.isRefreshing && !store.isComputingReport && !store.isLoadingCache { Button("重试") { Task { await store.refresh() } }.font(.caption) }
                }
            }
        } else if let report = store.report, report.missingValues > 0 {
            Label("有 \(report.missingValues) 笔交易缺少盈亏数据，区间收益和胜率暂不可计算。", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(LensTheme.loss)
        }
    }
}
