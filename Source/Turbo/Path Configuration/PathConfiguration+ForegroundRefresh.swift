import UIKit

extension PathConfiguration {
    /// Adds or removes the foreground observer to match `refreshOnForeground`.
    func updateForegroundObserver() {
        if refreshOnForeground, foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshServerSourcesIfStale()
            }
        } else if !refreshOnForeground, let observer = foregroundObserver {
            NotificationCenter.default.removeObserver(observer)
            foregroundObserver = nil
        }
    }

    /// Refreshes the server sources unless the last server fetch attempt was
    /// less than `foregroundRefreshMinimumInterval` ago.
    /// - Returns: whether a refresh was started.
    @discardableResult
    func refreshServerSourcesIfStale() -> Bool {
        guard refreshOnForeground, sources.contains(where: \.isServer) else { return false }

        if let lastServerLoadAttempt,
           now().timeIntervalSince(lastServerLoadAttempt) < foregroundRefreshMinimumInterval {
            return false
        }

        refreshServerSources()
        return true
    }
}
