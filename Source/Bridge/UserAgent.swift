import Foundation

enum UserAgent {
    static func build(appIdentifier: String? = nil,
                      appVersion: String? = nil,
                      appBuild: String? = nil,
                      applicationPrefix: String?,
                      componentTypes: [BridgeComponent.Type]) -> String {
        let components = componentTypes.map { $0.name }.joined(separator: " ")
        let componentsSubstring = "bridge-components: [\(components)]"

        return [
            appToken(identifier: appIdentifier, version: appVersion, build: appBuild),
            applicationPrefix,
            "Hotwire Native iOS;",
            "Turbo Native iOS;",
            componentsSubstring
        ].compactMap { $0 }.joined(separator: " ")
    }

    /// Composes an `"Identifier/version (build N)"` token that lets a server
    /// identify the app and its version from any request's user agent.
    ///
    /// Returns `nil` when no identifier is configured. Degrades to just the
    /// identifier when no version is available.
    static func appToken(identifier: String?, version: String?, build: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        guard let version, !version.isEmpty else { return identifier }

        if let build, !build.isEmpty {
            return "\(identifier)/\(version) (build \(build))"
        }
        return "\(identifier)/\(version)"
    }
}
