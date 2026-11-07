@testable import HotwireNative
import XCTest

final class SystemNavigationRouteDecisionHandlerTests: XCTestCase {
    let navigatorConfiguration = Navigator.Configuration(
        name: "test",
        startLocation: URL(string: "https://my.app.com")!
    )
    var navigator: Navigator!
    var route: SystemNavigationRouteDecisionHandler!

    override func setUp() {
        route = SystemNavigationRouteDecisionHandler()
        navigator = Navigator(configuration: navigatorConfiguration)
    }

    func test_handling_matching_result_stops_navigation() {
        let url = URL(string: "https://external.com/page")!
        let result = route.handle(location: url, configuration: navigatorConfiguration, navigator: navigator)
        XCTAssertEqual(result, Router.Decision.cancel)
    }

    func test_url_on_external_domain_matches() {
        let url = URL(string: "https://external.com/page")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_url_without_subdomain_matches() {
        let url = URL(string: "https://app.com/page")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_url_on_app_domain_does_not_match() {
        let url = URL(string: "https://my.app.com/page")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertFalse(result)
    }

    func test_non_http_urls_match() {
        let url = URL(string: "file:///path/to/file")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_sms_urls_match() {
        let url = URL(string: "sms:1-408-555-1212")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_same_host_webcal_url_matches() {
        let url = URL(string: "webcal://my.app.com/cal/x")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertTrue(result)
    }

    func test_same_host_mailto_and_tel_urls_match() {
        for string in ["mailto://my.app.com/x", "tel://my.app.com/x"] {
            let result = route.matches(location: URL(string: string)!, configuration: navigatorConfiguration)

            XCTAssertTrue(result, string)
        }
    }

    func test_same_host_http_url_does_not_match() {
        let url = URL(string: "http://my.app.com/page")!
        let result = route.matches(location: url, configuration: navigatorConfiguration)

        XCTAssertFalse(result)
    }
}
