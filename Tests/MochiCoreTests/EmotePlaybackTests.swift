import XCTest
@testable import MochiCore

final class EmotePlaybackTests: XCTestCase {
    func testPlayEmoteSetsCurrentClipAndActiveEmote() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "table_flip", displayName: "Table Flip", category: .reactions, isLooping: false, playbackDuration: 2.0)

        companion.playEmote(emote, now: 100.0)
        XCTAssertEqual(companion.currentClipName, "table_flip")
        XCTAssertEqual(companion.activeEmote?.id, "table_flip")
    }

    func testOneShotEmoteCompletesAndRestoresIdle() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "table_flip", displayName: "Table Flip", category: .reactions, isLooping: false, playbackDuration: 2.0)

        companion.playEmote(emote, now: 100.0)
        companion.tick(now: 101.0, elapsed: 1.0)
        XCTAssertEqual(companion.currentClipName, "table_flip")

        companion.tick(now: 102.5, elapsed: 1.5)
        XCTAssertEqual(companion.currentClipName, "idle")
        XCTAssertNil(companion.activeEmote)
    }

    func testClickOrDragInterruptsEmoteImmediately() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "dance", displayName: "Dance", category: .playful, isLooping: true, playbackDuration: 6.0)

        companion.playEmote(emote, now: 100.0)
        XCTAssertEqual(companion.activeEmote?.id, "dance")

        companion.startDrag(now: 101.0)
        XCTAssertNil(companion.activeEmote)
        XCTAssertEqual(companion.currentClipName, "pickup")
    }

    func testClickInterruptsEmoteImmediately() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "dance", displayName: "Dance", category: .playful, isLooping: true, playbackDuration: 6.0)

        companion.playEmote(emote, now: 100.0)
        XCTAssertEqual(companion.activeEmote?.id, "dance")

        companion.click(now: 101.0)
        XCTAssertNil(companion.activeEmote)
        XCTAssertEqual(companion.currentClipName, "bounce")
    }

    func testSleepInterruptsEmoteImmediately() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "dance", displayName: "Dance", category: .playful, isLooping: true, playbackDuration: 6.0)

        companion.playEmote(emote, now: 100.0)
        XCTAssertEqual(companion.activeEmote?.id, "dance")

        companion.setSleeping(true, now: 101.0)
        XCTAssertNil(companion.activeEmote)
        XCTAssertEqual(companion.currentClipName, "sleep")
        XCTAssertTrue(companion.sleeping)
    }

    func testLoopingEmotePlaysUntilDurationThenRestoresIdle() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        let emote = Emote(id: "dance", displayName: "Dance", category: .playful, isLooping: true, playbackDuration: 6.0)

        companion.playEmote(emote, now: 100.0)
        companion.tick(now: 103.0, elapsed: 3.0)
        XCTAssertEqual(companion.currentClipName, "dance")
        XCTAssertEqual(companion.activeEmote?.id, "dance")

        companion.tick(now: 106.1, elapsed: 3.1)
        XCTAssertEqual(companion.currentClipName, "idle")
        XCTAssertNil(companion.activeEmote)
    }

    func testPlayingEmoteStopsWalk() {
        let manifest = Manifest.standardTestManifest
        var companion = Companion(manifest: manifest)
        companion.startWalk(left: false)
        XCTAssertTrue(companion.walking)

        let emote = Emote(id: "table_flip", displayName: "Table Flip", category: .reactions, isLooping: false, playbackDuration: 2.0)
        companion.playEmote(emote, now: 100.0)

        XCTAssertFalse(companion.walking)
        XCTAssertEqual(companion.currentClipName, "table_flip")
        XCTAssertEqual(companion.activeEmote?.id, "table_flip")
    }
}
