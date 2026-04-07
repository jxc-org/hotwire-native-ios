import Foundation

/// Built-in bridge component that receives stale URL paths from the web
/// and marks them on the Session so that navigating back to those paths
/// triggers a full page load instead of restoring from the snapshot cache.
///
/// Register this component alongside your app's custom bridge components:
///
///     Hotwire.registerBridgeComponents([
///         CacheInvalidationComponent.self,
///         // ...your components
///     ])
///
/// On the web side, pair with a Strada bridge controller that sends
/// a `"connect"` event with `{ urls: ["/path1", "/path2"] }`.
@MainActor
public final class CacheInvalidationComponent: BridgeComponent {
    override nonisolated public class var name: String { "cache-invalidation" }

    /// Posted when stale URLs are received from the web bridge.
    /// The Session observes this internally to mark paths as stale.
    static let invalidationNotification = Notification.Name("HotwireNative.cacheInvalidation")

    override public func onReceive(message: Message) {
        guard message.event == "connect" else { return }
        guard let data: ConnectData = message.data() else { return }

        NotificationCenter.default.post(
            name: Self.invalidationNotification,
            object: nil,
            userInfo: ["urls": data.urls]
        )
    }
}

private struct ConnectData: Decodable {
    let urls: [String]
}
