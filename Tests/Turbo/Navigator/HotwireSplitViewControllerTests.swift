@testable import HotwireNative
import XCTest

/// SPIKE (DUO-4): pane routing for `HotwireSplitViewController`.
@MainActor
final class HotwireSplitViewControllerTests: XCTestCase {
    private let rootURL = URL(string: "https://example.com")!
    private let listItemA = URL(string: "https://example.com/children/1")!
    private let listItemB = URL(string: "https://example.com/children/2")!
    private let detailSubpage = URL(string: "https://example.com/children/1/gifts")!

    private var spy: SpyNavigatorDelegate!
    private var split: HotwireSplitViewController!
    private var window: UIWindow!

    override func setUp() {
        spy = SpyNavigatorDelegate()
        split = HotwireSplitViewController(
            configuration: .init(name: "Test", startLocation: rootURL),
            navigatorDelegate: spy
        )
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        window.rootViewController = split
        window.makeKeyAndVisible()
        split.loadViewIfNeeded()
        split.start()
    }

    // MARK: - Path property

    func test_paneProperty_parsesKnownValues_andIgnoresOthers() {
        XCTAssertEqual(PathProperties(dictionaryLiteral: ("pane", "secondary")).pane, .secondary)
        XCTAssertEqual(PathProperties(dictionaryLiteral: ("pane", "primary")).pane, .primary)
        XCTAssertNil(PathProperties(dictionaryLiteral: ("pane", "sideways")).pane)
        XCTAssertNil(PathProperties().pane)
    }

    // MARK: - Routing

    func test_start_visitsPrimary_andShowsPlaceholderInSecondary() {
        XCTAssertEqual(urls(split.primaryNavigator), [rootURL])
        XCTAssertEqual(split.secondaryNavigator.rootViewController.viewControllers.count, 1)
        XCTAssertFalse(split.hasSecondaryContent)
    }

    func test_secondaryProposal_fromPrimary_replacesSecondaryStack() {
        split.route(proposal(listItemA, pane: "secondary"))
        XCTAssertEqual(urls(split.primaryNavigator), [rootURL])
        XCTAssertEqual(urls(split.secondaryNavigator), [listItemA])

        split.route(proposal(listItemB, pane: "secondary"))
        XCTAssertEqual(urls(split.primaryNavigator), [rootURL], "list stays put")
        XCTAssertEqual(urls(split.secondaryNavigator), [listItemB], "detail replaced, not pushed")
    }

    func test_unmarkedProposal_fromSecondary_pushesInSecondary() {
        split.route(proposal(listItemA, pane: "secondary"))
        split.secondaryNavigator.route(proposal(detailSubpage, pane: nil))

        XCTAssertEqual(urls(split.secondaryNavigator), [listItemA, detailSubpage])
        XCTAssertEqual(urls(split.primaryNavigator), [rootURL])
    }

    func test_primaryProposal_fromSecondary_goesToPrimary() {
        split.route(proposal(listItemA, pane: "secondary"))
        split.secondaryNavigator.route(proposal(listItemB, pane: "primary"))

        XCTAssertEqual(urls(split.primaryNavigator), [rootURL, listItemB])
        XCTAssertEqual(urls(split.secondaryNavigator), [listItemA])
    }

    func test_appDelegate_seesForwardedProposals_notRedirectedOnes() {
        split.route(proposal(listItemA, pane: "secondary"))

        // Start visit (primary) + the redirected proposal re-routed on the secondary navigator.
        // The original proposal on the primary navigator is consumed by the router.
        XCTAssertEqual(spy.handled.map(\.url), [rootURL, listItemA])
        XCTAssertTrue(spy.handledFrom.last === split.secondaryNavigator)
    }

    func test_appDelegate_rejecting_aSecondaryProposal_leavesPlaceholder() {
        spy.result = .reject
        split.route(proposal(listItemA, pane: "secondary"))
        XCTAssertFalse(split.hasSecondaryContent)
    }

    // MARK: - Collapse

    func test_collapse_showsListUntilADetailIsChosen_thenDetail() {
        XCTAssertEqual(split.splitViewController(split, topColumnForCollapsingToProposedTopColumn: .secondary), .primary)

        split.route(proposal(listItemA, pane: "secondary"))
        XCTAssertEqual(split.splitViewController(split, topColumnForCollapsingToProposedTopColumn: .primary), .secondary)
    }

    func test_activeNavigator_isSecondary_onceADetailIsShown_whenExpanded() {
        XCTAssertTrue(split.activeNavigator === split.primaryNavigator)
        split.route(proposal(listItemA, pane: "secondary"))
        if !split.isCollapsed {
            XCTAssertTrue(split.activeNavigator === split.secondaryNavigator)
        }
    }

    // MARK: - Helpers

    private func proposal(_ url: URL, pane: String?) -> VisitProposal {
        // Not animated: an animated replace_root doesn't land in `viewControllers` until the
        // transition finishes, which a synchronous test never waits for.
        var properties: PathProperties = ["animated": false]
        if let pane { properties["pane"] = pane }
        return VisitProposal(url: url, options: VisitOptions(action: .advance), properties: properties)
    }

    private func urls(_ navigator: Navigator) -> [URL?] {
        navigator.rootViewController.viewControllers.compactMap { $0 as? Visitable }.map(\.initialVisitableURL)
    }
}

private final class SpyNavigatorDelegate: NavigatorDelegate {
    var result: ProposalResult = .accept
    var handled: [VisitProposal] = []
    var handledFrom: [Navigator] = []

    func handle(proposal: VisitProposal, from navigator: Navigator) -> ProposalResult {
        handled.append(proposal)
        handledFrom.append(navigator)
        return result
    }
}
