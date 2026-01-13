import HotwireNative
import SwiftUI

@main
struct SwiftUIDemoApp: App {
    @State private var navigator: Navigator?

    init() {
        configureHotwire()
    }

    var body: some Scene {
        WindowGroup {
            HotwireRootView(tabs: HotwireTab.all)
                .navigatorDelegate(AppNavigatorDelegate())
                .ignoresSafeArea()
        }
    }

    private func configureHotwire() {
        // Load path configuration from local file and remote server.
        Hotwire.loadPathConfiguration(from: [
            .file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!)
        ])

        // Set an optional custom user agent prefix.
        Hotwire.config.applicationUserAgentPrefix = "Hotwire SwiftUI Demo;"

        // Configure UI options.
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.showDoneButtonOnModals = true
        #if DEBUG
        Hotwire.config.debugLoggingEnabled = true
        #endif
    }
}
