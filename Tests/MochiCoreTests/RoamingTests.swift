import XCTest
@testable import MochiCore

final class RoamingTests: XCTestCase {
    /// Cycles through scripted "random" values so walks are deterministic.
    private func rolls(_ values: [Double]) -> () -> Double {
        var i = 0
        return { defer { i += 1 }; return values[i % values.count] }
    }

    private let room = 0.0...1000.0

    // Rolls: direction 0.9 (right), distance 0.0 (80 px), then wait rolls.
    private func rightWalk80() -> Roaming { Roaming(random: rolls([0.9, 0.0, 0.5])) }

    func testNothingHappensBeforeTheFirstWait() {
        var r = rightWalk80()
        let out = r.update(dt: 9.9, canRoam: true, x: 500, room: room)
        XCTAssertNil(out.event)
        XCTAssertEqual(out.dx, 0)
        XCTAssertFalse(r.walking)
    }

    func testWalksTheChosenDistanceAtASteadySpeedThenStops() {
        var r = rightWalk80()
        XCTAssertEqual(r.update(dt: 10.1, canRoam: true, x: 500, room: room).event, .begin(left: false))
        XCTAssertTrue(r.walking)
        var x = 500.0
        var step = r.update(dt: 1, canRoam: true, x: x, room: room)
        XCTAssertEqual(step.dx, 40)
        XCTAssertNil(step.event)
        x += step.dx
        step = r.update(dt: 1, canRoam: true, x: x, room: room)
        XCTAssertEqual(step.dx, 40)
        XCTAssertEqual(step.event, .end)
        XCTAssertFalse(r.walking)
    }

    func testLeftwardWalkMovesNegatively() {
        var r = Roaming(random: rolls([0.1, 0.0, 0.5]))
        XCTAssertEqual(r.update(dt: 10.1, canRoam: true, x: 500, room: room).event, .begin(left: true))
        XCTAssertEqual(r.update(dt: 1, canRoam: true, x: 500, room: room).dx, -40)
    }

    func testStopsAtOnceWhenRoamingBecomesNotAllowed() {
        var r = rightWalk80()
        _ = r.update(dt: 10.1, canRoam: true, x: 500, room: room)
        let out = r.update(dt: 0.1, canRoam: false, x: 500, room: room)   // typing, drag, sleep, focus...
        XCTAssertEqual(out.event, .end)
        XCTAssertEqual(out.dx, 0)
        XCTAssertFalse(r.walking)
    }

    func testCountdownOnlyRunsWhileRoamingIsAllowed() {
        var r = rightWalk80()
        _ = r.update(dt: 9, canRoam: true, x: 500, room: room)
        XCTAssertNil(r.update(dt: 100, canRoam: false, x: 500, room: room).event)
        XCTAssertEqual(r.update(dt: 1.1, canRoam: true, x: 500, room: room).event, .begin(left: false))
    }

    func testAtTheLeftEdgeItCanOnlyWalkRight() {
        var r = Roaming(random: rolls([0.0, 0.0, 0.5]))   // roll says left
        XCTAssertEqual(r.update(dt: 10.1, canRoam: true, x: 0, room: room).event, .begin(left: false))
    }

    func testAtTheRightEdgeItCanOnlyWalkLeft() {
        var r = Roaming(random: rolls([0.99, 0.0, 0.5]))  // roll says right
        XCTAssertEqual(r.update(dt: 10.1, canRoam: true, x: 1000, room: room).event, .begin(left: true))
    }

    func testDoesNotStartWhenThereIsNoRoomToWalk() {
        var r = rightWalk80()
        let out = r.update(dt: 11, canRoam: true, x: 0, room: 0...30)
        XCTAssertNil(out.event)
        XCTAssertFalse(r.walking)
    }

    func testNeverLeavesTheRoomEvenIfItShrinksMidWalk() {
        var r = Roaming(random: rolls([0.9, 1.0, 0.5]))   // right, 300 px
        _ = r.update(dt: 10.1, canRoam: true, x: 500, room: room)
        let out = r.update(dt: 1, canRoam: true, x: 500, room: 0...510)   // display changed
        XCTAssertEqual(out.dx, 10)
        XCTAssertEqual(out.event, .end)
    }

    func testDisabledNeverStartsAndEndsAWalkInProgress() {
        var r = rightWalk80()
        r.enabled = false
        XCTAssertNil(r.update(dt: 100, canRoam: true, x: 500, room: room).event)
        r.enabled = true
        _ = r.update(dt: 100, canRoam: true, x: 500, room: room)
        XCTAssertTrue(r.walking)
        r.enabled = false
        XCTAssertEqual(r.update(dt: 0.1, canRoam: true, x: 500, room: room).event, .end)
    }

    func testInvalidTimeStepsAreIgnored() {
        var r = rightWalk80()
        for dt in [Double.nan, -1, 0, .infinity] {
            let out = r.update(dt: dt, canRoam: true, x: 500, room: room)
            XCTAssertNil(out.event)
            XCTAssertEqual(out.dx, 0)
        }
    }
}

final class CompanionWalkTests: XCTestCase {
    private var clips: [String: Clip] {
        Dictionary(uniqueKeysWithValues: Companion.requiredClips.map {
            ($0, Clip(frames: ["a", "b", "c"], fps: 10,
                      loop: ["idle", "sleeping", "dragged", "walk", "walk_left"].contains($0)))
        })
    }

    func testWalkClipsAreRequired() {
        XCTAssertTrue(Companion.requiredClips.contains("walk"))
        XCTAssertTrue(Companion.requiredClips.contains("walk_left"))
    }

    func testStartWalkPlaysTheClipForThatDirection() {
        var pet = Companion()
        pet.startWalk(left: false)
        XCTAssertEqual(pet.animation, "walk")
        XCTAssertTrue(pet.walking)
        pet.stopWalk()
        pet.startWalk(left: true)
        XCTAssertEqual(pet.animation, "walk_left")
    }

    func testWalkOnlyStartsFromIdle() {
        var busy = Companion()
        busy.react("heart")
        busy.startWalk(left: false)
        XCTAssertEqual(busy.animation, "heart")

        var asleep = Companion()
        asleep.toggleSleep()
        asleep.startWalk(left: false)
        XCTAssertFalse(asleep.walking)

        var dragged = Companion()
        dragged.beginDrag()
        dragged.startWalk(left: false)
        XCTAssertFalse(dragged.walking)
    }

    func testWalkKeepsLoopingUntilStopped() {
        var pet = Companion()
        pet.startWalk(left: false)
        pet.advance(seconds: 10, clips: clips)
        XCTAssertTrue(pet.walking)
        pet.stopWalk()
        XCTAssertEqual(pet.animation, "idle")
    }

    func testClickDragAndSleepEachInterruptAWalk() {
        var clicked = Companion()
        clicked.startWalk(left: false)
        clicked.react("bounce")
        XCTAssertEqual(clicked.animation, "bounce")
        XCTAssertFalse(clicked.walking)

        var dragged = Companion()
        dragged.startWalk(left: false)
        dragged.beginDrag()
        XCTAssertEqual(dragged.animation, "pickup")

        var slept = Companion()
        slept.startWalk(left: false)
        slept.toggleSleep()
        XCTAssertEqual(slept.animation, "sleep")
    }

    func testStopWalkDoesNotCutShortSomethingElse() {
        var pet = Companion()
        pet.react("heart")
        pet.stopWalk()
        XCTAssertEqual(pet.animation, "heart")
    }
}
