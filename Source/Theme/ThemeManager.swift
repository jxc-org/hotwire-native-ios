import UIKit
import WebKit

/// Owns the current theme: reads it from path-configuration settings,
/// validates it, keeps the last good one in `UserDefaults`, and applies it.
///
/// Driven by `Hotwire.config` changes. Does nothing (no observer, no
/// appearance changes) unless `Hotwire.config.theme.isEnabled` is set.
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

    var isObserving: Bool { observer != nil }

    /// Invalid themes are logged even when Hotwire debug logging is off.
    private let warningLogger: Logger = HotwireLogger.enabledLogger

    // MARK: - Configuration

    func configDidChange(_ hotwireConfig: HotwireConfig) {
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
            setTheme(restored, persist: false)
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
            warningLogger.warning("[theme] rejected settings.theme: \(error); keeping current theme")
            return false
        }

        let fromServer = source == .server || source == .cachedServer
        if !fromServer, currentTheme != nil {
            logger.debug("[theme] bundled theme ignored; keeping current theme")
            return false
        }

        guard theme != currentTheme else { return false }
        setTheme(theme, persist: fromServer)
        return true
    }

    private func setTheme(_ theme: HotwireTheme, persist: Bool) {
        currentTheme = theme
        colors = ThemeApplier.colors(for: theme)
        if persist {
            persistLastGoodTheme(theme)
        }
    }

    // MARK: - Applying

    private func apply() {
        guard config.isEnabled, !colors.isEmpty else { return }
        ThemeApplier.apply(colors: colors, config: config, windows: windows())
    }

    /// Gives a newly created web view the theme's background.
    func style(newWebView webView: WKWebView) {
        guard config.isEnabled, let background = colors[.background] else { return }
        ThemeApplier.style(webView: webView, background: background)
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
            warningLogger.warning("[theme] discarding stored theme: \(error)")
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
    }
}
