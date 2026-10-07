import XCTest
@testable import MochiCore

final class MockAudioDelegate: AudioPlaybackDelegate {
    var playedEvents: [(event: SoundEvent, volume: Double)] = []
    var ambientLoopsStarted: [(event: SoundEvent, volume: Double)] = []
    var ambientLoopsStoppedCount = 0

    func play(event: SoundEvent, effectiveVolume: Double) {
        playedEvents.append((event, effectiveVolume))
    }

    func startAmbientLoop(event: SoundEvent, effectiveVolume: Double) {
        ambientLoopsStarted.append((event, effectiveVolume))
    }

    func stopAmbientLoop() {
        ambientLoopsStoppedCount += 1
    }
}

final class SoundTests: XCTestCase {
    func testSettingsClampingAndDefaults() {
        let defaultSettings = SoundSettings()
        XCTAssertTrue(defaultSettings.isMuted)
        XCTAssertEqual(defaultSettings.volume, 0.5, accuracy: 0.001)
        XCTAssertFalse(defaultSettings.isFocusRainEnabled)

        var settings = SoundSettings(isMuted: false, volume: 1.5, isFocusRainEnabled: true)
        XCTAssertEqual(settings.volume, 1.0, accuracy: 0.001)

        settings.setVolume(-0.2)
        XCTAssertEqual(settings.volume, 0.0, accuracy: 0.001)

        settings.volume = 1.6
        XCTAssertEqual(settings.volume, 1.0, accuracy: 0.001)

        settings.volume = -0.5
        XCTAssertEqual(settings.volume, 0.0, accuracy: 0.001)
    }

    func testMutedSoundManagerDispatchesNothing() {
        let delegate = MockAudioDelegate()
        let settings = SoundSettings(isMuted: true, volume: 0.8)
        let manager = SoundManager(settings: settings, delegate: delegate)

        manager.trigger(.chirp)
        manager.trigger(.eat)
        manager.startFocusAmbience()

        XCTAssertTrue(delegate.playedEvents.isEmpty)
        XCTAssertTrue(delegate.ambientLoopsStarted.isEmpty)
    }

    func testUnmutedSoundManagerDispatchesWithGainMultipliers() {
        let delegate = MockAudioDelegate()
        let settings = SoundSettings(isMuted: false, volume: 1.0, isFocusRainEnabled: true)
        let manager = SoundManager(settings: settings, delegate: delegate)

        manager.trigger(.chirp)
        XCTAssertEqual(delegate.playedEvents.count, 1)
        XCTAssertEqual(delegate.playedEvents[0].event, .chirp)
        XCTAssertEqual(delegate.playedEvents[0].volume, 1.0, accuracy: 0.001)

        manager.trigger(.spawn)
        XCTAssertEqual(delegate.playedEvents.count, 2)
        XCTAssertEqual(delegate.playedEvents[1].event, .spawn)
        XCTAssertEqual(delegate.playedEvents[1].volume, 0.35, accuracy: 0.001)

        manager.trigger(.menuOpen)
        XCTAssertEqual(delegate.playedEvents.count, 3)
        XCTAssertEqual(delegate.playedEvents[2].event, .menuOpen)
        XCTAssertEqual(delegate.playedEvents[2].volume, 0.22, accuracy: 0.001)

        manager.startFocusAmbience()
        XCTAssertEqual(delegate.ambientLoopsStarted.count, 1)
        XCTAssertEqual(delegate.ambientLoopsStarted[0].event, .rainLoop)
        XCTAssertEqual(delegate.ambientLoopsStarted[0].volume, 0.50, accuracy: 0.001)

        manager.stopFocusAmbience()
        XCTAssertEqual(delegate.ambientLoopsStoppedCount, 1)
    }

    func testFocusAmbienceRespectsRainSetting() {
        let delegate = MockAudioDelegate()
        let settings = SoundSettings(isMuted: false, volume: 0.8, isFocusRainEnabled: false)
        let manager = SoundManager(settings: settings, delegate: delegate)

        manager.startFocusAmbience()
        XCTAssertTrue(delegate.ambientLoopsStarted.isEmpty)

        var updated = settings
        updated.isFocusRainEnabled = true
        manager.updateSettings(updated)

        manager.startFocusAmbience()
        XCTAssertEqual(delegate.ambientLoopsStarted.count, 1)
    }

    func testMuteTransitionStopsAmbientLoop() {
        let delegate = MockAudioDelegate()
        let settings = SoundSettings(isMuted: false, volume: 0.8, isFocusRainEnabled: true)
        let manager = SoundManager(settings: settings, delegate: delegate)

        manager.startFocusAmbience()
        XCTAssertEqual(delegate.ambientLoopsStarted.count, 1)

        var mutedSettings = settings
        mutedSettings.isMuted = true
        manager.updateSettings(mutedSettings)

        XCTAssertEqual(delegate.ambientLoopsStoppedCount, 1)
    }
}
