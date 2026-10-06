import Foundation

public struct Clip: Decodable, Equatable {
    public let frames: [String]
    public let fps: Double
    public let loop: Bool

    public init(frames: [String], fps: Double, loop: Bool) {
        self.frames = frames
        self.fps = fps
        self.loop = loop
    }
}

public struct Manifest: Decodable {
    public let animations: [String: Clip]

    public init(animations: [String: Clip] = [:]) {
        self.animations = animations
    }

    public static var standardTestManifest: Manifest {
        var clips: [String: Clip] = Dictionary(uniqueKeysWithValues: Companion.requiredClips.map {
            ($0, Clip(frames: ["f1", "f2"], fps: 10, loop: ["idle", "sleeping", "dragged", "walk", "walk_left"].contains($0)))
        })
        for emote in EmoteCatalog.all {
            clips[emote.id] = Clip(frames: ["f1", "f2"], fps: 10, loop: emote.isLooping)
        }
        return Manifest(animations: clips)
    }

    public func validated() throws -> Manifest {
        for name in Companion.requiredClips {
            guard animations[name] != nil else { throw ManifestError.invalidClip(name) }
        }
        for (name, clip) in animations {
            guard !clip.frames.isEmpty,
                  clip.fps.isFinite, clip.fps > 0, clip.fps <= 120,
                  clip.frames.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") })
            else { throw ManifestError.invalidClip(name) }
        }
        return self
    }
}

public enum ManifestError: Error { case invalidClip(String) }

/// One owner for sleep, drag, transient reactions, and emote playback. Completion always consults
/// current state, so dragging or sleeping cannot be undone by an old reaction or emote.
public struct Companion {
    public static let requiredClips = ["idle", "blink", "look", "heart", "bounce", "squish",
                                       "pickup", "dragged", "drop", "sleep", "sleeping", "wake", "eat",
                                       "walk", "walk_left"]
    public private(set) var animation = "idle"
    public var currentClipName: String { animation }
    public private(set) var activeEmote: Emote?
    private var emoteStartedAt: TimeInterval = 0
    public private(set) var sleeping = false
    public private(set) var dragging = false
    public private(set) var frameIndex = 0
    private var elapsed: Double = 0
    public var manifest: Manifest?

    public init(manifest: Manifest? = nil) {
        self.manifest = manifest
    }

    private mutating func play(_ name: String) {
        animation = name
        frameIndex = 0
        elapsed = 0
    }

    public mutating func playEmote(_ emote: Emote, now: TimeInterval = 0) {
        if walking { stopWalk() }
        sleeping = false
        dragging = false
        activeEmote = emote
        emoteStartedAt = now
        play(emote.id)
    }

    public mutating func react(_ name: String) {
        guard !sleeping, !dragging, ["bounce", "squish", "heart", "eat", "blink", "look"].contains(name) else { return }
        activeEmote = nil
        play(name)
    }

    public mutating func click(count: Int = 1, now: TimeInterval = 0) {
        activeEmote = nil
        if sleeping {
            toggleSleep()
        } else {
            react(count >= 2 ? "heart" : "bounce")
        }
    }

    public mutating func click(now: TimeInterval) {
        click(count: 1, now: now)
    }

    /// Derived from the clip, so any other animation (click, drag, sleep, emote) ends a walk by itself.
    public var walking: Bool { animation == "walk" || animation == "walk_left" }

    public mutating func startWalk(left: Bool) {
        guard !sleeping, !dragging, activeEmote == nil, animation == "idle" else { return }
        play(left ? "walk_left" : "walk")
    }

    public mutating func stopWalk() {
        if walking { play("idle") }
    }

    public mutating func toggleSleep() {
        guard !dragging else { return }
        activeEmote = nil
        sleeping.toggle()
        play(sleeping ? "sleep" : "wake")
    }

    public mutating func setSleeping(_ sleep: Bool, now: TimeInterval = 0) {
        guard !dragging else { return }
        activeEmote = nil
        if sleeping != sleep {
            sleeping = sleep
            play(sleep ? "sleep" : "wake")
        }
    }

    public mutating func startDrag(now: TimeInterval = 0) {
        activeEmote = nil
        beginDrag()
    }

    public mutating func beginDrag() {
        activeEmote = nil
        dragging = true
        play("pickup")
    }

    public mutating func endDrag() {
        guard dragging else { return }
        dragging = false
        activeEmote = nil
        play("drop")
    }

    public mutating func tick(now: TimeInterval, elapsed dt: TimeInterval) {
        if let emote = activeEmote {
            if (now - emoteStartedAt) >= emote.playbackDuration {
                activeEmote = nil
                play("idle")
            }
        }
        if let manifest = manifest {
            advance(seconds: dt, clips: manifest.animations)
        }
    }

    public mutating func advance(seconds: Double, clips: [String: Clip]) {
        guard seconds.isFinite, seconds > 0, let clip = clips[animation],
              !clip.frames.isEmpty, clip.fps.isFinite, clip.fps > 0 else { return }
        elapsed += seconds
        let duration = 1 / clip.fps
        if clip.loop {
            let steps = floor(elapsed / duration)
            frameIndex = (frameIndex + Int(steps.truncatingRemainder(dividingBy: Double(clip.frames.count)))) % clip.frames.count
            elapsed = elapsed.truncatingRemainder(dividingBy: duration)
        } else {
            let remaining = Double(clip.frames.count - frameIndex) * duration
            if elapsed >= remaining {
                if activeEmote != nil {
                    frameIndex = clip.frames.count - 1
                    elapsed = 0
                } else {
                    play(dragging ? "dragged" : sleeping ? "sleeping" : "idle")
                }
            } else {
                let steps = Int(elapsed / duration)
                frameIndex += steps
                elapsed -= Double(steps) * duration
            }
        }
    }
}
