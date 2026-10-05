import Foundation

/// A single fixed-length focus session. It uses wall-clock `Date` so it can be saved and
/// resumed after a relaunch; the caller supplies `now`, so tests never wait for real time.
public struct Focus {
    // ponytail: one fixed length. Add a list of lengths if users ask for it.
    public static let length: TimeInterval = 25 * 60

    public private(set) var endsAt: Date?

    public init() {}

    public var isActive: Bool { endsAt != nil }

    public mutating func start(now: Date) { endsAt = now.addingTimeInterval(Self.length) }
    public mutating func stop() { endsAt = nil }

    public func remaining(now: Date) -> TimeInterval {
        max(endsAt.map { $0.timeIntervalSince(now) } ?? 0, 0)
    }

    /// Returns true exactly once, when the session runs out.
    public mutating func update(now: Date) -> Bool {
        guard let end = endsAt, now >= end else { return false }
        endsAt = nil
        return true
    }

    /// Resume a saved end time only if it could belong to a session started within the last
    /// `length` seconds. Anything else (already over, or the clock moved) is dropped silently.
    public mutating func restore(endsAt saved: Date?, now: Date) {
        guard let saved, saved > now, saved.timeIntervalSince(now) <= Self.length else {
            endsAt = nil
            return
        }
        endsAt = saved
    }
}
