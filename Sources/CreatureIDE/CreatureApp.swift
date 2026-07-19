#if canImport(SwiftUI)
import SwiftUI

@main
struct CreatureApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 1000, minHeight: 650)
                .background(Theme.ink)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}

#else

// SwiftUI is Apple-only, so off Apple the IDE cannot be built as a GUI. The
// executable still needs an entry point, so provide one that says so plainly
// rather than failing to link. The command-line `creature` is fully portable.
@main
struct CreatureIDEUnavailable {
    static func main() {
        print("CreatureIDE is a macOS app (SwiftUI). Use the `creature` command-line tool on this platform.")
    }
}

#endif
