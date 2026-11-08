@testable import HotwireNative
import XCTest

final class AppNavigationRouteDecisionHandlerTest: XCTestCase {
    let navigatorConfiguration = Navigator.Configuration(
        name: "test",
        startLocation: URL(string: "https://my.app.com")!
    )
    var route: AppNavigationRouteDecisionHandler!
    var navigator: NavigationSpy!

    override func setUp() {
        route = AppNavigationRouteDecisionHandler()
        navigator = NavigationSpy()
    }

    private func proposal(for url: URL) -> VisitProposal {
        VisitProposal(url: url, options: VisitOptions())
    }

    func test_handling_matching_result_navigates() {
        let url = URL(string: "https://my.app.com/page")!
        let result = route.handle(proposal: proposal(for: url), configuration: navigatorConfiguration, navigator: navigator)
        XCTAssertEqual(result, Router.Decision.navigate)
    }

    func test_url_on_app_domain_matches() {
        let url = URL(string: "https://my.app.com/page")!
        let result = route.matches(proposal: proposal(for: url), configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_url_without_subdomain_does_not_match() {
        let url = URL(string: "https://app.com/page")!
        let result = route.matches(proposal: proposal(for: url), configuration: navigatorConfiguration)

        XCTAssertFalse(result)
    }

    func test_masqueraded_url_does_not_match() {
        let url = URL(string: "https://app.my.com@fake.domain")!
        let result = route.matches(proposal: proposal(for: url), configuration: navigatorConfiguration)

        XCTAssertFalse(result)
    }

    func test_same_host_webcal_url_does_not_match() {
        let url = URL(string: "webcal://my.app.com/cal/x")!
        let result = route.matches(proposal: proposal(for: url), configuration: navigatorConfiguration)

        XCTAssertFalse(result)
    }

    func test_same_host_mailto_and_tel_urls_do_not_match() {
        for string in ["mailto://my.app.com/x", "tel://my.app.com/x"] {
            let result = route.matches(proposal: proposal(for: URL(string: string)!), configuration: navigatorConfiguration)

            XCTAssertFalse(result, string)
        }
    }

    func test_same_host_http_url_matches() {
        let url = URL(string: "http://my.app.com/page")!
        let result = route.matches(proposal: proposal(for: url), configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }
}
