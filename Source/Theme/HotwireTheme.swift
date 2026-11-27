import Foundation

/// A small color theme served in the path configuration's `settings.theme`:
///
/// ```json
/// "theme": { "version": 1,
///   "light": { "background": "#FFF8F2", "surface": "#FFFFFF", "border": "#EDE0D4",
///              "text": "#1A1614", "accent": "#B84428" },
///   "dark": null }
/// ```
///
/// Every role is a `#RRGGBB` string. `dark` is optional; when present it must
/// be a complete, valid palette. Unknown extra roles are ignored, so new roles
/// can be added without a version bump.
public struct HotwireTheme: Codable, Equatable {
    public enum Role: String, CaseIterable, Codable {
        /// Window and web-view background.
        case background
        /// Navigation-bar fill.
        case surface
        /// Navigation-bar hairline.
        case border
        /// Native text, e.g. error screens; optionally the nav title.
        case text
        /// Tint and nav title. Colors text (such as the modal Done button).
        case accent
    }

    public struct Palette: Codable, Equatable {
        public let background: String
        public let surface: String
        public let border: String
        public let text: String
        public let accent: String

        public subscript(role: Role) -> String {
            switch role {
            case .background: background
            case .surface: surface
            case .border: border
            case .text: text
            case .accent: accent
            }
        }
    }

    /// The only schema version this library understands.
    public static let supportedVersion = 1

    public let version: Int
    public let light: Palette
    public let dark: Palette?
}

// MARK: - Validation

enum HotwireThemeError: Error, Equatable, CustomStringConvertible {
    case notAnObject
    case unsupportedVersion(String)
    case missingPalette(String)
    case missingRole(palette: String, role: String)
    case invalidHex(palette: String, role: String)

    var description: String {
        switch self {
        case .notAnObject:
            "theme is not an object"
        case .unsupportedVersion(let version):
            "unsupported theme version \(version) (expected \(HotwireTheme.supportedVersion))"
        case .missingPalette(let palette):
            "\(palette) palette is missing or not an object"
        case .missingRole(let palette, let role):
            "\(palette).\(role) is missing"
        case .invalidHex(let palette, let role):
            "\(palette).\(role) is not #RRGGBB"
        }
    }
}

extension HotwireTheme {
    /// Parses and validates the raw `settings["theme"]` value.
    /// Any failure rejects the whole theme.
    init(settingsValue value: Any) throws {
        let value = (value as? AnyHashable)?.base ?? value
        guard let object = value as? [String: Any] else {
            throw HotwireThemeError.notAnObject
        }

        guard let version = Self.integer(object["version"]), version == Self.supportedVersion else {
            throw HotwireThemeError.unsupportedVersion(object["version"].map { "\($0)" } ?? "missing")
        }

        let light = try Self.palette(object["light"], name: "light")

        let dark: Palette?
        switch object["dark"] {
        case nil, is NSNull:
            dark = nil
        case let value?:
            dark = try Self.palette(value, name: "dark")
        }

        self.init(version: version, light: light, dark: dark)
    }

    /// Re-validates a decoded theme (for example, one restored from storage).
    func validated() throws -> HotwireTheme {
        guard version == Self.supportedVersion else {
            throw HotwireThemeError.unsupportedVersion("\(version)")
        }
        for (name, palette) in [("light", light), ("dark", dark)] {
            guard let palette else { continue }
            for role in Role.allCases where !Self.isHex(palette[role]) {
                throw HotwireThemeError.invalidHex(palette: name, role: role.rawValue)
            }
        }
        return self
    }

    /// Exactly `^#[0-9A-Fa-f]{6}$`. Checked by hand: an ICU `$` would also
    /// accept a trailing newline.
    static func isHex(_ value: String) -> Bool {
        let utf8 = Array(value.utf8)
        guard utf8.count == 7, utf8[0] == UInt8(ascii: "#") else { return false }
        return utf8.dropFirst().allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
        }
    }

    private static func palette(_ value: Any?, name: String) throws -> Palette {
        guard let object = value as? [String: Any] else {
            throw HotwireThemeError.missingPalette(name)
        }

        func role(_ role: Role) throws -> String {
            guard let raw = object[role.rawValue] else {
                throw HotwireThemeError.missingRole(palette: name, role: role.rawValue)
            }
            guard let hex = raw as? String, isHex(hex) else {
                throw HotwireThemeError.invalidHex(palette: name, role: role.rawValue)
            }
            return hex
        }

        return Palette(
            background: try role(.background),
            surface: try role(.surface),
            border: try role(.border),
            text: try role(.text),
            accent: try role(.accent)
        )
    }

    /// JSON numbers arrive as `NSNumber`; reject booleans and non-integers.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let int = number.intValue
        return Double(int) == number.doubleValue ? int : nil
    }
}
