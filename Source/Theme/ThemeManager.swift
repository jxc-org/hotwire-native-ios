import OSLog
import UIKit
import WebKit

/// Owns the current theme: reads it from path-configuration settings,
/// validates it, keeps the last good one in `UserDefaults`, and applies it.
///
/// Driven by `Hotwire.config` changes. Does nothing (no observer, no
/// appearance changes) unless `Hotwire.config.theme.isEnabled` is set.
///
/// Main thread only: every entry point that touches UIKit hops to (or
/// asserts) the main thread.
final class ThemeManager {
    static let shared = ThemeManager()

    static let storageKey = "HotwireNative.theme.lastGood"

    /// Injectable for tests.
    var userDefaults: UserDefaults = .standard

    /// The windows to restyle on a live update. Injectable for tests.
    var windows: () -> [UIWindow] = {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    private(set) var config = ThemeConfig()
    private(set) var currentTheme: HotwireTheme?
    private(set) var colors: [HotwireTheme.Role: UIColor] = [:]
    private weak var pathConfiguration: PathConfiguration?
    private var observer: NSObjectProtocol?

    /// Every bar and web view styled so far, restyled on each update even when
    /// off screen (a reused modal, a web view waiting in a session).
    private let styledNavigationBars = NSHashTable<UINavigationBar>.weakObjects()
    private let styledWebViews = NSHashTable<WKWebView>.weakObjects()

    var isObserving: Bool { observer != nil }

    /// The app's `Hotwire.config.log`, if set; otherwise warnings go to `osLog`.
    private var customLog: Logger?

    /// Theme warnings are logged even when Hotwire debug logging is off, with
    /// the reason marked public so it is readable in production. Reasons name
    /// the failed check, never the payload.
    private static let osLog = os.Logger(
        subsystem: Bundle.module.bundleIdentifier ?? "HotwireNative",
        category: "Theme"
    )

    // MARK: - Configuration

    /// Called from `Hotwire.config`'s `didSet`. Hops to the main thread if needed.
    func configDidChange(_ hotwireConfig: HotwireConfig) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.configDidChange(hotwireConfig) }
            return
        }

        customLog = hotwireConfig.log
        let newConfig = hotwireConfig.theme
        let oldConfig = config
        config = newConfig

        guard newConfig.isEnabled else {
            stopObserving()
            return
        }

        startObserving()

        var themeChanged = false
        if currentTheme == nil, let restored = restoreLastGoodTheme() {
            setTheme(restored)
            themeChanged = true
        }

        let pathConfiguration = hotwireConfig.pathConfiguration
        if self.pathConfiguration !== pathConfiguration {
            self.pathConfiguration = pathConfiguration
            themeChanged = ingest(pathConfiguration.settings, source: pathConfiguration.lastUpdateSource) || themeChanged
        }

        let styleChanged = !oldConfig.isEnabled
            || oldConfig.navTitleRole != newConfig.navTitleRole
            || oldConfig.baseNavigationBarAppearance !== newConfig.baseNavigationBarAppearance

        if themeChanged || styleChanged {
            apply()
        }
    }

    // MARK: - Updates

    private func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: PathConfiguration.didUpdateNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.pathConfigurationDidUpdate(notification.object as? PathConfiguration)
        }
    }

    private func stopObserving() {
        guard let observer else { return }
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
    }

    private func pathConfigurationDidUpdate(_ updated: PathConfiguration?) {
        guard config.isEnabled, let updated, updated === pathConfiguration else { return }
        let settings = updated.settings
        let source = updated.lastUpdateSource
        let work = { [weak self] in
            guard let self, self.ingest(settings, source: source) else { return }
            self.apply()
        }
        Thread.isMainThread ? work() : DispatchQueue.main.async(execute: work)
    }

    /// Reads `settings.theme`. A missing theme is ignored; an invalid one is
    /// logged and rejected, keeping the current theme.
    ///
    /// A valid theme from the server (fresh or its cached copy) becomes
    /// current and is persisted as the last good theme. A theme from a bundled
    /// file or data source is only a fallback: it is used when there is no
    /// current theme (first launch) and is never persisted, so an offline
    /// launch with a purged cache keeps the newer last good theme.
    /// - Returns: whether the current theme changed.
    @discardableResult
    func ingest(_ settings: [String: AnyHashable], source: PathConfiguration.LoadSource?) -> Bool {
        guard let raw = settings["theme"], !(raw.base is NSNull) else {
            logger.debug("[theme] no settings.theme; keeping current theme")
            return false
        }

        let theme: HotwireTheme
        do {
            theme = try HotwireTheme(settingsValue: raw)
        } catch {
            warn("rejected settings.theme: \(error); keeping current theme")
            return false
        }

        let fromServer = source == .server || source == .cachedServer
        if !fromServer, currentTheme != nil {
            logger.debug("[theme] bundled theme ignored; keeping current theme")
            return false
        }

        // Persist before the equality check, so a server theme identical to
        // the bundled one in use still becomes the last good theme.
        if fromServer {
            persistLastGoodTheme(theme)
        }

        guard theme != currentTheme else { return false }
        setTheme(theme)
        return true
    }

    private func setTheme(_ theme: HotwireTheme) {
        currentTheme = theme
        colors = ThemeApplier.colors(for: theme)
    }

    // MARK: - Applying

    /// Main thread only.
    private func apply() {
        guard config.isEnabled, !colors.isEmpty else { return }
        let styled = ThemeApplier.apply(
            colors: colors,
            config: config,
            windows: windows(),
            previouslyStyled: .init(
                navigationBars: styledNavigationBars.allObjects,
                webViews: styledWebViews.allObjects
            )
        )
        styled.navigationBars.forEach(styledNavigationBars.add)
        styled.webViews.forEach(styledWebViews.add)
    }

    /// Gives a newly created web view the theme's background, and keeps it so
    /// later updates restyle it too. Main thread only.
    func style(newWebView webView: WKWebView) {
        guard config.isEnabled else { return }
        styledWebViews.add(webView)
        guard let background = colors[.background] else { return }
        ThemeApplier.style(webView: webView, background: background)
    }

    private func warn(_ reason: String) {
        if let customLog {
            customLog.warning("[theme] \(reason)")
        } else {
            Self.osLog.warning("[theme] \(reason, privacy: .public)")
        }
    }

    /// Colors exposed to apps through `Hotwire.theme`; empty when disabled.
    var publicColors: [HotwireTheme.Role: UIColor] {
        config.isEnabled ? colors : [:]
    }

    // MARK: - Persistence

    private func persistLastGoodTheme(_ theme: HotwireTheme) {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        userDefaults.set(data, forKey: Self.storageKey)
    }

    private func restoreLastGoodTheme() -> HotwireTheme? {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return nil }
        do {
            return try JSONDecoder().decode(HotwireTheme.self, from: data).validated()
        } catch {
            warn("discarding stored theme: \(error)")
            userDefaults.removeObject(forKey: Self.storageKey)
            return nil
        }
    }

    // MARK: - Testing

    /// Returns the manager to its initial, disabled state. Does not undo
    /// appearance changes already applied.
    func reset() {
        stopObserving()
        config = ThemeConfig()
        currentTheme = nil
        colors = [:]
        pathConfiguration = nil
        customLog = nil
        styledNavigationBars.removeAllObjects()
        styledWebViews.removeAllObjects()
    }
}
