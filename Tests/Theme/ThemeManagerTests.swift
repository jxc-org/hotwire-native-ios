@testable import HotwireNative
import OHHTTPStubs
import OHHTTPStubsSwift
import UIKit
import WebKit
import XCTest

/// End-to-end theming against a real key window on the simulator: a stubbed
/// server serves `settings.theme`, `PathConfiguration` posts its update
/// notification, and the visible navigation bar, window and web views recolor.
class ThemeManagerTests: XCTestCase {
    private let serverURL = URL(string: "http://turbo.test/theme-test-configuration.json")!
    private let manager = ThemeManager.shared
    private let defaults = UserDefaults(suiteName: "HotwireNative.ThemeManagerTests")!

    private var originalConfig: HotwireConfig!
    private var originalWindows: (() -> [UIWindow])!
    private var window: UIWindow!
    private var navigationController: UINavigationController!

    /// What the stubbed server serves as `settings.theme`; `nil` omits it.
    private var serverTheme: Any?
    /// When set, the stubbed server fails as if offline.
    private var serverOffline = false
    private var serverHit: XCTestExpectation?

    private static let themeA = theme(surface: "#FFFFFF", border: "#EDE0D4", text: "#1A1614", accent: "#B84428", background: "#FFF8F2")
    private static let themeB = theme(surface: "#0B3D2E", border: "#14532D", text: "#F0FDF4", accent: "#FDE68A", background: "#052E16")
    private static let bundledTheme = theme(surface: "#111111", border: "#222222", text: "#333333", accent: "#444444", background: "#555555")

    override func setUp() {
        super.setUp()
        originalConfig = Hotwire.config
        originalWindows = manager.windows
        manager.reset()
        defaults.removePersistentDomain(forName: "HotwireNative.ThemeManagerTests")
        manager.userDefaults = defaults
        clearCache()

        serverTheme = Self.themeA
        serverOffline = false
        stub(condition: isAbsoluteURLString(serverURL.absoluteString)) { [unowned self] _ in
            defer { serverHit?.fulfill() }
            if serverOffline {
                return HTTPStubsResponse(error: URLError(.notConnectedToInternet))
            }
            var settings: [String: Any] = ["marker": UUID().uuidString]
            settings["theme"] = serverTheme
            return HTTPStubsResponse(jsonObject: ["settings": settings, "rules": []], statusCode: 200, headers: [:])
        }

        navigationController = UINavigationController(rootViewController: UIViewController())
        window = UIWindow()
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        manager.windows = { [unowned self] in [window] }
    }

    override func tearDown() {
        Hotwire.config = originalConfig
        manager.reset()
        manager.userDefaults = .standard
        manager.windows = originalWindows
        HTTPStubs.removeAllStubs()
        clearCache()
        window.isHidden = true
        window = nil
        resetAppearanceProxy()
        super.tearDown()
    }

    private func resetAppearanceProxy() {
        let proxy = UINavigationBar.appearance()
        proxy.standardAppearance = UINavigationBarAppearance()
        proxy.scrollEdgeAppearance = nil
        proxy.compactAppearance = nil
        if #available(iOS 15.0, *) {
            proxy.compactScrollEdgeAppearance = nil
        }
        proxy.tintColor = nil
    }

    // MARK: - Off by default

    func test_offByDefault_registersNoObserversAndChangesNoAppearance() throws {
        XCTAssertFalse(Hotwire.config.theme.isEnabled)
        let bar = navigationController.navigationBar
        let barBackground = bar.standardAppearance.backgroundColor
        let barTint = bar.tintColor
        let windowTint = window.tintColor
        let windowBackground = window.backgroundColor

        // A themed config loads and refreshes, but neither opt-in is on.
        let configuration = loadServerConfiguration()
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)
        let webView = Hotwire.config.makeWebView()

        XCTAssertNil(configuration.foregroundObserver, "no foreground observer without refreshOnForeground")
        XCTAssertFalse(manager.isObserving, "no update observer without theme.isEnabled")
        XCTAssertNil(Hotwire.theme[.accent])
        XCTAssertNil(defaults.data(forKey: ThemeManager.storageKey))
        XCTAssertEqual(bar.standardAppearance.backgroundColor, barBackground)
        XCTAssertEqual(bar.tintColor, barTint)
        XCTAssertEqual(window.tintColor, windowTint)
        XCTAssertEqual(window.backgroundColor, windowBackground)
        XCTAssertTrue(webView.isOpaque)
    }

    // MARK: - Applying

    func test_enablingAfterLoad_appliesTheThemeToTheVisibleBarAndWindow() {
        loadServerConfiguration()
        enableTheme()

        assertBar(showsTheme: Self.themeA)
        assertColor(window.tintColor, "#B84428")
        assertColor(window.backgroundColor, "#FFF8F2")
        assertColor(Hotwire.theme[.surface], "#FFFFFF")
    }

    func test_enablingBeforeLoad_appliesOnTheUpdateNotification() {
        enableTheme()
        XCTAssertTrue(manager.isObserving)
        XCTAssertNil(Hotwire.theme[.accent])

        loadServerConfiguration()

        assertBar(showsTheme: Self.themeA)
    }

    /// Acceptance: a visible nav bar recolors when an update notification arrives.
    func test_visibleBarRecolors_whenAnUpdateNotificationArrives() {
        let configuration = loadServerConfiguration()
        enableTheme()
        let bar = navigationController.navigationBar
        XCTAssertNotNil(bar.window, "bar is on screen")
        assertBar(showsTheme: Self.themeA)

        serverTheme = Self.themeB
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)

        XCTAssertTrue(bar === navigationController.navigationBar, "same live bar, not a new one")
        assertBar(showsTheme: Self.themeB)
        assertColor(window.tintColor, "#FDE68A")
        assertColor(Hotwire.theme[.accent], "#FDE68A")
    }

    func test_presentedModalBarRecolorsToo() {
        let configuration = loadServerConfiguration()
        enableTheme()
        let modal = UINavigationController(rootViewController: UIViewController())
        navigationController.present(modal, animated: false)

        serverTheme = Self.themeB
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)

        assertColor(modal.navigationBar.standardAppearance.backgroundColor, "#0B3D2E")
        assertColor(modal.navigationBar.tintColor, "#FDE68A")
    }

    func test_liveWebViewBackground_updatesButViewControllerBackgroundIsLeftAlone() {
        let visitable = VisitableViewController(url: URL(string: "https://example.com")!)
        navigationController.pushViewController(visitable, animated: false)
        visitable.loadViewIfNeeded()
        visitable.view.backgroundColor = .magenta // an app's per-rule background_color
        let webView = WKWebView()
        visitable.visitableView.activateWebView(webView, forVisitable: visitable)

        loadServerConfiguration()
        enableTheme()

        assertColor(webView.backgroundColor, "#FFF8F2")
        assertColor(webView.scrollView.backgroundColor, "#FFF8F2")
        if #available(iOS 15.0, *) {
            assertColor(webView.underPageBackgroundColor, "#FFF8F2")
        }
        XCTAssertFalse(webView.isOpaque)
        XCTAssertEqual(visitable.view.backgroundColor, .magenta)
    }

    func test_newWebViews_getTheThemedBackground() {
        loadServerConfiguration()
        enableTheme()

        let webView = Hotwire.config.makeWebView()

        assertColor(webView.backgroundColor, "#FFF8F2")
        XCTAssertFalse(webView.isOpaque)
    }

    func test_navTitleRoleText_andBaseAppearanceFontsSurvive() throws {
        let font = UIFont.systemFont(ofSize: 21, weight: .black)
        let base = UINavigationBarAppearance()
        base.configureWithOpaqueBackground()
        base.titleTextAttributes = [.font: font]
        let baseBackground = base.backgroundColor
        let baseTitleColor = base.titleTextAttributes[.foregroundColor] as? UIColor

        loadServerConfiguration()
        enableTheme { $0.navTitleRole = .text; $0.baseNavigationBarAppearance = base }

        let attributes = navigationController.navigationBar.standardAppearance.titleTextAttributes
        XCTAssertEqual(attributes[.font] as? UIFont, font)
        assertColor(attributes[.foregroundColor] as? UIColor, "#1A1614")
        XCTAssertEqual(base.backgroundColor, baseBackground, "the app's base appearance is copied, not mutated")
        XCTAssertEqual(base.titleTextAttributes[.foregroundColor] as? UIColor, baseTitleColor)
    }

    func test_darkPalette_becomesDynamicColors() {
        serverTheme = ["version": 1, "light": HotwireThemeTests.light, "dark": HotwireThemeTests.dark]
        loadServerConfiguration()
        enableTheme()

        let accent = Hotwire.theme[.accent]
        assertColor(accent?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)), "#B84428")
        assertColor(accent?.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), "#F08A6C")
    }

    func test_onlyAppWindowsAreTouched_notUIKitOverlayWindows() {
        // Stands in for UIKit's keyboard / text-effects windows.
        let overlay = UIWindow()
        overlay.windowLevel = .alert + 1
        overlay.rootViewController = UINavigationController(rootViewController: UIViewController())
        overlay.isHidden = false
        defer { overlay.isHidden = true }
        let overlayBar = (overlay.rootViewController as! UINavigationController).navigationBar
        let overlayBackground = overlay.backgroundColor
        let overlayBarBackground = overlayBar.standardAppearance.backgroundColor
        manager.windows = { [unowned self] in [window, overlay] }

        loadServerConfiguration()
        enableTheme()

        assertColor(window.backgroundColor, "#FFF8F2")
        XCTAssertEqual(overlay.backgroundColor, overlayBackground, "overlay window background untouched")
        XCTAssertEqual(overlayBar.standardAppearance.backgroundColor, overlayBarBackground, "overlay hierarchy untouched")
    }

    /// Review fix: a reused modal (Navigator keeps one modal navigation
    /// controller) must not keep a theme applied directly while it was on screen.
    /// Review fix: a reused modal (Navigator keeps one modal navigation
    /// controller) must not keep a theme applied directly while it was on
    /// screen. This test host has no window scene, so UIKit never completes a
    /// real present/dismiss transition; the same lifecycle is modelled by
    /// putting the reused controller in a window, taking it out of every
    /// window, and showing it again.
    func test_reusedModal_showsTheLatestThemeWhenShownAgain() {
        let configuration = loadServerConfiguration()
        enableTheme()
        let modal = UINavigationController(rootViewController: UIViewController())
        let modalWindow = UIWindow()
        defer { modalWindow.isHidden = true }
        manager.windows = { [unowned self] in [window, modalWindow] }

        // On screen while theme B arrives: styled directly.
        modalWindow.rootViewController = modal
        modalWindow.isHidden = false
        serverTheme = Self.themeB
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)
        assertColor(modal.navigationBar.standardAppearance.backgroundColor, "#0B3D2E")

        // "Dismissed": in no window while theme C arrives.
        modalWindow.rootViewController = nil
        XCTAssertNil(modal.view.window)
        let themeC = Self.theme(surface: "#1E3A8A", border: "#1D4ED8", text: "#EFF6FF", accent: "#93C5FD", background: "#172554")
        serverTheme = themeC
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)

        // "Presented" again: shows C, not the stale B.
        modalWindow.rootViewController = modal
        assertColor(modal.navigationBar.standardAppearance.backgroundColor, "#1E3A8A")
        assertColor(modal.navigationBar.scrollEdgeAppearance?.backgroundColor, "#1E3A8A")
        assertColor(modal.navigationBar.tintColor, "#93C5FD")
    }

    func test_offScreenWebViews_areRestyledOnUpdate() {
        let configuration = loadServerConfiguration()
        enableTheme()
        // Made by the library but not in any window yet (e.g. a modal session's).
        let webView = Hotwire.config.makeWebView()
        assertColor(webView.backgroundColor, "#FFF8F2")

        serverTheme = Self.themeB
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)

        assertColor(webView.backgroundColor, "#052E16")
        assertColor(webView.scrollView.backgroundColor, "#052E16")
    }

    func test_serverThemeEqualToTheBundledOne_isStillPersisted() throws {
        enableTheme()
        serverTheme = Self.bundledTheme
        let configuration = PathConfiguration()
        Hotwire.config.pathConfiguration = configuration
        configuration.sources = [.file(try bundledFile()), .server(serverURL)]
        waitForUpdate(of: configuration)

        assertBar(showsTheme: Self.bundledTheme)
        XCTAssertEqual(storedTheme()?.light.accent, "#444444")
    }

    func test_rejection_isLoggedToACustomLog_withTheReasonButNotThePayload() {
        let spy = ThemeLogSpy()
        Hotwire.config.log = spy
        let configuration = loadServerConfiguration()
        enableTheme()

        var unknownVersion = Self.themeB
        unknownVersion["version"] = 2
        serverTheme = unknownVersion
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)

        let warnings = spy.messages(for: .warning)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings.first?.contains("unsupported theme version 2") == true, "\(warnings)")
        XCTAssertFalse(warnings.joined().contains("#0B3D2E"), "no payload in the log")
    }

    // MARK: - Rejection

    /// Acceptance: an invalid or unknown-version theme leaves the current one in place.
    func test_invalidOrUnknownVersionTheme_keepsTheCurrentTheme() {
        let configuration = loadServerConfiguration()
        enableTheme()
        assertBar(showsTheme: Self.themeA)

        var unknownVersion = Self.themeB
        unknownVersion["version"] = 2
        var badHex = Self.themeB
        badHex["light"] = (Self.themeB["light"] as! [String: Any]).merging(["accent": "#FDE68"]) { $1 }
        var missingRole = Self.themeB
        missingRole["light"] = (Self.themeB["light"] as! [String: Any]).filter { $0.key != "border" }

        for rejected in [unknownVersion, badHex, missingRole, "not an object"] as [Any] {
            serverTheme = rejected
            configuration.refreshServerSources()
            waitForUpdate(of: configuration)

            assertBar(showsTheme: Self.themeA)
            assertColor(Hotwire.theme[.accent], "#B84428")
            XCTAssertEqual(storedTheme()?.light.accent, "#B84428")
        }

        // A missing theme is not an error either: keep the current one.
        serverTheme = nil
        configuration.refreshServerSources()
        waitForUpdate(of: configuration)
        assertBar(showsTheme: Self.themeA)
    }

    // MARK: - Last good theme

    /// Acceptance: the last good theme is used on the next launch when the
    /// network is unavailable, even if iOS purged the cached download and
    /// only the (older) bundled file is left.
    func test_lastGoodTheme_isUsedOnTheNextLaunchWhenOffline() throws {
        // Launch 1: the server serves theme B, which is persisted.
        serverTheme = Self.themeB
        loadServerConfiguration()
        enableTheme()
        XCTAssertEqual(storedTheme()?.light.accent, "#FDE68A")

        // Relaunch: in-memory state gone, fresh UI, Caches purged, network down.
        Hotwire.config = originalConfig
        manager.reset()
        clearCache()
        serverOffline = true
        resetAppearanceProxy()
        window.isHidden = true
        navigationController = UINavigationController(rootViewController: UIViewController())
        window = UIWindow()
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        XCTAssertNil(navigationController.navigationBar.standardAppearance.backgroundColor, "fresh bar is unthemed")

        serverHit = expectation(description: "offline fetch attempted")
        let configuration = PathConfiguration()
        configuration.sources = [.file(try bundledFile()), .server(serverURL)]
        Hotwire.config.pathConfiguration = configuration
        enableTheme()
        wait(for: [serverHit!], timeout: 5)
        drainMainQueue()

        XCTAssertEqual(configuration.lastUpdateSource, .file, "only the bundled file loaded")
        assertBar(showsTheme: Self.themeB)
        assertColor(Hotwire.theme[.accent], "#FDE68A")
    }

    func test_bundledTheme_isUsedOnFirstLaunch_butNotPersisted() throws {
        serverOffline = true
        serverHit = expectation(description: "offline fetch attempted")
        enableTheme()
        let configuration = PathConfiguration()
        Hotwire.config.pathConfiguration = configuration
        configuration.sources = [.file(try bundledFile()), .server(serverURL)]
        wait(for: [serverHit!], timeout: 5)
        drainMainQueue()

        assertBar(showsTheme: Self.bundledTheme)
        XCTAssertNil(defaults.data(forKey: ThemeManager.storageKey))
    }

    func test_serverThemeReplacesTheBundledThemeInTheSameLaunch() throws {
        enableTheme()
        let configuration = PathConfiguration()
        Hotwire.config.pathConfiguration = configuration
        configuration.sources = [.file(try bundledFile()), .server(serverURL)]
        waitForUpdate(of: configuration)

        assertBar(showsTheme: Self.themeA)
        XCTAssertEqual(storedTheme()?.light.accent, "#B84428")
    }

    func test_tamperedStoredTheme_isDiscarded() throws {
        let palette = HotwireTheme.Palette(background: "#FFFFFF", surface: "#FFFFFF", border: "#FFFFFF", text: "#FFFFFF", accent: "bad")
        defaults.set(try JSONEncoder().encode(HotwireTheme(version: 1, light: palette, dark: nil)), forKey: ThemeManager.storageKey)

        enableTheme()

        XCTAssertNil(manager.currentTheme)
        XCTAssertNil(defaults.data(forKey: ThemeManager.storageKey))
    }

    // MARK: - Helpers

    private static func theme(surface: String, border: String, text: String, accent: String, background: String) -> [String: Any] {
        ["version": 1, "light": ["background": background, "surface": surface, "border": border, "text": text, "accent": accent], "dark": NSNull()]
    }

    private func enableTheme(_ configure: (inout ThemeConfig) -> Void = { _ in }) {
        var theme = ThemeConfig(isEnabled: true)
        configure(&theme)
        Hotwire.config.theme = theme
    }

    /// Installs a server-only path configuration as the app's and waits for its download.
    @discardableResult
    private func loadServerConfiguration() -> PathConfiguration {
        let configuration = PathConfiguration()
        Hotwire.config.pathConfiguration = configuration
        configuration.sources = [.server(serverURL)]
        waitForUpdate(of: configuration)
        return configuration
    }

    private func waitForUpdate(of configuration: PathConfiguration) {
        let updated = expectation(forNotification: PathConfiguration.didUpdateNotification, object: configuration) { _ in
            configuration.lastUpdateSource == .server
        }
        wait(for: [updated], timeout: 5)
        drainMainQueue()
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private func bundledFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("theme-bundled-path-configuration.json")
        let json: [String: Any] = ["settings": ["theme": Self.bundledTheme], "rules": []]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    private func storedTheme() -> HotwireTheme? {
        defaults.data(forKey: ThemeManager.storageKey).flatMap { try? JSONDecoder().decode(HotwireTheme.self, from: $0) }
    }

    private func clearCache() {
        try? FileManager.default.removeItem(at: PathConfigurationLoader(sources: []).configurationCacheURL(for: serverURL))
    }

    private func assertBar(showsTheme theme: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        let palette = theme["light"] as! [String: String]
        let bar = navigationController.navigationBar
        for appearance in [bar.standardAppearance, bar.scrollEdgeAppearance, bar.compactAppearance] {
            assertColor(appearance?.backgroundColor, palette["surface"]!, file: file, line: line)
            assertColor(appearance?.shadowColor, palette["border"]!, file: file, line: line)
            assertColor(appearance?.titleTextAttributes[.foregroundColor] as? UIColor, palette["accent"]!, file: file, line: line)
        }
        assertColor(bar.tintColor, palette["accent"]!, file: file, line: line)
    }

    private func assertColor(_ color: UIColor?, _ hex: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let color else {
            return XCTFail("expected \(hex), got nil", file: file, line: line)
        }
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let actual = String(format: "#%02X%02X%02X", Int(round(red * 255)), Int(round(green * 255)), Int(round(blue * 255)))
        XCTAssertEqual(actual, hex.uppercased(), file: file, line: line)
    }
}

private final class ThemeLogSpy: Logger {
    private(set) var entries: [(level: LogLevel, message: String)] = []

    func log(message: String, level: LogLevel, file: String, function: String, line: UInt) {
        entries.append((level, message))
    }

    func messages(for level: LogLevel) -> [String] {
        entries.filter { $0.level == level }.map(\.message)
    }
}
