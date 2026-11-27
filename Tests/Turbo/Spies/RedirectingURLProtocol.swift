import Foundation

/// Answers registered URLs with a 301 redirect, honoring the URLProtocol
/// contract: report the redirect and stop.
///
/// Fork (not upstream): OHHTTPStubs 9.1.0 also sends a response and
/// `didFinishLoading` after reporting a stubbed redirect. With the async
/// `URLSession.data(for:)` API, that second completion races the redirected
/// request's completion and can resume the continuation twice, which traps
/// the test host (EXC_BREAKPOINT on the NSURLSession work queue). Seen on
/// whichever `JSFetchRecoveryHandlerTests` redirect test ran first.
///
/// Only the redirect hop goes through this protocol. The target URL is still
/// answered by an ordinary OHHTTPStubs stub.
final class RedirectingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var redirects: [URL: URL] = [:]

    /// Registers the protocol and makes requests for `source` redirect to `target`.
    static func redirect(_ source: URL, to target: URL) {
        lock.lock()
        redirects[source] = target
        lock.unlock()
        URLProtocol.registerClass(RedirectingURLProtocol.self)
    }

    static func reset() {
        URLProtocol.unregisterClass(RedirectingURLProtocol.self)
        lock.lock()
        redirects = [:]
        lock.unlock()
    }

    private static func target(for url: URL?) -> URL? {
        guard let url else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return redirects[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        target(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let source = request.url, let target = Self.target(for: source) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = HTTPURLResponse(
            url: source,
            statusCode: 301,
            httpVersion: "HTTP/1.1",
            headerFields: ["Location": target.absoluteString]
        )!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
    }

    override func stopLoading() {}
}
