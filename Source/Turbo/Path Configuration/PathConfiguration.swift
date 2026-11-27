import Foundation

public typealias PathProperties = [String: AnyHashable]

public protocol PathConfigurationDelegate: AnyObject {
    /// Notifies delegate when a path configuration has been updated with new data
    func pathConfigurationDidUpdate()
}

public struct PathConfigurationLoaderOptions {
    public init(urlSessionConfiguration: URLSessionConfiguration? = nil) {
        self.urlSessionConfiguration = urlSessionConfiguration
    }

    /// If present, the ``PathConfigurationLoader`` will initialize a new `URLSession` with
    /// this configuration to make its network request
    public let urlSessionConfiguration: URLSessionConfiguration?
}

public final class PathConfiguration {
    /// Posted on the main thread every time the configuration is updated with
    /// new data (from any source). The notification's `object` is the
    /// `PathConfiguration` that changed. Unlike `delegate`, any number of
    /// observers can listen.
    public static let didUpdateNotification = Notification.Name("HotwireNative.PathConfiguration.didUpdate")

    public weak var delegate: PathConfigurationDelegate?

    /// Enable to include the query string (in addition to the path) when applying rules.
    /// Disable to only consider the path when applying rules.
    public var matchQueryStrings = true

    /// Returns top-level settings: `{ settings: {} }`
    public private(set) var settings: [String: AnyHashable] = [:]

    /// Where the current `settings` and `rules` came from, or `nil` before
    /// the first load. Read it from a `didUpdateNotification` observer to tell
    /// a bundled file apart from server data.
    public private(set) var lastUpdateSource: LoadSource?

    /// The list of rules from the configuration: `{ rules: [] }`
    /// Default server route rules are included by default.
    public private(set) var rules: [PathRule] = PathRule.defaultServerRoutes

    /// Sources for this configuration, setting it will
    /// cause the configuration to be loaded from the new sources
    public var sources: [Source] = [] {
        didSet {
            load()
        }
    }

    /// Opt in to re-downloading the `.server` sources when the app returns to
    /// the foreground, at most once per `foregroundRefreshMinimumInterval`.
    /// Off by default: no foreground observer is registered unless enabled.
    public var refreshOnForeground = false {
        didSet {
            updateForegroundObserver()
        }
    }

    /// The minimum time between server fetches triggered by returning to the
    /// foreground, measured from the last server fetch attempt (including the
    /// initial load).
    public var foregroundRefreshMinimumInterval: TimeInterval = 15 * 60

    /// Multiple sources will be loaded in order
    /// Remote sources should be last since they're loaded async
    public init(sources: [Source] = [], options: PathConfigurationLoaderOptions? = nil) {
        self.sources = sources
        self.options = options
        load()
    }

    /// Convenience method for getting properties for path: configuration["/path"]
    public subscript(path: String) -> PathProperties {
        properties(for: path)
    }

    /// Convenience method for retrieving properties for url: configuration[url]
    public subscript(url: URL) -> PathProperties {
        properties(for: url)
    }

    /// Returns a merged dictionary containing all the properties that match this URL.
    public func properties(for url: URL) -> PathProperties {
        if Hotwire.config.pathConfiguration.matchQueryStrings, let query = url.query {
            return properties(for: "\(url.pathPreservingSlash)?\(query)")
        }
        return properties(for: url.pathPreservingSlash)
    }

    /// Returns a merged dictionary containing all the properties
    /// that match this path
    public func properties(for path: String) -> PathProperties {
        var properties: PathProperties = [:]

        for rule in rules where rule.match(path: path) {
            properties.merge(rule.properties) { _, new in new }
        }

        return properties
    }

    /// Re-downloads only the `.server` sources. Bundled (`.file`/`.data`)
    /// sources and the cached server copy are not replayed, so a refresh can
    /// never flash older values back. Any fetch still in flight is dropped,
    /// so the newest fetch wins. Does nothing without `.server` sources.
    public func refreshServerSources() {
        let serverSources = sources.filter(\.isServer)
        guard !serverSources.isEmpty else { return }

        lastServerLoadAttempt = now()
        loader = PathConfigurationLoader(sources: serverSources, options: options)
        loader?.loadReportingSource(replayingCachedServerData: false) { [weak self] config, source in
            self?.update(with: config, source: source)
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Loading

    private let options: PathConfigurationLoaderOptions?

    private var loader: PathConfigurationLoader?

    /// When the last server fetch was started. Used to gate foreground refreshes.
    private(set) var lastServerLoadAttempt: Date?

    /// Clock, injectable for tests.
    var now: () -> Date = Date.init

    var foregroundObserver: NSObjectProtocol?

    private func load() {
        if sources.contains(where: \.isServer) {
            lastServerLoadAttempt = now()
        }
        loader = PathConfigurationLoader(sources: sources, options: options)
        loader?.loadReportingSource { [weak self] config, source in
            self?.update(with: config, source: source)
        }
    }

    private func update(with config: PathConfigurationDecoder, source: LoadSource) {
        lastUpdateSource = source
        // Update our internal state with the config from the loader
        settings = config.settings
        rules = config.rules
        // Always include the default server route rules.
        rules.append(contentsOf: PathRule.defaultServerRoutes)
        delegate?.pathConfigurationDidUpdate()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }
}

extension PathConfiguration: Equatable {
    public static func == (lhs: PathConfiguration, rhs: PathConfiguration) -> Bool {
        lhs.settings == rhs.settings && lhs.rules == rhs.rules
    }
}

public extension PathConfiguration {
    enum Source: Equatable {
        case data(Data)
        case file(URL)
        case server(URL)

        var isServer: Bool {
            if case .server = self { return true }
            return false
        }
    }

    /// Where a configuration update came from.
    enum LoadSource: Equatable {
        /// A `.data` source.
        case data
        /// A `.file` source, typically bundled with the app.
        case file
        /// The cached copy of a `.server` source, replayed before downloading.
        case cachedServer
        /// A fresh download of a `.server` source.
        case server
    }
}
