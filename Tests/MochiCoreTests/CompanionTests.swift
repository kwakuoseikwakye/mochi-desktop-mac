import XCTest
@testable import MochiCore

final class CompanionTests: XCTestCase {
    private var clips: [String: Clip] {
        Dictionary(uniqueKeysWithValues: Companion.requiredClips.map {
            ($0, Clip(frames: ["a", "b", "c"], fps: 10, loop: ["idle", "sleeping", "dragged"].contains($0)))
        })
    }

    func testReactionCompletesAndBecomesInteractableAgain() {
        var pet = Companion()
        pet.react("heart")
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "idle")
        pet.react("bounce")
        XCTAssertEqual(pet.animation, "bounce")
    }

    func testSleepInterruptsReactionAndRejectsAmbientActivity() {
        var pet = Companion()
        pet.react("heart")
        pet.toggleSleep()
        pet.react("blink")
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "sleeping")
        XCTAssertTrue(pet.sleeping)
        pet.toggleSleep()
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "idle")
        XCTAssertFalse(pet.sleeping)
    }

    func testDraggingSleepingPetRestoresSleepAfterDrop() {
        var pet = Companion()
        pet.toggleSleep()
        pet.beginDrag()
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "dragged")
        pet.react("heart")
        pet.toggleSleep()
        XCTAssertEqual(pet.animation, "dragged")
        pet.endDrag()
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "sleeping")
        XCTAssertFalse(pet.dragging)
    }

    func testDragInterruptsReactionAndDoesNotResumeOldCompletion() {
        var pet = Companion()
        pet.react("heart")
        pet.advance(seconds: 0.2, clips: clips)
        pet.beginDrag()
        pet.advance(seconds: 0.15, clips: clips)
        XCTAssertEqual(pet.animation, "pickup")
        pet.endDrag()
        pet.advance(seconds: 0.31, clips: clips)
        XCTAssertEqual(pet.animation, "idle")
        pet.react("eat")
        XCTAssertEqual(pet.animation, "eat")
    }

    func testLoopUsesElapsedTimeAndRejectsInvalidTicks() {
        var pet = Companion()
        pet.advance(seconds: 0.25, clips: clips)
        XCTAssertEqual(pet.frameIndex, 2)
        pet.advance(seconds: 0.1, clips: clips)
        XCTAssertEqual(pet.frameIndex, 0)
        pet.advance(seconds: .nan, clips: clips)
        pet.advance(seconds: -1, clips: clips)
        XCTAssertEqual(pet.frameIndex, 0)
    }

    func testManifestRejectsMissingEmptyInvalidAndUnsafeClips() throws {
        var animations = clips
        animations.removeValue(forKey: "heart")
        XCTAssertThrowsError(try Manifest(animations: animations).validated())
        for invalid in [Clip(frames: [], fps: 10, loop: false),
                        Clip(frames: ["a"], fps: 0, loop: false),
                        Clip(frames: ["../secret"], fps: 10, loop: false)] {
            animations = clips
            animations["heart"] = invalid
            XCTAssertThrowsError(try Manifest(animations: animations).validated())
        }
        XCTAssertNoThrow(try Manifest(animations: clips).validated())
    }

    func testRemovedDisplayRecoversToRemainingScreen() {
        let screen = CGRect(x: 0, y: 30, width: 1440, height: 870)
        let result = Placement.clamp(origin: CGPoint(x: 2200, y: -800),
                                     size: CGSize(width: 192, height: 192), screens: [screen])
        XCTAssertEqual(result, CGPoint(x: 1248, y: 30))
    }

    func testNegativeOriginMonitorAndOversizedPet() {
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(Placement.clamp(origin: CGPoint(x: -1000, y: 100),
                                      size: CGSize(width: 192, height: 192), screens: [left, right]),
                       CGPoint(x: -1000, y: 100))
        XCTAssertEqual(Placement.clamp(origin: .zero, size: CGSize(width: 2000, height: 2000), screens: [left]),
                       CGPoint(x: -1280, y: 0))
    }
}
