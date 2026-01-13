import HotwireNative
import UIKit

final class AppNavigatorDelegate: NavigatorDelegate {
    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        // Accept all proposals with the default view controller.
        // Customize this to return .acceptCustom(viewController) for native screens.
        .accept
    }

    func visitableDidFailRequest(_ visitable: Visitable, error: Error, retryHandler: RetryBlock?) {
        if let errorPresenter = visitable as? ErrorPresenter {
            errorPresenter.presentError(error, retryHandler: retryHandler)
        }
    }
}
