import UIKit

/// The current theme colors, for bridge components and app code:
/// `Hotwire.theme[.accent]`. Each value is `nil` when theming is disabled or
/// no valid theme has loaded yet. With a `dark` palette, colors are dynamic.
public struct HotwireThemeColors {
    let colors: [HotwireTheme.Role: UIColor]

    public subscript(role: HotwireTheme.Role) -> UIColor? {
        colors[role]
    }
}

public extension Hotwire {
    /// Colors from the path configuration's `settings.theme`.
    /// Requires `Hotwire.config.theme.isEnabled`.
    static var theme: HotwireThemeColors {
        HotwireThemeColors(colors: ThemeManager.shared.publicColors)
    }
}
