import Foundation
import AVFoundation
import MochiCore

public final class MacAudioService: AudioPlaybackDelegate {
    public static let shared = MacAudioService()

    private var soundPlayers: [SoundEvent: AVAudioPlayer] = [:]
    private var ambientPlayer: AVAudioPlayer?
    private var fadeTimer: Timer?

    private init() {
        preloadShortSounds()
    }

    private func soundURL(for event: SoundEvent) -> URL? {
        let filename: String
        switch event {
        case .chirp: filename = "chirp"
        case .eat: filename = "eat"
        case .spawn: filename = "spawn"
        case .exit: filename = "exit"
        case .menuOpen: filename = "menu_open"
        case .levelUp: filename = "level_up"
        case .rainLoop: filename = "rain"
        }

        if let bundleURL = Bundle.main.url(forResource: filename, withExtension: "wav", subdirectory: "Audio") {
            return bundleURL
        }
        if let moduleURL = Bundle.module.url(forResource: filename, withExtension: "wav", subdirectory: "Resources/Audio") {
            return moduleURL
        }
        // Fallback for command-line runs and dev builds:
        let devPath = "macos/Sources/MochiMac/Resources/Audio/\(filename).wav"
        if FileManager.default.fileExists(atPath: devPath) {
            return URL(fileURLWithPath: devPath)
        }
        let altDevPath = "Sources/MochiMac/Resources/Audio/\(filename).wav"
        if FileManager.default.fileExists(atPath: altDevPath) {
            return URL(fileURLWithPath: altDevPath)
        }
        return nil
    }

    private func preloadShortSounds() {
        for event in [SoundEvent.chirp, .eat, .spawn, .exit, .menuOpen, .levelUp] {
            guard let url = soundURL(for: event) else { continue }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                soundPlayers[event] = player
            } catch {
                NSLog("[MochiMac] Could not preload sound for \(event): \(error)")
            }
        }
    }

    public func play(event: SoundEvent, effectiveVolume: Double) {
        let volume = Float(max(0.0, min(1.0, effectiveVolume)))
        guard volume > 0 else { return }

        if let existing = soundPlayers[event] {
            existing.volume = volume
            existing.currentTime = 0
            existing.play()
            return
        }

        guard let url = soundURL(for: event) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.play()
            soundPlayers[event] = player
        } catch {
            NSLog("[MochiMac] Error playing sound for \(event): \(error)")
        }
    }

    public func startAmbientLoop(event: SoundEvent, effectiveVolume: Double) {
        let targetVolume = Float(max(0.0, min(1.0, effectiveVolume)))
        guard targetVolume > 0 else { return }

        fadeTimer?.invalidate()
        fadeTimer = nil

        if let current = ambientPlayer, current.isPlaying {
            current.setVolume(targetVolume, fadeDuration: 0.3)
            return
        }

        guard let url = soundURL(for: event) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.play()
            player.setVolume(targetVolume, fadeDuration: 0.5)
            self.ambientPlayer = player
        } catch {
            NSLog("[MochiMac] Error starting ambient loop for \(event): \(error)")
        }
    }

    public func stopAmbientLoop() {
        guard let player = ambientPlayer, player.isPlaying else { return }
        fadeTimer?.invalidate()
        player.setVolume(0.0, fadeDuration: 0.3)
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.ambientPlayer?.stop()
            self?.ambientPlayer = nil
        }
    }
}
