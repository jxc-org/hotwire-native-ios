import Foundation
@testable import HotwireNative
import XCTest

class UserAgentTests: XCTestCase {
    func testUserAgentSubstringWithNoComponents() {
        let userAgentSubstring = UserAgent.build(
            applicationPrefix: nil,
            componentTypes: []
        )
        XCTAssertEqual(userAgentSubstring, "Hotwire Native iOS; Turbo Native iOS; bridge-components: []")
    }

    func testUserAgentSubstringWithTwoComponents() {
        let userAgentSubstring = UserAgent.build(
            applicationPrefix: nil,
            componentTypes: [OneBridgeComponent.self, TwoBridgeComponent.self]
        )
        XCTAssertEqual(userAgentSubstring, "Hotwire Native iOS; Turbo Native iOS; bridge-components: [one two]")
    }

    func testUserAgentSubstringCustomPrefix() {
        let userAgentSubstring = UserAgent.build(
            applicationPrefix: "Hotwire Demo;",
            componentTypes: [OneBridgeComponent.self, TwoBridgeComponent.self]
        )
        XCTAssertEqual(userAgentSubstring, "Hotwire Demo; Hotwire Native iOS; Turbo Native iOS; bridge-components: [one two]")
    }

    func testAppTokenWithVersionAndBuild() {
        XCTAssertEqual(
            UserAgent.appToken(identifier: "Birthdaze", version: "1.5.0", build: "202605170900"),
            "Birthdaze/1.5.0 (build 202605170900)"
        )
    }

    func testAppTokenWithoutBuild() {
        XCTAssertEqual(
            UserAgent.appToken(identifier: "Birthdaze", version: "1.5.0", build: nil),
            "Birthdaze/1.5.0"
        )
    }

    func testAppTokenDegradesToIdentifierWithoutVersion() {
        XCTAssertEqual(
            UserAgent.appToken(identifier: "Birthdaze", version: nil, build: "42"),
            "Birthdaze"
        )
    }

    func testAppTokenIsNilWithoutIdentifier() {
        XCTAssertNil(UserAgent.appToken(identifier: nil, version: "1.5.0", build: "42"))
        XCTAssertNil(UserAgent.appToken(identifier: "", version: "1.5.0", build: "42"))
    }

    func testUserAgentSubstringLeadsWithAppToken() {
        let userAgentSubstring = UserAgent.build(
            appIdentifier: "Birthdaze",
            appVersion: "1.5.0",
            appBuild: "202605170900",
            applicationPrefix: nil,
            componentTypes: []
        )
        XCTAssertEqual(
            userAgentSubstring,
            "Birthdaze/1.5.0 (build 202605170900) Hotwire Native iOS; Turbo Native iOS; bridge-components: []"
        )
    }
}
