import Foundation

/// Decides when Mochi takes a short walk along the bottom of the screen and how far it
/// moves each tick. It reads no screen and no clock, and takes its randomness as a closure,
/// so tests script every walk. The caller decides `canRoam` (not dragging, not asleep, not
/// typing, not in a focus session...) and the walk stops the moment that turns false.
public struct Roaming {
    public enum Event: Equatable { case begin(left: Bool), end }

    public static let speed = 40.0       // pixels per second
    public static let minWalk = 40.0     // never start a walk shorter than this
    public static let firstWait = 10.0   // seconds after launch before the first walk

    public var enabled = true
    public private(set) var walking = false
    private let random: () -> Double
    private var wait = Roaming.firstWait
    private var goLeft = false
    private var remaining = 0.0

    public init(random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
    }

    /// `x` is the pet's left edge; `room` is the range that edge may occupy on this display.
    /// Returns an optional event and how far to move horizontally this tick.
    public mutating func update(dt: Double, canRoam: Bool, x: Double,
                                room: ClosedRange<Double>) -> (event: Event?, dx: Double) {
        guard dt.isFinite, dt > 0 else { return (nil, 0) }

        if walking {
            guard enabled, canRoam else { return (finish(), 0) }
            let step = min(Self.speed * dt, remaining)
            let proposed = x + (goLeft ? -step : step)
            let clamped = min(max(proposed, room.lowerBound), room.upperBound)
            remaining -= step
            let done = remaining <= 1e-9 || clamped != proposed   // arrived, or hit an edge
            return (done ? finish() : nil, clamped - x)
        }

        guard enabled, canRoam else { return (nil, 0) }
        wait -= dt
        guard wait <= 0 else { return (nil, 0) }

        let roomLeft = x - room.lowerBound, roomRight = room.upperBound - x
        let canLeft = roomLeft >= Self.minWalk, canRight = roomRight >= Self.minWalk
        guard canLeft || canRight else { scheduleNext(); return (nil, 0) }
        let left = canLeft && canRight ? random() < 0.5 : canLeft
        remaining = min(80 + random() * 220, left ? roomLeft : roomRight)
        goLeft = left
        walking = true
        return (.begin(left: left), 0)
    }

    private mutating func finish() -> Event {
        walking = false
        scheduleNext()
        return .end
    }

    private mutating func scheduleNext() { wait = 8 + random() * 12 }
}
