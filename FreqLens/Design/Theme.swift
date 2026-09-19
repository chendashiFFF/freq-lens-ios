import SwiftUI
import Charts

enum LensTheme {
    static let tint = Color(light: 0xD95B13, dark: 0xFF9654)
    static let selection = Color(light: 0xFF873D, dark: 0xFF9654)
    static let selectionText = Color(light: 0x2C1608, dark: 0x2C1608)
    static let gain = Color(light: 0x287D68, dark: 0x83CBB3)
    static let loss = Color(light: 0xC35550, dark: 0xF39186)
    static let background = Color(light: 0xF5F2ED, dark: 0x171715)
    static let card = Color(light: 0xFFFEFC, dark: 0x23231F)
    static let soft = Color(light: 0xFBE9DA, dark: 0x392A21)
    static let muted = Color(light: 0x837C71, dark: 0xAAA598)
    static let grid = Color(light: 0xE6E0D7, dark: 0x3B3B34)
    static func pnl(_ value: Double?) -> Color {
        guard let value else { return muted }
        return value < 0 ? loss : gain
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

enum Fmt {
    static func number(_ value: Double?, digits: Int = 2, signed: Bool = false) -> String {
        guard let value, value.isFinite else { return "—" }
        let string = abs(value).formatted(.number.grouping(.automatic).precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
        return (value < 0 ? "−" : (signed && value > 0 ? "+" : "")) + string
    }
    static func percent(_ ratio: Double?, signed: Bool = false) -> String {
        guard let ratio, ratio.isFinite else { return "—" }
        return number(ratio * 100, digits: 2, signed: signed) + "%"
    }
    static func price(_ value: Double?) -> String {
        guard let value else { return "—" }
        return number(value, digits: value < 1 ? 6 : (value < 100 ? 4 : 2))
    }
    static func compact(_ value: Double) -> String {
        if abs(value) >= 1_000 { return number(value / 1_000, digits: 1) + "k" }
        return number(value, digits: 0)
    }
    static func duration(from: Date, to: Date = Date()) -> String {
        let hours = max(0, Int(to.timeIntervalSince(from) / 3600))
        if hours >= 24 { return "\(hours / 24)天 \(hours % 24)小时" }
        if hours == 0 { return "\(max(0, Int(to.timeIntervalSince(from) / 60)))分钟" }
        return "\(hours)小时"
    }
}

struct LensCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(LensTheme.card, in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(LensTheme.grid.opacity(0.55), lineWidth: 0.6) }
    }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(2.2).foregroundStyle(LensTheme.muted)
    }
}

struct SectionHeading: View {
    var title: String
    var detail: String = ""
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 19, weight: .semibold))
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(LensTheme.muted) }
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var detail: String
    var symbol: String
    var color: Color = .primary
    var body: some View {
        LensCard(padding: 17) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title).font(.caption).foregroundStyle(LensTheme.muted)
                    Spacer(minLength: 0)
                    Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(LensTheme.tint)
                }
                Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.65)
                Text(detail).font(.system(size: 10)).foregroundStyle(LensTheme.muted).lineLimit(1)
            }
        }
    }
}

struct CoinIcon: View {
    var symbol: String
    var size: CGFloat = 42
    private var color: Color {
        switch symbol {
        case "BTC": Color(light: 0xB7802B, dark: 0xE3B66B)
        case "ETH": Color(light: 0x677BAB, dark: 0xAFBFF0)
        case "SOL": LensTheme.tint
        default: Color(light: 0x627E9A, dark: 0xB2CBE6)
        }
    }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34).fill(color.opacity(0.11))
            if symbol == "BTC" { Image(systemName: "bitcoinsign").font(.system(size: size * 0.48, weight: .medium)) }
            else { Text(String(symbol.prefix(1))).font(.system(size: size * 0.42, weight: .semibold, design: .rounded)) }
        }.foregroundStyle(color).frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct TradeRow: View {
    var trade: Trade
    @Environment(LensStore.self) private var store
    var body: some View {
        HStack(spacing: 12) {
            CoinIcon(symbol: trade.symbol)
            VStack(alignment: .leading, spacing: 5) {
                Text(trade.symbol).font(.system(size: 16, weight: .semibold))
                Text(trade.isOpen ? "\(trade.direction) · \(Fmt.duration(from: trade.openedAt))" : (trade.closedAt?.formatted(.dateTime.month().day().hour().minute()) ?? "—"))
                    .font(.system(size: 11)).foregroundStyle(LensTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(store.privacyMode ? "••••" : Fmt.number(trade.pnl, signed: true))
                    .font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit()
                Text(Fmt.percent(trade.ratio, signed: true)).font(.system(size: 11, weight: .medium)).monospacedDigit()
            }.foregroundStyle(LensTheme.pnl(trade.pnl))
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 10).contentShape(Rectangle())
    }
}

struct DataStatus: View {
    @Environment(LensStore.self) private var store
    var body: some View {
        if store.isDemo {
            Text("演示数据").font(.system(size: 10, design: .monospaced)).foregroundStyle(LensTheme.muted)
        } else if let error = store.errorMessage, !store.isRefreshing {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wifi.exclamationmark").foregroundStyle(LensTheme.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.snapshot == nil ? "未能同步" : "离线缓存").font(.caption.weight(.medium))
                    Text(error).font(.caption2).foregroundStyle(LensTheme.muted)
                }
                Spacer(minLength: 0)
                Button("重试") { Task { await store.refresh() } }.font(.caption)
            }.padding(14).background(LensTheme.soft, in: RoundedRectangle(cornerRadius: 18))
        } else if store.isRefreshing || store.isLoadingCache || store.isCached {
            HStack(spacing: 8) {
                if store.isRefreshing || store.isLoadingCache { ProgressView().controlSize(.mini) }
                else { Image(systemName: "clock.arrow.circlepath") }
                Text(store.isLoadingCache ? "读取缓存…" : (store.isRefreshing ? (store.snapshot == nil ? "同步中…" : "缓存可用 · 同步中…") : "本机缓存"))
                Spacer()
                if let date = store.snapshot?.fetchedAt { Text(date.formatted(.dateTime.hour().minute())) }
            }.font(.system(size: 11)).foregroundStyle(LensTheme.muted)
                .accessibilityIdentifier("syncStatus")
        }
    }
}

struct RefreshFootnote: View {
    @Environment(LensStore.self) private var store
    var body: some View {
        if let date = store.snapshot?.fetchedAt, !store.isDemo {
            Text("\(date.formatted(.dateTime.hour().minute())) 更新 · UTC 统计")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(LensTheme.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }
}

struct DashboardToolbar: ToolbarContent {
    @Environment(LensStore.self) private var store
    @Binding var showConnection: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showConnection = true } label: {
                Image(systemName: "slider.horizontal.3")
            }.accessibilityLabel("服务器连接").accessibilityIdentifier("serverButton")
        }
    }
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: "跟随系统"; case .light: "浅色"; case .dark: "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance = AppAppearance.dark.rawValue
    var body: some View {
        Menu {
            Picker("外观", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.rawValue) { value in Text(value.title).tag(value.rawValue) }
            }
        } label: {
            Image(systemName: appearance == "dark" ? "moon.fill" : "circle.lefthalf.filled")
        }.accessibilityLabel("外观设置").accessibilityIdentifier("appearanceButton")
    }
}
