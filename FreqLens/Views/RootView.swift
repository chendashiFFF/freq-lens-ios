import SwiftUI

struct RootView: View {
    @Environment(LensStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var selection = 0
    @State private var showConnection = false
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue
    var body: some View {
        TabView(selection: $selection) {
            Tab("总览", systemImage: "square.grid.2x2", value: 0) {
                NavigationStack { OverviewView(showConnection: $showConnection) }
            }
            Tab("持仓", systemImage: "chart.line.uptrend.xyaxis", value: 1) {
                NavigationStack { PositionsView(showConnection: $showConnection) }
            }
            Tab("分析", systemImage: "chart.bar.xaxis", value: 2) {
                NavigationStack { AnalyticsView(showConnection: $showConnection) }
            }
            Tab("历史", systemImage: "clock.arrow.circlepath", value: 3) {
                NavigationStack { HistoryView(showConnection: $showConnection) }
            }
        }
        .tabBarMinimizeBehavior(.never)
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .sheet(isPresented: $showConnection) { ConnectionView() }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--tab"), args.indices.contains(i + 1) { selection = Int(args[i + 1]) ?? 0 }
        }
    }
}
