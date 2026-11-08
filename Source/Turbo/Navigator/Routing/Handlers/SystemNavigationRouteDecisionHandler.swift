import Foundation
import UIKit

/// Opens external URLs, and same-host non-http(s) URLs (`webcal:`, `mailto:`, `tel:`), via `openURL(_:options:completionHandler)`.
public final class SystemNavigationRouteDecisionHandler: RouteDecisionHandler {
    public let name: String = "system-navigation"

    public init() {}

    public func matches(proposal: VisitProposal,
                        configuration: Navigator.Configuration) -> Bool {
        let location = proposal.url
        guard location.scheme == "http" || location.scheme == "https" else {
            return true
        }

        if #available(iOS 16, *) {
            return configuration.startLocation.host() != location.host()
        }

        return configuration.startLocation.host != location.host
    }

    public func handle(proposal: VisitProposal,
                       configuration: Navigator.Configuration,
                       navigator: Navigating) -> Router.Decision {
        UIApplication.shared.open(proposal.url)

        return .cancel
    }
}
