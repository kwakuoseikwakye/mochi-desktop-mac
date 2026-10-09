import XCTest
@testable import MochiCore

final class BondTests: XCTestCase {
    func testBondPhaseThresholds() {
        XCTAssertEqual(BondPhase.phase(for: 0), .new)
        XCTAssertEqual(BondPhase.phase(for: 1), .new)
        XCTAssertEqual(BondPhase.phase(for: 2), .new)
        XCTAssertEqual(BondPhase.phase(for: 3), .familiar)
        XCTAssertEqual(BondPhase.phase(for: 4), .familiar)
        XCTAssertEqual(BondPhase.phase(for: 5), .comfortable)
        XCTAssertEqual(BondPhase.phase(for: 7), .comfortable)
        XCTAssertEqual(BondPhase.phase(for: 8), .close)
        XCTAssertEqual(BondPhase.phase(for: 10), .close)
        XCTAssertEqual(BondPhase.phase(for: 11), .deepBond)
        XCTAssertEqual(BondPhase.phase(for: 99), .deepBond)

        XCTAssertEqual(BondPhase.new.displayName, "New")
        XCTAssertEqual(BondPhase.familiar.displayName, "Familiar")
        XCTAssertEqual(BondPhase.comfortable.displayName, "Comfortable")
        XCTAssertEqual(BondPhase.close.displayName, "Close")
        XCTAssertEqual(BondPhase.deepBond.displayName, "Deep Bond")
    }

    func testBondStateCurveAndProgressFraction() {
        let stateLevel1 = BondState(level: 1, currentXP: 240, dailyEarnedXP: 240, lastActiveDate: "2026-10-09")
        XCTAssertEqual(stateLevel1.xpNeededForNextLevel, 480)
        XCTAssertEqual(stateLevel1.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(stateLevel1.phase, .new)

        let stateLevel2 = BondState(level: 2, currentXP: 0, dailyEarnedXP: 0, lastActiveDate: "2026-10-09")
        XCTAssertEqual(stateLevel2.xpNeededForNextLevel, 570)
        XCTAssertEqual(stateLevel2.progressFraction, 0.0, accuracy: 0.001)

        let stateLevel3 = BondState(level: 3, currentXP: 330, dailyEarnedXP: 330, lastActiveDate: "2026-10-09")
        XCTAssertEqual(stateLevel3.xpNeededForNextLevel, 660)
        XCTAssertEqual(stateLevel3.progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(stateLevel3.phase, .familiar)
    }

    func testDailyCapAndRollover() {
        let manager = BondManager(state: BondState(level: 1, currentXP: 0, dailyEarnedXP: 0, lastActiveDate: "2026-10-09"))
        let cal = Calendar(identifier: .gregorian)
        var components = DateComponents(year: 2026, month: 10, day: 9, hour: 10, minute: 0, second: 0)
        let day1 = cal.date(from: components)!

        // Typing 700 seconds should earn exactly 600 XP due to daily cap
        let earnedDay1 = manager.recordTyping(seconds: 700, at: day1)
        XCTAssertEqual(earnedDay1, 600)
        XCTAssertEqual(manager.state.dailyEarnedXP, 600)
        XCTAssertEqual(manager.state.currentXP, 120) // 600 - 480 (level 1 needed 480)
        XCTAssertEqual(manager.state.level, 2)

        // Additional typing on same day yields 0 XP
        let extra = manager.recordTyping(seconds: 50, at: day1)
        XCTAssertEqual(extra, 0)
        XCTAssertEqual(manager.state.dailyEarnedXP, 600)

        // Move to next day (2026-10-10)
        components.day = 10
        let day2 = cal.date(from: components)!
        let earnedDay2 = manager.recordTyping(seconds: 100, at: day2)
        XCTAssertEqual(earnedDay2, 100)
        XCTAssertEqual(manager.state.dailyEarnedXP, 100)
        XCTAssertEqual(manager.state.currentXP, 220)
        XCTAssertEqual(manager.state.level, 2)
    }

    func testFeedingWindowCap() {
        let manager = BondManager()
        let cal = Calendar(identifier: .gregorian)
        let t0 = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12, minute: 0, second: 0))!

        // Feed 1: +25 XP
        XCTAssertEqual(manager.recordFeeding(at: t0), 25)
        // Feed 2 within 10 min: +25 XP
        let t1 = t0.addingTimeInterval(120) // 2 min later
        XCTAssertEqual(manager.recordFeeding(at: t1), 25)
        // Feed 3 within 10 min: 0 XP
        let t2 = t0.addingTimeInterval(300) // 5 min later
        XCTAssertEqual(manager.recordFeeding(at: t2), 0)
        // Feed 4 after 10 min window: +25 XP
        let t3 = t0.addingTimeInterval(601) // 10 min 1s later
        XCTAssertEqual(manager.recordFeeding(at: t3), 25)
    }

    func testFocusCompletionAndLevelUpCallback() {
        let manager = BondManager()
        var levelUpCalls: [(Int, BondPhase)] = []
        manager.onLevelUp = { lvl, phase in
            levelUpCalls.append((lvl, phase))
        }

        let date = Date()
        // Focus completes: +150 XP
        XCTAssertEqual(manager.recordFocusCompleted(at: date), 150)
        XCTAssertEqual(manager.state.currentXP, 150)
        XCTAssertTrue(levelUpCalls.isEmpty)

        // 3 more focus sessions (+450 XP, capped at remaining 450 XP for daily 600 XP)
        XCTAssertEqual(manager.recordFocusCompleted(at: date), 150) // 300 XP
        XCTAssertEqual(manager.recordFocusCompleted(at: date), 150) // 450 XP
        // 4th session: needed 480 XP for Level 2. At 480 XP, level up fires!
        XCTAssertEqual(manager.recordFocusCompleted(at: date), 150) // 600 XP total, level 2!

        XCTAssertEqual(manager.state.level, 2)
        XCTAssertEqual(manager.state.currentXP, 120) // 600 - 480
        XCTAssertEqual(levelUpCalls.count, 1)
        XCTAssertEqual(levelUpCalls.first?.0, 2)
        XCTAssertEqual(levelUpCalls.first?.1, .new)
    }

    func testResetBond() {
        let manager = BondManager(state: BondState(level: 5, currentXP: 300, dailyEarnedXP: 400, lastActiveDate: "2026-10-09"))
        manager.reset()
        XCTAssertEqual(manager.state.level, 1)
        XCTAssertEqual(manager.state.currentXP, 0)
        XCTAssertEqual(manager.state.dailyEarnedXP, 0)
        XCTAssertEqual(manager.state.phase, .new)
    }
}

