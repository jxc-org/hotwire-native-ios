import HotwireNative
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAppearance()
        configureHotwire()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // Make navigation and tab bars opaque.
    private func configureAppearance() {
        UINavigationBar.appearance().scrollEdgeAppearance = .init()
        UITabBar.appearance().scrollEdgeAppearance = .init()
    }

    private func configureHotwire() {
        // Load the path configuration
        // The server configuration replaces the bundled one once it loads. The demo server's
        // copy has no "pane" rules, so split mode uses the bundled file only.
        var sources: [PathConfiguration.Source] = [
            .file(Bundle.main.url(forResource: "path-configuration", withExtension: "json")!)
        ]
        if !Demo.usesSplitView {
            sources.append(.server(Demo.current.appendingPathComponent("configurations/ios_v1.json")))
        }
        Hotwire.loadPathConfiguration(from: sources)

        // Set an optional custom user agent application prefix.
        Hotwire.config.applicationUserAgentPrefix = "Hotwire Demo;"

        // Register bridge components
        Hotwire.registerBridgeComponents([
            FormComponent.self,
            MenuComponent.self,
            OverflowMenuComponent.self,
        ])

        // Set configuration options
        Hotwire.config.backButtonDisplayMode = .minimal
        Hotwire.config.showDoneButtonOnModals = true
        Hotwire.config.animateReplaceActions = true
#if DEBUG
        Hotwire.config.debugLoggingEnabled = true
#endif
    }
}
