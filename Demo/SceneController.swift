import HotwireNative
import SafariServices
import UIKit
import WebKit

final class SceneController: UIResponder {
    var window: UIWindow?

    private let rootURL = Demo.current
    private lazy var tabBarController = HotwireTabBarController(
        navigatorDelegate: self,
        lazyLoadTabs: true
    )
    private lazy var splitController = HotwireSplitViewController(
        configuration: .init(name: "main", startLocation: rootURL),
        navigatorDelegate: self
    )

    private var activeNavigator: Navigator {
        Demo.usesSplitView ? splitController.activeNavigator : tabBarController.activeNavigator
    }

    // MARK: - Authentication

    private func promptForAuthentication() {
        // Clean up empty screen from 401 response.
        activeNavigator.pop(animated: false)

        let authURL = rootURL.appendingPathComponent("/session/new")
        activeNavigator.route(authURL)
    }

    // MARK: - Split demo script

    /// Launch with `-HotwireSplit -SplitDemoScript` to drive the split demo without taps,
    /// for simulator screenshots: open a detail, push inside it, then flip the width
    /// size class (collapse on iPad, expand on iPhone) and flip it back.
    private func runSplitDemoScript() {
        let steps: [(TimeInterval, String, () -> Void)] = [
            (5, "open detail /navigation from the list", { [self] in
                splitController.route(rootURL.appendingPathComponent("/navigation"))
            }),
            (10, "push /navigation/second inside the detail pane", { [self] in
                splitController.activeNavigator.route(rootURL.appendingPathComponent("/navigation/second"))
            }),
            (15, "flip width size class", { [self] in
                if #available(iOS 17.0, *) {
                    let current = splitController.traitCollection.horizontalSizeClass
                    splitController.traitOverrides.horizontalSizeClass = current == .regular ? .compact : .regular
                }
            }),
            (20, "restore width size class", { [self] in
                if #available(iOS 17.0, *) {
                    splitController.traitOverrides.remove(UITraitHorizontalSizeClass.self)
                }
            }),
        ]

        for (delay, name, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                step()
                // Log the resulting hierarchy so the report can quote it next to the screenshots.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    let primary = splitController.primaryNavigator.rootViewController.viewControllers
                    let secondary = splitController.secondaryNavigator.rootViewController.viewControllers
                    NSLog("SPLIT-DEMO t=%.0f %@ | collapsed=%d | primary=%@ | secondary=%@",
                          delay, name, splitController.isCollapsed ? 1 : 0,
                          primary.map(Self.describe).joined(separator: " > "),
                          secondary.map(Self.describe).joined(separator: " > "))
                }
            }
        }
    }

    private static func describe(_ controller: UIViewController) -> String {
        if let navigation = controller as? UINavigationController {
            return "[nav: " + navigation.viewControllers.map(describe).joined(separator: " > ") + "]"
        }
        if let url = (controller as? Visitable)?.currentVisitableURL {
            return url.path.isEmpty ? "/" : url.path
        }
        return String(describing: type(of: controller))
    }
}

extension SceneController: UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)

        if Demo.usesSplitView {
            window?.rootViewController = splitController
            window?.makeKeyAndVisible()
            splitController.start()

            if ProcessInfo.processInfo.arguments.contains("-SplitDemoScript") {
                runSplitDemoScript()
            }
        } else {
            window?.rootViewController = tabBarController
            window?.makeKeyAndVisible()
            tabBarController.load(HotwireTab.all)
        }
    }
}

extension SceneController: NavigatorDelegate {
    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        switch proposal.viewController {
        case NumbersViewController.pathConfigurationIdentifier:
            return .acceptCustom(NumbersViewController(
                url: proposal.url,
                navigator: navigator
                )
            )

        default:
            return .accept
        }
    }

    func visitableDidFailRequest(_ visitable: any Visitable, error: HotwireNativeError, retryHandler: RetryBlock?) {
        switch error {
        case .http(.client(.unauthorized)):
            promptForAuthentication()
        default:
            if let errorPresenter = visitable as? ErrorPresenter {
                errorPresenter.presentError(error) {
                    retryHandler?()
                }
            } else {
                let alert = UIAlertController(title: "Visit failed!", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                activeNavigator.present(alert, animated: true)
            }
        }
    }
}
