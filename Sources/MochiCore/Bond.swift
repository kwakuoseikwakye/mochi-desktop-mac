import Foundation

public enum BondPhase: String, CaseIterable, Equatable {
    case new
    case familiar
    case comfortable
    case close
    case deepBond

    public var displayName: String {
        switch self {
        case .new: return "New"
        case .familiar: return "Familiar"
        case .comfortable: return "Comfortable"
        case .close: return "Close"
        case .deepBond: return "Deep Bond"
        }
    }

    public static func phase(for level: Int) -> BondPhase {
        let lvl = max(1, level)
        switch lvl {
        case 1...2: return .new
        case 3...4: return .familiar
        case 5...7: return .comfortable
        case 8...10: return .close
        default: return .deepBond
        }
    }
}

public struct BondState: Equatable {
    public var level: Int
    public var currentXP: Int
    public var dailyEarnedXP: Int
    public var lastActiveDate: String

    public init(
        level: Int = 1,
        currentXP: Int = 0,
        dailyEarnedXP: Int = 0,
        lastActiveDate: String = ""
    ) {
        self.level = max(1, level)
        self.currentXP = max(0, currentXP)
        self.dailyEarnedXP = max(0, dailyEarnedXP)
        self.lastActiveDate = lastActiveDate
    }

    public var xpNeededForNextLevel: Int {
        480 + (max(1, level) - 1) * 90
    }

    public var phase: BondPhase {
        BondPhase.phase(for: level)
    }

    public var progressFraction: Double {
        let needed = xpNeededForNextLevel
        guard needed > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(currentXP) / Double(needed)))
    }
}

public final class BondManager {
    public static let dailyMaxXP: Int = 600
    public static let feedXP: Int = 25
    public static let focusXP: Int = 150
    public static let feedWindowSeconds: TimeInterval = 600 // 10 minutes
    public static let maxFeedsPerWindow: Int = 2

    public private(set) var state: BondState
    public var onLevelUp: ((_ newLevel: Int, _ newPhase: BondPhase) -> Void)?

    private var recentFeeds: [Date] = []
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        return df
    }()

    public init(state: BondState = BondState()) {
        self.state = state
    }

    public func reset() {
        state = BondState(level: 1, currentXP: 0, dailyEarnedXP: 0, lastActiveDate: "")
        recentFeeds.removeAll()
    }

    public func checkRollover(at now: Date) {
        let today = Self.dateFormatter.string(from: now)
        if state.lastActiveDate.isEmpty {
            state.lastActiveDate = today
        } else if state.lastActiveDate != today {
            state.dailyEarnedXP = 0
            state.lastActiveDate = today
        }
    }

    @discardableResult
    public func recordTyping(seconds: Double, at now: Date = Date()) -> Int {
        guard seconds >= 1.0 else { return 0 }
        let rawXP = Int(seconds)
        return addXP(rawXP, at: now)
    }

    @discardableResult
    public func recordFeeding(at now: Date = Date()) -> Int {
        checkRollover(at: now)
        recentFeeds = recentFeeds.filter { now.timeIntervalSince($0) < Self.feedWindowSeconds }
        guard recentFeeds.count < Self.maxFeedsPerWindow else { return 0 }
        recentFeeds.append(now)
        return addXP(Self.feedXP, at: now)
    }

    @discardableResult
    public func recordFocusCompleted(at now: Date = Date()) -> Int {
        return addXP(Self.focusXP, at: now)
    }

    private func addXP(_ xpToAdd: Int, at now: Date) -> Int {
        guard xpToAdd > 0 else { return 0 }
        checkRollover(at: now)

        let remainingDaily = max(0, Self.dailyMaxXP - state.dailyEarnedXP)
        let actualXP = min(xpToAdd, remainingDaily)
        guard actualXP > 0 else { return 0 }

        state.dailyEarnedXP += actualXP
        state.currentXP += actualXP

        while state.currentXP >= state.xpNeededForNextLevel {
            let needed = state.xpNeededForNextLevel
            state.currentXP -= needed
            state.level += 1
            onLevelUp?(state.level, state.phase)
        }

        return actualXP
    }
}

