import SwiftUI

struct HistoryDeletionView: View {
    @Environment(LensStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var months = 3
    @State private var customDate = Date()
    @State private var plan: DeletionPlan?
    @State private var isPreparing = false
    @State private var showConfirmation = false
    @State private var error: String?
    @State private var result: DeletionSummary?
    private var cutoff: Date {
        UTCDate.calendar.startOfDay(for: months == 0 ? customDate : UTCDate.calendar.date(byAdding: .month, value: -months, to: Date())!)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LensCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("删除历史交易").font(.title3.weight(.semibold))
                            Text("仅限已平仓记录。删除发生在服务器，无法撤销，会改变收益与胜率统计；不会撤销已经成交的交易。")
                                .font(.caption).foregroundStyle(LensTheme.muted)
                            Picker("早于", selection: $months) {
                                ForEach([1, 3, 6, 12], id: \.self) { Text("\($0) 个月前").tag($0) }
                                Text("自定义日期").tag(0)
                            }.pickerStyle(.menu).accessibilityIdentifier("deletionCutoff")
                            if months == 0 {
                                DatePicker("截止日期", selection: $customDate, in: ...Date(), displayedComponents: .date)
                                    .environment(\.timeZone, UTCDate.calendar.timeZone)
                            }
                            Text("平仓时间早于 \(UTCDate.string(cutoff)) 00:00 UTC，不含当天。")
                                .font(.system(size: 11, design: .monospaced)).foregroundStyle(LensTheme.muted)
                            Button {
                                isPreparing = true; error = nil; plan = nil; result = nil
                                let date = cutoff
                                Task {
                                    do { plan = try await store.previewDeletion(before: date) }
                                    catch { self.error = error.localizedDescription }
                                    isPreparing = false
                                }
                            } label: {
                                HStack {
                                    if isPreparing { ProgressView().controlSize(.small) }
                                    Text(isPreparing ? "读取记录…" : "预览记录")
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.bordered).accessibilityIdentifier("previewDeletion")
                        }
                    }.disabled(isPreparing || store.isDeletingHistory)

                    if store.isDeletingHistory {
                        LensCard {
                            VStack(alignment: .leading, spacing: 14) {
                                ProgressView(value: Double(store.deletionCompleted), total: Double(max(1, store.deletionTotal)))
                                Text("已确认删除 \(store.deletionCompleted) / \(store.deletionTotal) 笔").font(.subheadline)
                                Button("停止后续删除") { store.stopDeletingHistory() }.font(.caption)
                            }
                        }
                    } else if let result {
                        LensCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("已确认删除 \(result.deleted) 笔").font(.headline)
                                if result.stopped { Text("已停止后续删除").font(.caption) }
                                if let error = result.error {
                                    Text(error + "\n剩余记录请刷新核对。")
                                        .font(.caption).foregroundStyle(LensTheme.loss)
                                }
                            }
                        }
                    } else if let plan {
                        LensCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("\(plan.trades.count) 笔").font(.system(size: 42, weight: .bold, design: .rounded))
                                    .accessibilityIdentifier("deletionPreviewCount")
                                if let first = plan.trades.first?.closedAt, let last = plan.trades.last?.closedAt {
                                    Text("\(UTCDate.string(first)) — \(UTCDate.string(last))")
                                        .font(.caption.monospaced()).foregroundStyle(LensTheme.muted)
                                }
                                if store.isDemo { Text("演示预览 · 不执行删除").font(.caption).foregroundStyle(LensTheme.muted) }
                                Button(role: .destructive) { showConfirmation = true } label: {
                                    Text("删除这 \(plan.trades.count) 笔记录").frame(maxWidth: .infinity)
                                }.buttonStyle(.borderedProminent).tint(LensTheme.loss)
                                    .disabled(plan.trades.isEmpty || store.isDemo).accessibilityIdentifier("deleteHistoryRecords")
                                ForEach(plan.trades) { trade in
                                    HStack {
                                        Text("#\(trade.id)  \(trade.pair)")
                                        Spacer()
                                        Text(trade.closedAt.map(UTCDate.string) ?? "—").foregroundStyle(LensTheme.muted)
                                    }.font(.system(size: 11, design: .monospaced))
                                }
                            }
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(LensTheme.loss) }
                }.padding(22)
            }.background(LensTheme.background)
                .navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.disabled(store.isDeletingHistory || isPreparing) } }
                .interactiveDismissDisabled(store.isDeletingHistory || isPreparing)
                .onChange(of: months) { _, _ in plan = nil; result = nil }
                .onChange(of: customDate) { _, _ in plan = nil; result = nil }
                .alert("永久删除 \(plan?.trades.count ?? 0) 笔记录？", isPresented: $showConfirmation) {
                    Button("取消", role: .cancel) { }
                    Button("确认删除", role: .destructive) {
                        guard let approved = plan else { return }
                        Task { result = await store.deleteHistory(approved); plan = nil }
                    }
                } message: {
                    Text("服务器：\(store.activeProfile?.name ?? "")\n平仓时间早于 \(plan.map { UTCDate.string($0.cutoff) } ?? "") 00:00 UTC。此操作无法撤销，会改变历史统计。")
                }
        }
    }
}
