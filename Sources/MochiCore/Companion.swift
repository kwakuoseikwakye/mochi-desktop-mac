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

/// One owner for sleep, drag and transient reactions. Completion always consults
/// current state, so dragging or sleeping cannot be undone by an old reaction.
public struct Companion {
    public static let requiredClips = ["idle", "blink", "look", "heart", "bounce", "squish",
                                       "pickup", "dragged", "drop", "sleep", "sleeping", "wake", "eat",
                                       "walk", "walk_left"]
    public private(set) var animation = "idle"
    public private(set) var sleeping = false
    public private(set) var dragging = false
    public private(set) var frameIndex = 0
    private var elapsed: Double = 0

    public init() {}

    private mutating func play(_ name: String) {
        animation = name
        frameIndex = 0
        elapsed = 0
    }

    public mutating func react(_ name: String) {
        guard !sleeping, !dragging, ["bounce", "squish", "heart", "eat", "blink", "look"].contains(name) else { return }
        play(name)
    }

    /// Derived from the clip, so any other animation (click, drag, sleep) ends a walk by itself.
    public var walking: Bool { animation == "walk" || animation == "walk_left" }

    public mutating func startWalk(left: Bool) {
        guard !sleeping, !dragging, animation == "idle" else { return }
        play(left ? "walk_left" : "walk")
    }

    public mutating func stopWalk() {
        if walking { play("idle") }
    }

    public mutating func toggleSleep() {
        guard !dragging else { return }
        sleeping.toggle()
        play(sleeping ? "sleep" : "wake")
    }

    public mutating func beginDrag() {
        dragging = true
        play("pickup")
    }

    public mutating func endDrag() {
        guard dragging else { return }
        dragging = false
        play("drop")
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
                play(dragging ? "dragged" : sleeping ? "sleeping" : "idle")
            } else {
                let steps = Int(elapsed / duration)
                frameIndex += steps
                elapsed -= Double(steps) * duration
            }
        }
    }
}
