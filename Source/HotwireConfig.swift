import SwiftUI
import UIKit
import WebKit

public struct HotwireConfig {
    public typealias WebViewBlock = (_ configuration: WKWebViewConfiguration) -> WKWebView

    /// Set a custom user agent application prefix for every WKWebView instance.
    ///
    /// The library will automatically append a substring to your prefix
    /// which includes:
    /// - "Hotwire Native iOS; Turbo Native iOS;"
    /// - "bridge-components: [your bridge components];"
    ///
    /// WKWebView's default user agent string will also appear at the
    /// beginning of the user agent.
    public var applicationUserAgentPrefix: String? = nil

    /// A single-token identifier for the app (e.g. `"Birthdaze"`).
    ///
    /// When set, the library adds an `"Identifier/version (build N)"` token
    /// to the user agent — sent on both WebView requests *and* the remote
    /// `path_configuration` request — so the server can identify the app and
    /// its version from any request (e.g. gating native screens to a minimum
    /// app version, or forcing upgrade prompts for old clients).
    ///
    /// The version and build are read automatically from the app bundle
    /// (`CFBundleShortVersionString` / `CFBundleVersion`). The identifier
    /// must be a single token (no spaces) so the server can parse it.
    public var appIdentifier: String? = nil

    /// When enabled, adds a `UIBarButtonItem` of type `.done` to the left
    /// navigation bar button item on screens presented modally.
    public var showDoneButtonOnModals = false

    /// Sets the back button display mode of `HotwireWebViewController`.
    public var backButtonDisplayMode = UINavigationItem.BackButtonDisplayMode.default

    /// Set to true to only show the tab bar on the root screens.
    public var hideTabBarWhenPushed = false

    /// Set to `true` to fade content when performing a `replace` visit.
    public var animateReplaceActions = false

    /// Enable or disable debug logging for Turbo visits and bridge elements
    /// connecting, disconnecting, receiving/sending messages, and more.
    public var debugLoggingEnabled = false {
        didSet {
            HotwireLogger.debugLoggingEnabled = debugLoggingEnabled
        }
    }
    
    /// Gets the user agent that the library builds to identify the app
    /// and its registered bridge components.
    ///
    /// The user agent includes:
    /// - An `"Identifier/version (build N)"` token, when `appIdentifier` is set
    /// - Your (optional) custom `applicationUserAgentPrefix`
    /// - "Hotwire Native iOS; Turbo Native iOS;"
    /// - "bridge-components: [your bridge components];"
    public var userAgent: String {
        get {
            let info = Bundle.main.infoDictionary
            return UserAgent.build(
                appIdentifier: appIdentifier,
                appVersion: info?["CFBundleShortVersionString"] as? String,
                appBuild: info?["CFBundleVersion"] as? String,
                applicationPrefix: applicationUserAgentPrefix,
                componentTypes: Hotwire.bridgeComponentTypes
            )
        }
    }

    // MARK: Turbo

    /// Configure options for matching path rules.
    public var pathConfiguration = PathConfiguration()


    /// The view controller used in `Navigator` for web requests. Must be
    /// a `VisitableViewController` or subclass.
    public var defaultViewController: (URL) -> VisitableViewController = { url in
        HotwireWebViewController(url: url)
    }

    /// The navigation controller used in `Navigator` for the main and modal stacks.
    /// Must be a `HotwireNavigationController` or subclass.
    public var defaultNavigationController: () -> UINavigationController = {
        HotwireNavigationController()
    }

    /// Optionally customize the web views used by each Turbo Session.
    /// Ensure you return a new instance each time.
    public var makeCustomWebView: WebViewBlock = { (configuration: WKWebViewConfiguration) in
        WKWebView.debugInspectable(configuration: configuration)
    }

    /// Optionally customize the native view presented when an error occurs.
    public var makeCustomErrorView: (Error, ErrorPresenter.Handler?) -> any ErrorPresentableView = { error, handler in
        DefaultErrorView(error: error, handler: handler)
    }

    // MARK: Bridge

    /// Set a custom JSON encoder when parsing bridge payloads.
    /// The custom encoder can be useful when you need to apply specific
    /// encoding strategies, like snake case vs. camel case
    public var jsonEncoder = JSONEncoder()

    /// Set a custom JSON decoder when parsing bridge payloads.
    /// The custom decoder can be useful when you need to apply specific
    /// decoding strategies, like snake case vs. camel case
    public var jsonDecoder = JSONDecoder()

    // MARK: - Internal

    public func makeWebView() -> WKWebView {
        let webView = makeCustomWebView(makeWebViewConfiguration())
        
        if !Hotwire.bridgeComponentTypes.isEmpty {
            Bridge.initialize(webView)
        }
        
        return webView
    }

    // MARK: - Private

    private let sharedProcessPool = WKProcessPool()

    var router = Router(
        decisionHandlers: [
            AppNavigationRouteDecisionHandler(),
            SafariViewControllerRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        ]
    )

    var webViewPolicyManager = WebViewPolicyManager(
        policyDecisionHandlers: [
            ReloadWebViewPolicyDecisionHandler(),
            NewWindowWebViewPolicyDecisionHandler(),
            ExternalNavigationWebViewPolicyDecisionHandler(),
            LinkActivatedWebViewPolicyDecisionHandler()
        ]
    )

    // A method (not a property) because we need a new instance for each web view.
    private func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences?.preferredContentMode = .mobile
        configuration.applicationNameForUserAgent = userAgent
        configuration.processPool = sharedProcessPool
        return configuration
    }
}
