@testable import HotwireNative
import OHHTTPStubs
import OHHTTPStubsSwift
import XCTest

final class JSFetchRecoveryHandlerTests: XCTestCase {
    private let handler = JSFetchRecoveryHandler()
    private let testURL = URL(string: "https://example.com/page")!

    override func setUp() {
        super.setUp()
        // Hotwire.config's one-time initializer creates a WKProcessPool, and
        // WebKit traps (EXC_BREAKPOINT in InitializeWebKit2) if that first
        // happens off the main thread. resolve(location:) reads
        // Hotwire.config from a background task, so when this suite ran first
        // or alone it crashed the test host. setUp runs on the main thread.
        _ = Hotwire.config
    }

    override func tearDown() {
        HTTPStubs.removeAllStubs()
        RedirectingURLProtocol.reset()
    }

    // MARK: - No redirect

    func test_resolve_noRedirect_whenResponseURLMatchesRequestURL() async throws {
        stub(condition: isAbsoluteURLString(testURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    // MARK: - Same-origin redirect

    func test_resolve_sameOriginRedirect_whenResponseURLDiffersButSameHost() async throws {
        let redirectURL = URL(string: "https://example.com/other")!

        // A 301 that URLSession follows, landing at a different URL on the same host.
        // See RedirectingURLProtocol for why the redirect hop isn't an OHHTTPStubs stub.
        RedirectingURLProtocol.redirect(testURL, to: redirectURL)

        stub(condition: isAbsoluteURLString(redirectURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .sameOriginRedirect(redirectURL))
    }

    // MARK: - Cross-origin redirect

    func test_resolve_crossOriginRedirect_whenResponseURLHasDifferentHost() async throws {
        let redirectURL = URL(string: "https://other.com/page")!

        RedirectingURLProtocol.redirect(testURL, to: redirectURL)

        stub(condition: isAbsoluteURLString(redirectURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .crossOriginRedirect(redirectURL))
    }

    // MARK: - Request failure

    func test_resolve_throwsRequestFailed_whenNetworkErrorOccurs() async {
        stub(condition: isAbsoluteURLString(testURL.absoluteString)) { _ in
            HTTPStubsResponse(error: URLError(.notConnectedToInternet))
        }

        do {
            _ = try await handler.resolve(location: testURL)
            XCTFail("Expected requestFailed error")
        } catch let error as JSFetchRecoveryError {
            guard case .requestFailed = error else {
                return XCTFail("Expected .requestFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Non-2xx responses (after 1b fix: any HTTP response is valid)

    func test_resolve_noRedirect_whenNon2xxResponseWithSameURL() async throws {
        // A 401 or 500 response still means the server is reachable.
        // After removing the status code validation, this should return .noRedirect.
        stub(condition: isAbsoluteURLString(testURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 401, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    func test_resolve_noRedirect_when500ResponseWithSameURL() async throws {
        stub(condition: isAbsoluteURLString(testURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 500, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .noRedirect)
    }

    // MARK: - Non-2xx with redirect

    func test_resolve_detectsRedirect_evenWhenFinalResponseIsNon2xx() async throws {
        let redirectURL = URL(string: "https://other.com/login")!

        RedirectingURLProtocol.redirect(testURL, to: redirectURL)

        stub(condition: isAbsoluteURLString(redirectURL.absoluteString)) { _ in
            HTTPStubsResponse(data: Data(), statusCode: 401, headers: nil)
        }

        let result = try await handler.resolve(location: testURL)
        XCTAssertEqual(result, .crossOriginRedirect(redirectURL))
    }
}

// MARK: - Equatable for test assertions

extension JSFetchRecoveryHandler.Result: Equatable {
    public static func == (lhs: JSFetchRecoveryHandler.Result, rhs: JSFetchRecoveryHandler.Result) -> Bool {
        switch (lhs, rhs) {
        case (.noRedirect, .noRedirect):
            return true
        case (.sameOriginRedirect(let lhsURL), .sameOriginRedirect(let rhsURL)):
            return lhsURL == rhsURL
        case (.crossOriginRedirect(let lhsURL), .crossOriginRedirect(let rhsURL)):
            return lhsURL == rhsURL
        default:
            return false
        }
    }
}
