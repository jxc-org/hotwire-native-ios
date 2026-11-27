import UIKit

/// Opt-in configuration for applying the path configuration's
/// `settings.theme` to native UI. Set it on `Hotwire.config.theme`.
///
/// Off by default: unless `isEnabled` is set, the library never touches
/// appearance proxies, bars, windows or web views.
public struct ThemeConfig {
    public enum NavTitleRole {
        case accent
        case text
    }

    /// Apply `settings.theme` on load and on every path-configuration update.
    public var isEnabled = false

    /// The app's base navigation-bar appearance (fonts, title attributes,
    /// background effect). The theme copies it and sets only colors: fill
    /// (`surface`), hairline (`border`) and title color (`navTitleRole`).
    /// When `nil`, an opaque default appearance is used.
    public var baseNavigationBarAppearance: UINavigationBarAppearance?

    /// Which role colors the navigation-bar title.
    public var navTitleRole: NavTitleRole = .accent

    public init(
        isEnabled: Bool = false,
        baseNavigationBarAppearance: UINavigationBarAppearance? = nil,
        navTitleRole: NavTitleRole = .accent
    ) {
        self.isEnabled = isEnabled
        self.baseNavigationBarAppearance = baseNavigationBarAppearance
        self.navTitleRole = navTitleRole
    }
}
