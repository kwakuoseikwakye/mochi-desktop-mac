import XCTest
@testable import MochiCore

final class FocusTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testStartRunsForTwentyFiveMinutes() {
        var f = Focus()
        XCTAssertFalse(f.isActive)
        f.start(now: t0)
        XCTAssertTrue(f.isActive)
        XCTAssertEqual(f.remaining(now: t0), 1500)
    }

    func testFinishesExactlyOnce() {
        var f = Focus()
        f.start(now: t0)
        XCTAssertFalse(f.update(now: t0.addingTimeInterval(1499)))
        XCTAssertTrue(f.isActive)
        XCTAssertTrue(f.update(now: t0.addingTimeInterval(1500)))
        XCTAssertFalse(f.isActive)
        XCTAssertFalse(f.update(now: t0.addingTimeInterval(1501)))
    }

    func testStopCancelsWithoutFinishing() {
        var f = Focus()
        f.start(now: t0)
        f.stop()
        XCTAssertFalse(f.isActive)
        XCTAssertFalse(f.update(now: t0.addingTimeInterval(2000)))
    }

    func testStartingAgainRestartsTheClock() {
        var f = Focus()
        f.start(now: t0)
        f.start(now: t0.addingTimeInterval(600))
        XCTAssertEqual(f.remaining(now: t0.addingTimeInterval(600)), 1500)
    }

    func testRemainingNeverGoesNegative() {
        var f = Focus()
        f.start(now: t0)
        XCTAssertEqual(f.remaining(now: t0.addingTimeInterval(9999)), 0)
    }

    func testRestoreResumesASessionStillInProgress() {
        var f = Focus()
        f.restore(endsAt: t0.addingTimeInterval(600), now: t0)
        XCTAssertTrue(f.isActive)
        XCTAssertEqual(f.remaining(now: t0), 600)
    }

    func testRestoreDropsAnExpiredSessionSilently() {
        var f = Focus()
        f.restore(endsAt: t0.addingTimeInterval(-5), now: t0)
        XCTAssertFalse(f.isActive)
        XCTAssertFalse(f.update(now: t0))
    }

    func testRestoreRejectsAnEndTimeFartherAwayThanASessionCouldBe() {
        var f = Focus()   // e.g. the clock was moved backwards since it was saved
        f.restore(endsAt: t0.addingTimeInterval(86_400), now: t0)
        XCTAssertFalse(f.isActive)
    }

    func testRestoreWithNothingSavedStaysInactive() {
        var f = Focus()
        f.restore(endsAt: nil, now: t0)
        XCTAssertFalse(f.isActive)
    }
}
