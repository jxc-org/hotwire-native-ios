import UIKit
import WebKit

/// Applies theme colors to UIKit. `UIAppearance` proxies only affect views
/// that enter a window later, so live bars, windows and web views are also
/// walked and restyled directly.
///
/// View-controller backgrounds are deliberately left alone, so apps' per-rule
/// `background_color` overrides survive a live update.
enum ThemeApplier {
    static func colors(for theme: HotwireTheme) -> [HotwireTheme.Role: UIColor] {
        var colors: [HotwireTheme.Role: UIColor] = [:]
        for role in HotwireTheme.Role.allCases {
            let light = UIColor(hotwireHex: theme.light[role])
            if let dark = theme.dark.map({ UIColor(hotwireHex: $0[role]) }) {
                colors[role] = UIColor { $0.userInterfaceStyle == .dark ? dark : light }
            } else {
                colors[role] = light
            }
        }
        return colors
    }

    static func navigationBarAppearance(
        colors: [HotwireTheme.Role: UIColor],
        config: ThemeConfig
    ) -> UINavigationBarAppearance {
        let appearance: UINavigationBarAppearance
        if let base = config.baseNavigationBarAppearance?.copy() as? UINavigationBarAppearance {
            appearance = base
        } else {
            appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
        }

        appearance.backgroundColor = colors[.surface]
        appearance.shadowColor = colors[.border]

        let titleColor = config.navTitleRole == .text ? colors[.text] : colors[.accent]
        appearance.titleTextAttributes[.foregroundColor] = titleColor
        appearance.largeTitleTextAttributes[.foregroundColor] = titleColor
        return appearance
    }

    static func apply(colors: [HotwireTheme.Role: UIColor], config: ThemeConfig, windows: [UIWindow]) {
        let appearance = navigationBarAppearance(colors: colors, config: config)
        let accent = colors[.accent]
        let background = colors[.background]

        // Future bars.
        style(navigationBar: UINavigationBar.appearance(), appearance: appearance, tint: accent)

        // Live bars, windows and web views.
        for window in windows {
            window.tintColor = accent
            window.backgroundColor = background
            if let root = window.rootViewController {
                visit(root) { viewController in
                    if let navigationController = viewController as? UINavigationController {
                        style(navigationBar: navigationController.navigationBar, appearance: appearance, tint: accent)
                    }
                    if let background,
                       let visitable = viewController as? VisitableViewController,
                       visitable.isViewLoaded,
                       let webView = visitable.visitableView.webView {
                        style(webView: webView, background: background)
                    }
                }
            }
        }
    }

    static func style(navigationBar: UINavigationBar, appearance: UINavigationBarAppearance, tint: UIColor?) {
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        if #available(iOS 15.0, *) {
            navigationBar.compactScrollEdgeAppearance = appearance
        }
        navigationBar.tintColor = tint
    }

    static func style(webView: WKWebView, background: UIColor) {
        webView.isOpaque = false
        webView.backgroundColor = background
        webView.scrollView.backgroundColor = background
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = background
        }
    }

    /// Depth-first over children and presented view controllers.
    private static func visit(_ viewController: UIViewController, _ body: (UIViewController) -> Void) {
        body(viewController)
        for child in viewController.children {
            visit(child, body)
        }
        if let presented = viewController.presentedViewController,
           presented.presentingViewController === viewController {
            visit(presented, body)
        }
    }
}

extension UIColor {
    /// `#RRGGBB`; callers validate the format first.
    convenience init(hotwireHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
