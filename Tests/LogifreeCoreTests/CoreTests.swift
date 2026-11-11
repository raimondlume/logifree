import Foundation
import XCTest
@testable import LogifreeCore

final class HIDPPTests: XCTestCase {
    func testLongReportFraming() {
        HIDPP.softwareID = 0x0A
        let report = HIDPP.long(2, 0x0A, 1, [0x00, 0xC3])
        XCTAssertEqual(report.count, 20)
        XCTAssertEqual(Array(report.prefix(6)), [0x11, 0x02, 0x0A, 0x1A, 0x00, 0xC3])
    }

    // Reports below are from a real MX Master 3S on a Bolt receiver.
    func testMatchesReplyToSameFeatureFunctionAndSoftwareID() {
        let ping = hex("11 02 00 1a 00 00 5a 00 00 00 00 00 00 00 00 00 00 00 00 00")
        XCTAssertTrue(HIDPP.isReply(hex("11 02 00 1a 04 05 5a 00 00 00 00 00 00 00 00 00 00 00 00 00"), to: ping))
        // Same request from another process (software ID 0xB) isn't ours.
        XCTAssertFalse(HIDPP.isReply(hex("11 02 00 1b 04 05 5a 00 00 00 00 00 00 00 00 00 00 00 00 00"), to: ping))
        // Another slot isn't ours either.
        XCTAssertFalse(HIDPP.isReply(hex("11 01 00 1a 04 05 5a 00 00 00 00 00 00 00 00 00 00 00 00 00"), to: ping))
    }

    func testMatchesErrorReplies() {
        let ping = hex("11 04 00 1a 00 00 5a 00 00 00 00 00 00 00 00 00 00 00 00 00")
        XCTAssertTrue(HIDPP.isReply(hex("10 04 8f 00 1a 09 00"), to: ping)) // receiver: no device
        XCTAssertTrue(HIDPP.isReply(hex("11 04 ff 00 1a 02 00 00 00 00 00 00 00 00 00 00 00 00 00 00"), to: ping))
    }

    func testDeviceEventsAreNotReplies() {
        let request = hex("11 02 0a 0a 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        let divertedButtonEvent = hex("11 02 0a 00 00 c3 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
        XCTAssertFalse(HIDPP.isReply(divertedButtonEvent, to: request))
    }

    private func hex(_ string: String) -> [UInt8] {
        string.split(separator: " ").map { UInt8($0, radix: 16)! }
    }
}

final class GestureTests: XCTestCase {
    func testSmallMovementIsAClick() {
        XCTAssertEqual(ThumbGesture.classify(dx: 10, dy: -20, threshold: 50), .click)
    }

    func testDominantAxisPicksTheSwipe() {
        XCTAssertEqual(ThumbGesture.classify(dx: -80, dy: 30, threshold: 50), .swipeLeft)
        XCTAssertEqual(ThumbGesture.classify(dx: 80, dy: -30, threshold: 50), .swipeRight)
        XCTAssertEqual(ThumbGesture.classify(dx: 10, dy: -60, threshold: 50), .swipeUp)
        XCTAssertEqual(ThumbGesture.classify(dx: 10, dy: 60, threshold: 50), .swipeDown)
    }
}

final class KeyCatalogTests: XCTestCase {
    func testNamesMatchHIDUsages() {
        XCTAssertEqual(KeyCatalog.name(0x6D), "F18")
        XCTAssertEqual(KeyCatalog.name(0x45), "F12")
        XCTAssertEqual(KeyCatalog.name(0x68), "F13")
        XCTAssertEqual(KeyCatalog.name(0x27), "0")
        XCTAssertEqual(KeyCatalog.name(0x1E), "1")
        XCTAssertEqual(KeyCatalog.name(0x1D), "Z")
        XCTAssertEqual(KeyCatalog.name(0x99), "Key 0x99")
    }

    func testNoDuplicateKeys() {
        let usages = KeyCatalog.groups.flatMap(\.keys).map(\.usage)
        XCTAssertEqual(usages.count, Set(usages).count)
    }
}

final class SettingsTests: XCTestCase {
    func testRoundTrip() throws {
        var settings = Settings()
        settings.invertThumbwheel = false
        settings.gestures[.click] = .keystroke(KeyCombo(key: 49, modifiers: 1 << 20, display: "⌘Space"))
        settings.gestures[.swipeUp] = .shell("open -a Notes")
        settings.gestures[.swipeDown] = nil
        settings.keyRemaps = [KeyRemap(from: 0x64, to: 0x6D)]
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(#"{"invertWheel": false}"#.utf8))
        XCTAssertFalse(decoded.invertWheel)
        XCTAssertEqual(decoded.gestures, Settings().gestures)
        XCTAssertEqual(decoded.swipeThreshold, 50)
        XCTAssertEqual(decoded.minimumLinesPerClick, 2)
        XCTAssertEqual(decoded.keyRemaps, [])
    }
}
