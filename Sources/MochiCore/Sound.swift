import Foundation

public enum SoundEvent: String, CaseIterable, Equatable {
    case chirp
    case eat
    case spawn
    case exit
    case menuOpen
    case levelUp
    case rainLoop

    public var gain: Double {
        switch self {
        case .chirp, .eat, .levelUp:
            return 1.0
        case .rainLoop:
            return 0.5
        case .spawn:
            return 0.35
        case .exit:
            return 0.28
        case .menuOpen:
            return 0.22
        }
    }
}

public struct SoundSettings: Equatable {
    public var isMuted: Bool
    public var volume: Double {
        didSet {
            let clamped = max(0.0, min(1.0, volume))
            if volume != clamped { volume = clamped }
        }
    }
    public var isFocusRainEnabled: Bool

    public static let defaultVolume: Double = 0.5

    public init(
        isMuted: Bool = true,
        volume: Double = defaultVolume,
        isFocusRainEnabled: Bool = false
    ) {
        self.isMuted = isMuted
        self.volume = max(0.0, min(1.0, volume))
        self.isFocusRainEnabled = isFocusRainEnabled
    }

    public mutating func setVolume(_ newVolume: Double) {
        self.volume = max(0.0, min(1.0, newVolume))
    }
}

public protocol AudioPlaybackDelegate: AnyObject {
    func play(event: SoundEvent, effectiveVolume: Double)
    func startAmbientLoop(event: SoundEvent, effectiveVolume: Double)
    func stopAmbientLoop()
}

public final class SoundManager {
    public private(set) var settings: SoundSettings
    public weak var delegate: AudioPlaybackDelegate?

    public init(settings: SoundSettings = SoundSettings(), delegate: AudioPlaybackDelegate? = nil) {
        self.settings = settings
        self.delegate = delegate
    }

    public func updateSettings(_ newSettings: SoundSettings) {
        let wasMuted = settings.isMuted
        self.settings = newSettings
        if !wasMuted && newSettings.isMuted {
            delegate?.stopAmbientLoop()
        }
    }

    public func trigger(_ event: SoundEvent) {
        guard !settings.isMuted, settings.volume > 0 else { return }
        let effectiveVolume = settings.volume * event.gain
        delegate?.play(event: event, effectiveVolume: effectiveVolume)
    }

    public func startFocusAmbience() {
        guard !settings.isMuted, settings.volume > 0, settings.isFocusRainEnabled else { return }
        let effectiveVolume = settings.volume * SoundEvent.rainLoop.gain
        delegate?.startAmbientLoop(event: .rainLoop, effectiveVolume: effectiveVolume)
    }

    public func stopFocusAmbience() {
        delegate?.stopAmbientLoop()
    }
}
