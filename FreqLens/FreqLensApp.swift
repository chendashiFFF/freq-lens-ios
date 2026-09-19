import SwiftUI

@main
struct FreqLensApp: App {
    @State private var store = LensStore(forceDemo: ProcessInfo.processInfo.arguments.contains("--demo"))
    init() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "darkAppearancePreferred") {
            defaults.set(AppAppearance.dark.rawValue, forKey: "appearance")
            defaults.set(true, forKey: "darkAppearancePreferred")
        }
    }
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(LensTheme.tint)
        }
    }
}
