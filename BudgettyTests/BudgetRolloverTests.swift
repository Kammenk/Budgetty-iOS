//
//  BudgetRolloverTests.swift
//  BudgettyTests
//
//  The unspent-only roll-forward math. A direct port of Android's BudgetRolloverTest. A fixed UTC
//  Gregorian calendar keeps the period-key math independent of the runner's timezone.
//

import Testing
import Foundation
@testable import Budgetty

struct BudgetRolloverTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func currentPeriodKeyIsThePayCycleStartMonth() {
        #expect(BudgetRolloverMath.currentPeriodKey(day(2026, 7, 25), startDay: 1, calendar: cal) == "2026-07")
        // Pay day 25: Jul 25 opens the Jul cycle; Jul 10 still sits in the Jun 25 – Jul 24 cycle.
        #expect(BudgetRolloverMath.currentPeriodKey(day(2026, 7, 25), startDay: 25, calendar: cal) == "2026-07")
        #expect(BudgetRolloverMath.currentPeriodKey(day(2026, 7, 10), startDay: 25, calendar: cal) == "2026-06")
    }

    @Test func nextPeriodKeyRollsTheYearOver() {
        #expect(BudgetRolloverMath.nextPeriodKey("2026-12") == "2027-01")
    }

    @Test func unspentBudgetAccumulatesAcrossElapsedPeriods() {
        // Budget 400. May spent 350 -> 50 left; June spent 300 -> 400+50-300 = 150 left. Roll to July.
        let spent = ["2026-05": Decimal(350), "2026-06": Decimal(300)]
        let carried = BudgetRolloverMath.rollForward(
            storedCarried: 0,
            storedPeriodKey: "2026-05",
            currentPeriodKey: "2026-07",
            budget: 400
        ) { spent[$0] ?? 0 }
        #expect(carried == 150)
    }

    @Test func overspendIsForgivenNeverRollsNegative() {
        let carried = BudgetRolloverMath.rollForward(
            storedCarried: 0,
            storedPeriodKey: "2026-05",
            currentPeriodKey: "2026-06",
            budget: 400
        ) { _ in 500 } // spent 500 on a 400 budget
        #expect(carried == 0)
    }

    @Test func theCarriedBufferAbsorbsOverspendButNeverGoesNegative() {
        // Available = budget + carried = 400 + 120 = 520; spending 500 draws the buffer down to 20.
        let carried = BudgetRolloverMath.rollForward(
            storedCarried: 120,
            storedPeriodKey: "2026-05",
            currentPeriodKey: "2026-06",
            budget: 400
        ) { _ in 500 }
        #expect(carried == 20)
    }

    @Test func alreadyCaughtUpIsANoOp() {
        var queried = false
        let carried = BudgetRolloverMath.rollForward(
            storedCarried: 50,
            storedPeriodKey: "2026-07",
            currentPeriodKey: "2026-07",
            budget: 400
        ) { _ in queried = true; return 0 }
        #expect(carried == 50)
        #expect(!queried) // no spend query when already current
    }
}
