@testable import HotwireNative
import XCTest

final class RouterTests: XCTestCase {
    let navigatorConfiguration = Navigator.Configuration(
        name: "test",
        startLocation: URL(string: "https://my.app.com")!
    )
    let proposal = VisitProposal(
        url: URL(string: "https://my.app.com/page")!,
        options: VisitOptions()
    )
    var router: Router!
    var navigator: NavigationSpy!

    override func setUp() {
        navigator = NavigationSpy()
    }

    func test_no_handlers_stops_navigation() {
        router = Router(decisionHandlers: [])

        let result = router.decideRoute(
            for: proposal,
            configuration: navigatorConfiguration,
            navigator: navigator
        )

        XCTAssertEqual(result, Router.Decision.cancel)
    }

    func test_no_matching_handlers_stops_navigation() {
        let noMatchSpy1 = NoMatchRouteDecisionHandlerSpy()
        let noMatchSpy2 = NoMatchRouteDecisionHandlerSpy()

        router = Router(
            decisionHandlers: [
                noMatchSpy1,
                noMatchSpy2
            ]
        )

        let result = router.decideRoute(
            for: proposal,
            configuration: navigatorConfiguration,
            navigator: navigator
        )

        XCTAssertTrue(noMatchSpy1.matchesWasCalled)
        XCTAssertFalse(noMatchSpy1.handleWasCalled)
        XCTAssertTrue(noMatchSpy2.matchesWasCalled)
        XCTAssertFalse(noMatchSpy2.handleWasCalled)
        XCTAssertEqual(result, Router.Decision.cancel)
    }

    func test_only_first_matching_handler_is_executed() {
        let noMatchSpy = NoMatchRouteDecisionHandlerSpy()
        let matchSpy1 = MatchRouteDecisionHandlerSpy()
        let matchSpy2 = MatchRouteDecisionHandlerSpy()

        router = Router(
            decisionHandlers: [
                noMatchSpy,
                matchSpy1,
                matchSpy2
            ]
        )

        let result = router.decideRoute(
            for: proposal,
            configuration: navigatorConfiguration,
            navigator: navigator
        )

        XCTAssertTrue(noMatchSpy.matchesWasCalled)
        XCTAssertFalse(noMatchSpy.handleWasCalled)
        XCTAssertTrue(matchSpy1.matchesWasCalled)
        XCTAssertTrue(matchSpy1.handleWasCalled)
        XCTAssertFalse(matchSpy2.matchesWasCalled)
        XCTAssertFalse(matchSpy2.handleWasCalled)
        XCTAssertEqual(result, Router.Decision.navigate)
    }

    // Uses a fresh HotwireConfig so the real default handler list is under test,
    // not a hand-built order (and not Hotwire.config, which other tests may mutate).
    func test_default_handlers_cancel_same_host_webcal_instead_of_navigating() {
        let router = HotwireConfig().router

        let result = router.decideRoute(
            for: VisitProposal(url: URL(string: "webcal://my.app.com/cal/x")!, options: VisitOptions()),
            configuration: navigatorConfiguration,
            navigator: navigator
        )

        XCTAssertEqual(result, Router.Decision.cancel)
    }

    func test_default_handlers_still_navigate_same_host_https() {
        let router = HotwireConfig().router

        let result = router.decideRoute(
            for: proposal,
            configuration: navigatorConfiguration,
            navigator: navigator
        )

        XCTAssertEqual(result, Router.Decision.navigate)
    }
}

final class NoMatchRouteDecisionHandlerSpy: RouteDecisionHandler {
    let name: String = "no-match-spy"
    var matchesWasCalled = false
    var handleWasCalled = false

    func matches(proposal: VisitProposal, configuration: HotwireNative.Navigator.Configuration) -> Bool {
        matchesWasCalled = true
        return false
    }

    func handle(proposal: VisitProposal, configuration: HotwireNative.Navigator.Configuration, navigator: HotwireNative.Navigating) -> HotwireNative.Router.Decision {
        handleWasCalled = true
        return .cancel
    }
}

final class MatchRouteDecisionHandlerSpy: RouteDecisionHandler {
    let name: String = "match-spy"
    var matchesWasCalled = false
    var handleWasCalled = false

    func matches(proposal: VisitProposal, configuration: HotwireNative.Navigator.Configuration) -> Bool {
        matchesWasCalled = true
        return true
    }

    func handle(proposal: VisitProposal, configuration: HotwireNative.Navigator.Configuration, navigator: HotwireNative.Navigating) -> HotwireNative.Router.Decision {
        handleWasCalled = true
        return .navigate
    }
}
