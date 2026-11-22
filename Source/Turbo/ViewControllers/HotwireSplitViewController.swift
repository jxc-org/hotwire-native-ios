import UIKit

// SPIKE (DUO-4): an opt-in two-pane container. Not production quality.
// See the PR description and duo-4/report.md for what works and what doesn't.

public extension Navigation {
    /// Which pane of a `HotwireSplitViewController` a URL opens in.
    /// Set with the `"pane"` path-configuration property.
    /// A URL with no `"pane"` property stays in the pane it was proposed from.
    enum Pane: String {
        case primary
        case secondary
    }
}

/// A two-pane container: a list (primary) and a detail (secondary), each with its own `Navigator`.
///
/// On a wide screen (regular width: iPad, iPhone Duo inner display) the panes sit side by side.
/// On a narrow one (compact width: iPhone, iPad Split View, Duo outer display) UIKit collapses
/// them into one stack, with the detail pushed on top of the list.
///
/// Opt-in happens in two places, so an app that uses neither is unchanged:
/// 1. The app uses this controller as its root instead of a `Navigator` or `HotwireTabBarController`.
/// 2. Path-configuration rules mark detail URLs with `"pane": "secondary"`.
///
/// A visit proposed by the primary pane to a `secondary` URL replaces the secondary pane's stack.
/// Visits inside the secondary pane push onto it, as usual.
open class HotwireSplitViewController: UISplitViewController, NavigationHandler {
    public let primaryNavigator: Navigator
    public let secondaryNavigator: Navigator

    /// - Parameters:
    ///   - configuration: the primary (list) navigator's configuration.
    ///   - secondaryStartLocation: an optional page for the detail pane before anything is chosen.
    ///     When `nil`, `placeholder` is shown instead.
    ///   - placeholder: a native "nothing selected" screen for the detail pane.
    ///   - navigatorDelegate: the app's delegate. It receives every proposal the split controller
    ///     doesn't redirect between panes, from both navigators.
    public init(
        configuration: Navigator.Configuration,
        secondaryStartLocation: URL? = nil,
        placeholder: UIViewController? = nil,
        navigatorDelegate: NavigatorDelegate? = nil
    ) {
        let router = PaneRouter(appDelegate: navigatorDelegate)
        self.router = router
        self.secondaryStartLocation = secondaryStartLocation
        self.placeholder = placeholder ?? PlaceholderViewController()

        primaryNavigator = Navigator(configuration: configuration, delegate: router)
        secondaryNavigator = Navigator(
            configuration: .init(
                name: "\(configuration.name)-secondary",
                startLocation: secondaryStartLocation ?? configuration.startLocation
            ),
            delegate: router
        )

        super.init(style: .doubleColumn)
        router.split = self
        delegate = self

        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        setViewController(primaryNavigator.rootViewController, for: .primary)
        setViewController(secondaryNavigator.rootViewController, for: .secondary)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Use init(configuration:...) instead.")
    }

    /// Visits the primary start location, and the secondary one if given.
    public func start() {
        primaryNavigator.start()

        if secondaryStartLocation != nil {
            secondaryNavigator.start()
        } else {
            secondaryNavigator.rootViewController.setViewControllers([placeholder], animated: false)
        }
    }

    /// The navigator the person is most likely looking at: the detail when it has content
    /// and is on screen, otherwise the list.
    public var activeNavigator: Navigator {
        if hasSecondaryContent && (!isCollapsed || secondaryIsOnTopWhenCollapsed) {
            return secondaryNavigator
        }
        return primaryNavigator
    }

    public func navigator(for pane: Navigation.Pane) -> Navigator {
        switch pane {
        case .primary: primaryNavigator
        case .secondary: secondaryNavigator
        }
    }

    // MARK: NavigationHandler

    /// Routes through the primary navigator, so `"pane": "secondary"` rules still apply.
    open func route(_ url: URL, options: VisitOptions?, parameters: [String: Any]?) {
        primaryNavigator.route(url, options: options, parameters: parameters)
    }

    open func route(_ proposal: VisitProposal) {
        primaryNavigator.route(proposal)
    }

    // MARK: Pane routing

    /// Replaces the secondary pane's stack with `proposal`, and brings that pane on screen
    /// (pushes it when collapsed).
    open func routeToSecondary(_ proposal: VisitProposal) {
        var properties = proposal.properties
        if proposal.context == .default {
            properties["presentation"] = Navigation.Presentation.replaceRoot.rawValue
        }

        secondaryNavigator.route(VisitProposal(
            url: proposal.url,
            options: proposal.options,
            properties: properties,
            parameters: proposal.parameters
        ))
        show(.secondary)
    }

    /// Routes `proposal` in the primary pane, and brings that pane on screen.
    open func routeToPrimary(_ proposal: VisitProposal) {
        primaryNavigator.route(proposal)
        show(.primary)
    }

    // MARK: Private

    private let router: PaneRouter
    private let secondaryStartLocation: URL?
    private let placeholder: UIViewController

    var hasSecondaryContent: Bool {
        secondaryNavigator.rootViewController.viewControllers.contains { $0 !== placeholder }
    }

    private var secondaryIsOnTopWhenCollapsed: Bool {
        // When collapsed, UIKit pushes the secondary navigation controller onto the primary one.
        primaryNavigator.rootViewController.viewControllers.contains(secondaryNavigator.rootViewController)
    }
}

// MARK: - UISplitViewControllerDelegate

extension HotwireSplitViewController: UISplitViewControllerDelegate {
    /// When collapsing, keep the detail on top if one was chosen; otherwise show the list.
    open func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        hasSecondaryContent ? .secondary : .primary
    }
}

// MARK: - PaneRouter

/// Sits between both navigators and the app's delegate. Redirects proposals whose
/// `"pane"` differs from the navigator they were proposed in, and forwards everything else.
final class PaneRouter: NavigatorDelegate {
    weak var split: HotwireSplitViewController?
    weak var appDelegate: NavigatorDelegate?

    init(appDelegate: NavigatorDelegate?) {
        self.appDelegate = appDelegate
    }

    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        if let split {
            switch (proposal.pane, navigator === split.primaryNavigator) {
            case (.secondary, true):
                split.routeToSecondary(proposal)
                return .reject
            case (.primary, false):
                split.routeToPrimary(proposal)
                return .reject
            default:
                break
            }
        }

        return appDelegate?.handle(proposal: proposal, from: navigator) ?? .accept
    }

    func visitableDidFailRequest(_ visitable: Visitable, error: HotwireNativeError, retryHandler: RetryBlock?) {
        if let appDelegate {
            appDelegate.visitableDidFailRequest(visitable, error: error, retryHandler: retryHandler)
        } else if let errorPresenter = visitable as? ErrorPresenter {
            errorPresenter.presentError(error, retryHandler: retryHandler)
        }
    }

    func didReceiveAuthenticationChallenge(_ challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let appDelegate {
            appDelegate.didReceiveAuthenticationChallenge(challenge, completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func formSubmissionDidStart(to url: URL) { appDelegate?.formSubmissionDidStart(to: url) }
    func formSubmissionDidFinish(at url: URL) { appDelegate?.formSubmissionDidFinish(at: url) }
    func requestDidFinish(at url: URL) { appDelegate?.requestDidFinish(at: url) }
}

// MARK: - Placeholder

private final class PlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let label = UILabel()
        label.text = "Nothing selected"
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}
