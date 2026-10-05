import XCTest
@testable import MochiCore

final class AwarenessTests: XCTestCase {
    private func step(_ a: inout Awareness, key: Double = 10, input: Double? = nil,
                      app: String? = "com.apple.Safari", sleeping: Bool = false) -> Awareness.Action? {
        a.update(secondsSinceKey: key, secondsSinceInput: input ?? key, frontmost: app, sleeping: sleeping)
    }

    func testTypingStartsWithinTwoSecondsAndEndsAfter() {
        var a = Awareness()
        _ = step(&a, key: 0.5)
        XCTAssertEqual(a.activity, .typing)
        _ = step(&a, key: 2.5)
        XCTAssertEqual(a.activity, .present)
    }

    func testFirstAppObservationDoesNotReact() {
        var a = Awareness()
        XCTAssertNil(step(&a, app: "com.apple.dt.Xcode"))
    }

    func testEditorAndBrowserSwitchesReactDifferently() {
        var a = Awareness()
        _ = step(&a, app: "com.apple.Safari")
        XCTAssertEqual(step(&a, app: "com.apple.dt.Xcode"), .react("look"))
        XCTAssertEqual(step(&a, app: "com.apple.Safari"), .react("blink"))
    }

    func testSwitchWithinTheSameKindDoesNotReact() {
        var a = Awareness()
        _ = step(&a, app: "com.microsoft.VSCode")
        XCTAssertNil(step(&a, app: "com.apple.dt.Xcode"))
    }

    func testClassifiesBundleIds() {
        XCTAssertEqual(Awareness.kind(of: "com.jetbrains.intellij"), .editor)
        XCTAssertEqual(Awareness.kind(of: "com.googlecode.iterm2"), .terminal)
        XCTAssertEqual(Awareness.kind(of: "org.mozilla.firefox"), .browser)
        XCTAssertEqual(Awareness.kind(of: "com.example.unknown"), .other)
        XCTAssertEqual(Awareness.kind(of: nil), .other)
    }

    func testDozesWhenAwayAndWakesWhenInputReturns() {
        var a = Awareness()
        XCTAssertEqual(step(&a, key: 301), .doze)
        XCTAssertNil(step(&a, key: 301, sleeping: true))
        XCTAssertEqual(step(&a, key: 1, sleeping: true), .wake)
    }

    func testMouseActivityKeepsMochiAwake() {
        var a = Awareness()
        XCTAssertNil(step(&a, key: 400, input: 5))
    }

    func testNeverWakesAPetTheUserPutToSleep() {
        var a = Awareness()
        XCTAssertNil(step(&a, key: 1, sleeping: true))
    }

    func testUserWakingADozingPetClearsAutoWakeOwnership() {
        var a = Awareness()
        XCTAssertEqual(step(&a, key: 301), .doze)
        XCTAssertNil(step(&a, key: 1, sleeping: false))   // user woke Mochi
        XCTAssertNil(step(&a, key: 1, sleeping: true))    // user put Mochi back to sleep
    }

    func testDisabledAwarenessDoesNothing() {
        var a = Awareness()
        a.enabled = false
        XCTAssertNil(step(&a, key: 999))
        XCTAssertNil(step(&a, app: "com.apple.dt.Xcode"))
    }

    func testDisabledAwarenessStillTracksTypingForOtherFeatures() {
        var a = Awareness()
        a.enabled = false
        XCTAssertNil(step(&a, key: 0.5))
        XCTAssertEqual(a.activity, .typing)
    }

    func testInvalidSignalsAreIgnored() {
        var a = Awareness()
        _ = step(&a, key: 0.5)
        XCTAssertNil(step(&a, key: -1))
        XCTAssertNil(step(&a, key: .nan))
        XCTAssertEqual(a.activity, .typing)
    }
}
