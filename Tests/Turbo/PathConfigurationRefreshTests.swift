@testable import HotwireNative
import OHHTTPStubs
import OHHTTPStubsSwift
import UIKit
import XCTest

/// Covers the update notification, `refreshServerSources()` and the opt-in
/// foreground refresh with its minimum interval.
class PathConfigurationRefreshTests: XCTestCase {
    private let serverURL = URL(string: "http://turbo.test/refresh-test-configuration.json")!
    private let fileURL = Bundle.module.url(forResource: "test-configuration", withExtension: "json", subdirectory: "Fixtures")!

    /// What the stubbed server currently returns as `settings.source`.
    private var serverVersion = "server-1"
    private var serverRequestCount = 0

    override func setUp() {
        super.setUp()
        serverVersion = "server-1"
        serverRequestCount = 0
        clearCache()
        stub(condition: isAbsoluteURLString(serverURL.absoluteString)) { [unowned self] _ in
            serverRequestCount += 1
            let json: [String: Any] = ["settings": ["source": serverVersion], "rules": []]
            return HTTPStubsResponse(jsonObject: json, statusCode: 200, headers: [:])
        }
    }

    override func tearDown() {
        HTTPStubs.removeAllStubs()
        clearCache()
        super.tearDown()
    }

    // MARK: - Notification

    func test_update_postsDidUpdateNotificationWithTheConfiguration() {
        let configuration = PathConfiguration()
        let posted = expectation(forNotification: PathConfiguration.didUpdateNotification, object: configuration)

        configuration.sources = [.file(fileURL)]

        wait(for: [posted], timeout: 1)
        XCTAssertEqual(configuration.settings["server"] as? String, "beta")
    }

    // MARK: - refreshServerSources()

    func test_refreshServerSources_neverReloadsTheBundledFileOrTheCachedCopy() {
        let configuration = PathConfiguration()
        configuration.sources = [.file(fileURL), .server(serverURL)]
        // The bundled file loads synchronously; wait for the first download.
        waitForSource("server-1", on: configuration)

        serverVersion = "server-2"
        var updates: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: PathConfiguration.didUpdateNotification, object: configuration, queue: nil
        ) { _ in updates.append((configuration.settings["source"] ?? configuration.settings["server"]) as? String ?? "?") }
        defer { NotificationCenter.default.removeObserver(observer) }

        configuration.refreshServerSources()
        waitForSource("server-2", on: configuration)

        // Exactly one update, from the network. Neither the bundled file
        // ("beta") nor the cached "server-1" copy was replayed.
        XCTAssertEqual(updates, ["server-2"])
        XCTAssertEqual(serverRequestCount, 2)
    }

    func test_refreshServerSources_withoutServerSources_doesNothing() {
        let configuration = PathConfiguration(sources: [.file(fileURL)])
        var updateCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: PathConfiguration.didUpdateNotification, object: configuration, queue: nil
        ) { _ in updateCount += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        configuration.refreshServerSources()

        XCTAssertEqual(updateCount, 0)
        XCTAssertNil(configuration.lastServerLoadAttempt)
        XCTAssertEqual(serverRequestCount, 0)
    }

    func test_lastUpdateSource_reportsWhereEachUpdateCameFrom() {
        // First launch: bundled file, then the download (which gets cached).
        let first = PathConfiguration()
        var sources: [PathConfiguration.LoadSource?] = []
        let observer = NotificationCenter.default.addObserver(
            forName: PathConfiguration.didUpdateNotification, object: nil, queue: nil
        ) { notification in
            sources.append((notification.object as? PathConfiguration)?.lastUpdateSource)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertNil(first.lastUpdateSource)
        first.sources = [.file(fileURL), .server(serverURL)]
        waitForSource("server-1", on: first)
        XCTAssertEqual(sources, [.file, .server])

        // Next launch: bundled, then the cached copy, then the download.
        sources = []
        serverVersion = "server-2"
        let second = PathConfiguration()
        second.sources = [.file(fileURL), .server(serverURL)]
        waitForSource("server-2", on: second)
        XCTAssertEqual(sources, [.file, .cachedServer, .server])

        // A refresh only downloads.
        sources = []
        serverVersion = "server-3"
        second.refreshServerSources()
        waitForSource("server-3", on: second)
        XCTAssertEqual(sources, [.server])
    }

    func test_overlappingRefreshes_newestWins() {
        let configuration = PathConfiguration()
        configuration.sources = [.server(serverURL)]
        waitForSource("server-1", on: configuration)

        // The first refresh's response is slow; the second's is immediate.
        HTTPStubs.removeAllStubs()
        var requestCount = 0
        stub(condition: isAbsoluteURLString(serverURL.absoluteString)) { _ in
            requestCount += 1
            let isFirst = requestCount == 1
            let json: [String: Any] = ["settings": ["source": isFirst ? "slow-old" : "fast-new"], "rules": []]
            return HTTPStubsResponse(jsonObject: json, statusCode: 200, headers: [:])
                .responseTime(isFirst ? 0.5 : 0)
        }

        var updates: [String] = []
        let observer = NotificationCenter.default.addObserver(
            forName: PathConfiguration.didUpdateNotification, object: configuration, queue: nil
        ) { _ in updates.append(configuration.settings["source"] as? String ?? "?") }
        defer { NotificationCenter.default.removeObserver(observer) }

        configuration.refreshServerSources()
        configuration.refreshServerSources()
        waitForSource("fast-new", on: configuration)

        // Give the slow, superseded response time to arrive; it must be dropped.
        let settled = expectation(description: "slow response window passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(updates, ["fast-new"])
        XCTAssertEqual(configuration.settings["source"] as? String, "fast-new")
    }

    func test_refresh_revalidatesInsteadOfUsingAnHTTPCachedCopy() {
        let configuration = PathConfiguration()
        configuration.sources = [.server(serverURL)]
        waitForSource("server-1", on: configuration)

        var policies: [URLRequest.CachePolicy] = []
        HTTPStubs.removeAllStubs()
        stub(condition: isAbsoluteURLString(serverURL.absoluteString)) { request in
            policies.append(request.cachePolicy)
            let json: [String: Any] = ["settings": ["source": "server-2"], "rules": []]
            return HTTPStubsResponse(jsonObject: json, statusCode: 200, headers: [:])
        }

        configuration.refreshServerSources()
        waitForSource("server-2", on: configuration)

        XCTAssertEqual(policies, [.reloadRevalidatingCacheData])
    }

    // MARK: - Foreground refresh

    func test_refreshOnForeground_isOffByDefaultAndRegistersNoObserver() {
        let configuration = PathConfiguration()
        XCTAssertFalse(configuration.refreshOnForeground)
        XCTAssertNil(configuration.foregroundObserver)

        var clock = Date(timeIntervalSince1970: 0)
        configuration.now = { clock }
        configuration.sources = [.server(serverURL)]
        waitForSource("server-1", on: configuration)

        clock += 24 * 60 * 60
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        drainMainQueue()

        XCTAssertFalse(configuration.refreshServerSourcesIfStale())
        XCTAssertEqual(serverRequestCount, 1)
    }

    func test_refreshOnForeground_togglingOffRemovesTheObserver() {
        let configuration = PathConfiguration()
        configuration.refreshOnForeground = true
        XCTAssertNotNil(configuration.foregroundObserver)

        configuration.refreshOnForeground = false
        XCTAssertNil(configuration.foregroundObserver)
    }

    func test_foregroundRefresh_respectsTheMinimumIntervalFromTheLastAttempt() {
        let configuration = PathConfiguration()
        var clock = Date(timeIntervalSince1970: 0)
        configuration.now = { clock }
        configuration.refreshOnForeground = true
        configuration.foregroundRefreshMinimumInterval = 15 * 60

        // The cold-launch load counts as an attempt.
        configuration.sources = [.server(serverURL)]
        waitForSource("server-1", on: configuration)
        XCTAssertEqual(configuration.lastServerLoadAttempt, clock)

        clock += 14 * 60 + 59
        XCTAssertFalse(configuration.refreshServerSourcesIfStale(), "inside the interval")

        clock += 1
        serverVersion = "server-2"
        XCTAssertTrue(configuration.refreshServerSourcesIfStale(), "interval elapsed")
        XCTAssertEqual(configuration.lastServerLoadAttempt, clock)
        waitForSource("server-2", on: configuration)

        clock += 60
        XCTAssertFalse(configuration.refreshServerSourcesIfStale(), "gated again from the new attempt")
        XCTAssertEqual(serverRequestCount, 2)
    }

    func test_foregroundNotification_refreshesOnceTheIntervalHasElapsed() {
        let configuration = PathConfiguration()
        var clock = Date(timeIntervalSince1970: 0)
        configuration.now = { clock }
        configuration.refreshOnForeground = true
        configuration.sources = [.server(serverURL)]
        waitForSource("server-1", on: configuration)

        // Too soon: the notification is ignored.
        clock += 60
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        drainMainQueue()
        XCTAssertEqual(serverRequestCount, 1)

        // Past the interval: the notification triggers a server-only refresh.
        clock += 15 * 60
        serverVersion = "server-2"
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        waitForSource("server-2", on: configuration)
        XCTAssertEqual(serverRequestCount, 2)
    }

    // MARK: - Helpers

    private func waitForSource(_ source: String, on configuration: PathConfiguration, file: StaticString = #filePath, line: UInt = #line) {
        if configuration.settings["source"] as? String == source { return }
        let updated = expectation(forNotification: PathConfiguration.didUpdateNotification, object: configuration) { _ in
            configuration.settings["source"] as? String == source
        }
        wait(for: [updated], timeout: 5)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }

    private func clearCache() {
        let loader = PathConfigurationLoader(sources: [])
        try? FileManager.default.removeItem(at: loader.configurationCacheURL(for: serverURL))
    }
}
