@testable import HotwireNative
import XCTest

/// Validation of `settings.theme`: any failure rejects the whole theme.
class HotwireThemeTests: XCTestCase {
    static let light: [String: Any] = [
        "background": "#FFF8F2", "surface": "#FFFFFF", "border": "#EDE0D4", "text": "#1A1614", "accent": "#B84428"
    ]
    static let dark: [String: Any] = [
        "background": "#1A1614", "surface": "#221D1A", "border": "#3A322D", "text": "#F5EDE6", "accent": "#F08A6C"
    ]

    func test_validLightOnlyTheme_withNullOrAbsentDark() throws {
        for dark in [NSNull(), nil] as [Any?] {
            var json: [String: Any] = ["version": 1, "light": Self.light]
            json["dark"] = dark
            let theme = try parse(json)
            XCTAssertEqual(theme.version, 1)
            XCTAssertEqual(theme.light.accent, "#B84428")
            XCTAssertNil(theme.dark)
        }
    }

    func test_validThemeWithDarkPalette() throws {
        let theme = try parse(["version": 1, "light": Self.light, "dark": Self.dark])
        XCTAssertEqual(theme.dark?.accent, "#F08A6C")
    }

    func test_lowercaseHexIsValid() throws {
        var light = Self.light
        light["accent"] = "#b84428"
        XCTAssertEqual(try parse(["version": 1, "light": light]).light.accent, "#b84428")
    }

    func test_unknownExtraRolesAreIgnored() throws {
        var light = Self.light
        light["danger"] = "not-a-color"
        XCTAssertNoThrow(try parse(["version": 1, "light": light]))
    }

    func test_unsupportedOrMalformedVersionIsRejected() {
        for version in [2, 0, "1", true, 1.5, NSNull()] as [Any] {
            XCTAssertThrowsError(try parse(["version": version, "light": Self.light]), "version \(version)") { error in
                guard case HotwireThemeError.unsupportedVersion = error else {
                    return XCTFail("unexpected \(error) for version \(version)")
                }
            }
        }
        XCTAssertThrowsError(try parse(["light": Self.light]), "missing version")
    }

    func test_eachMissingRoleRejectsTheWholeTheme() {
        for role in HotwireTheme.Role.allCases {
            var light = Self.light
            light[role.rawValue] = nil
            XCTAssertThrowsError(try parse(["version": 1, "light": light])) { error in
                XCTAssertEqual(error as? HotwireThemeError, .missingRole(palette: "light", role: role.rawValue))
            }
        }
    }

    func test_eachMalformedHexRejectsTheWholeTheme() {
        let bad: [Any] = ["#FFF", "FFFFFF", "#GGGGGG", "#FFFFFF ", " #FFFFFF", "#FFFFFFFF", "#FFFFFF\n", "red", "", 0xFFFFFF]
        for role in HotwireTheme.Role.allCases {
            for value in bad {
                var light = Self.light
                light[role.rawValue] = value
                XCTAssertThrowsError(try parse(["version": 1, "light": light]), "\(role) = \(value)") { error in
                    XCTAssertEqual(error as? HotwireThemeError, .invalidHex(palette: "light", role: role.rawValue))
                }
            }
        }
    }

    func test_invalidDarkPaletteRejectsTheWholeTheme() {
        var dark = Self.dark
        dark["surface"] = "#12345"
        XCTAssertThrowsError(try parse(["version": 1, "light": Self.light, "dark": dark])) { error in
            XCTAssertEqual(error as? HotwireThemeError, .invalidHex(palette: "dark", role: "surface"))
        }
        XCTAssertThrowsError(try parse(["version": 1, "light": Self.light, "dark": "#000000"])) { error in
            XCTAssertEqual(error as? HotwireThemeError, .missingPalette("dark"))
        }
    }

    func test_missingLightOrNonObjectThemeIsRejected() {
        XCTAssertThrowsError(try parse(["version": 1, "dark": Self.dark]))
        XCTAssertThrowsError(try HotwireTheme(settingsValue: "theme"))
        XCTAssertThrowsError(try HotwireTheme(settingsValue: [Self.light]))
    }

    /// Goes through the same JSON → `[String: AnyHashable]` path as a real
    /// path configuration, not a hand-built Swift dictionary.
    func test_parsesThemeFromRealPathConfigurationSettings() throws {
        let json: [String: Any] = [
            "settings": ["theme": ["version": 1, "light": Self.light, "dark": NSNull()]],
            "rules": []
        ]
        let configuration = PathConfiguration(sources: [.data(try JSONSerialization.data(withJSONObject: json))])

        let raw = try XCTUnwrap(configuration.settings["theme"])
        let theme = try HotwireTheme(settingsValue: raw)
        XCTAssertEqual(theme.light.surface, "#FFFFFF")
        XCTAssertNil(theme.dark)
    }

    func test_validatedRejectsATamperedStoredTheme() {
        let palette = HotwireTheme.Palette(background: "#FFFFFF", surface: "#FFFFFF", border: "#FFFFFF", text: "#FFFFFF", accent: "nope")
        XCTAssertThrowsError(try HotwireTheme(version: 1, light: palette, dark: nil).validated())
    }

    // MARK: - Helpers

    private func parse(_ object: [String: Any]) throws -> HotwireTheme {
        // Round-trip through JSONSerialization so values are Foundation types.
        let data = try JSONSerialization.data(withJSONObject: object)
        return try HotwireTheme(settingsValue: JSONSerialization.jsonObject(with: data))
    }
}
