import Foundation

/// Navigates in-app to http(s) URLs on the app's own host. Same-host URLs with
/// any other scheme (`webcal:`, `mailto:`, `tel:`, ...) can't be fetched as a
/// Turbo visit, so they are left for `SystemNavigationRouteDecisionHandler`.
public final class AppNavigationRouteDecisionHandler: RouteDecisionHandler {
    public let name: String = "app-navigation"

    public init() {}

    public func matches(proposal: VisitProposal,
                        configuration: Navigator.Configuration) -> Bool {
        let location = proposal.url
        guard location.scheme == "http" || location.scheme == "https" else {
            return false
        }

        if #available(iOS 16, *) {
            return configuration.startLocation.host() == location.host()
        }

        return configuration.startLocation.host == location.host
    }

    public func handle(proposal: VisitProposal,
                       configuration: Navigator.Configuration,
                       navigator: Navigating) -> Router.Decision {
        logger.info("Routing \(proposal.url.absoluteString)")
        return .navigate
    }
}
