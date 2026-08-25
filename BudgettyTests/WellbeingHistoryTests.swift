//
//  WellbeingHistoryTests.swift
//  BudgettyTests
//
//  Pins the pure history-snapshot logic (§3.1) — the Swift port of Android's `WellbeingHistoryTest`:
//  the closed-vs-in-flight month decision, the "yyyy-MM" id math (calendar and pay-cycle), the
//  componentsJson round-trip the future breakdown view reads, and the §3.2 trend-sparkline model.
//
//  A fixed UTC Gregorian calendar keeps the day math independent of the runner's timezone, matching the
//  Android test's explicit `LocalDate`s.
//

import Testing
import Foundation
@testable import Budgetty

@MainActor
struct WellbeingHistoryTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func scoreOf(_ total: Int?, _ band: WellbeingBand?) -> WellbeingScore {
        WellbeingScore(score: total, band: band, components: [
            WellbeingComponent(key: .savings, weight: WellbeingEngine.wSavings, score: 80),
            WellbeingComponent(key: .budget, weight: WellbeingEngine.wBudget, score: 60),
            WellbeingComponent(key: .trend, weight: WellbeingEngine.wTrend, score: nil),
            WellbeingComponent(key: .subscriptions, weight: WellbeingEngine.wSubscriptions, score: 100),
            WellbeingComponent(key: .goals, weight: WellbeingEngine.wGoals, score: nil),
        ], trendDeltaVsPrevious: nil)
    }

    private func entity(_ periodId: String, _ score: Int) -> WellbeingScoreEntity {
        WellbeingScoreEntity(periodId: periodId, score: score, band: WellbeingEngine.band(score).name,
                             componentsJson: "{}", computedAt: Date(timeIntervalSince1970: 0))
    }

    // ── periodId identity ────────────────────────────────────────────────────────

    @Test func calendarMonthClosedIdIsThePreviousMonthAndDiffersFromTheCurrentOne() {
        let today = day(2026, 3, 15)
        #expect(WellbeingHistory.periodId(today, monthStartDay: 1, offset: 0, calendar: cal) == "2026-03")
        #expect(WellbeingHistory.periodId(today, monthStartDay: 1, offset: -1, calendar: cal) == "2026-02")
    }

    @Test func payCycleMonthUsesTheSalaryAnchoredCycleNotTheCalendarMonth() {
        // Pay day 25th: on the 15th, today sits in the tail of the cycle that opened on Feb 25 → the
        // current cycle is "2026-02" and the just-closed one is "2026-01".
        let today = day(2026, 3, 15)
        #expect(WellbeingHistory.periodId(today, monthStartDay: 25, offset: 0, calendar: cal) == "2026-02")
        #expect(WellbeingHistory.periodId(today, monthStartDay: 25, offset: -1, calendar: cal) == "2026-01")
    }

    @Test func closedIdRollsOverTheYearBoundary() {
        let today = day(2026, 1, 10)
        #expect(WellbeingHistory.periodId(today, monthStartDay: 1, offset: -1, calendar: cal) == "2025-12")
    }

    // ── closed-month snapshot (the guard) ─────────────────────────────────────────

    @Test func snapshotStoresTheClosedMonthAndNeverTheInFlightOne() throws {
        let today = day(2026, 3, 15)
        let closedId = WellbeingHistory.periodId(today, monthStartDay: 1, offset: -1, calendar: cal)
        let currentId = WellbeingHistory.periodId(today, monthStartDay: 1, offset: 0, calendar: cal)

        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let entity = WellbeingHistory.closedSnapshot(closedPeriodId: closedId,
                                                     closedScore: scoreOf(72, .healthy), computedAt: when)
        let e = try #require(entity)
        #expect(e.periodId == "2026-02")
        #expect(e.periodId != currentId) // the in-flight month is never the target
        #expect(e.score == 72)
        #expect(e.band == "HEALTHY")
        #expect(e.computedAt == when)
    }

    @Test func snapshotIsNilWhenTheClosedMonthCannotBeScoredYet() {
        // A brand-new account (too few receipts) scores nil → no junk row is ever written.
        let entity = WellbeingHistory.closedSnapshot(closedPeriodId: "2026-02",
                                                     closedScore: scoreOf(nil, nil),
                                                     computedAt: Date(timeIntervalSince1970: 1))
        #expect(entity == nil)
    }

    // ── componentsJson round-trip ─────────────────────────────────────────────────

    @Test func componentsJsonPreservesEveryComponentIncludingTheUnScoredNulls() {
        let json = WellbeingHistory.encodeComponents(scoreOf(72, .healthy).components)
        // Fixed order + explicit nulls, matching Android's Gson serializeNulls over a LinkedHashMap.
        #expect(json == "{\"SAVINGS\":80,\"BUDGET\":60,\"TREND\":null,\"SUBSCRIPTIONS\":100,\"GOALS\":null}")

        let decoded = WellbeingHistory.decodeComponents(json)
        #expect(Set(decoded.keys) == ["SAVINGS", "BUDGET", "TREND", "SUBSCRIPTIONS", "GOALS"])
        // Values (double-optional: outer = key present, inner = the sub-score or an explicit nil).
        if let savings = decoded["SAVINGS"] { #expect(savings == 80) } else { Issue.record("SAVINGS dropped") }
        if let budget = decoded["BUDGET"] { #expect(budget == 60) } else { Issue.record("BUDGET dropped") }
        if let subs = decoded["SUBSCRIPTIONS"] { #expect(subs == 100) } else { Issue.record("SUBSCRIPTIONS dropped") }
        // A component with no data is kept as an explicit null, not dropped.
        #expect(decoded.keys.contains("TREND"))
        if let trend = decoded["TREND"] { #expect(trend == nil) } else { Issue.record("TREND dropped") }
        if let goals = decoded["GOALS"] { #expect(goals == nil) } else { Issue.record("GOALS dropped") }
    }

    @Test func decodeComponentsToleratesAMalformedPayload() {
        #expect(WellbeingHistory.decodeComponents("not json").isEmpty)
    }

    // ── §3.2 trend sparkline model ────────────────────────────────────────────────

    @Test func trendRendersNothingBelowTwoStoredMonths() {
        // The whole point of the thin-data state: one point (or none) is not a trend → nil (no card).
        #expect(WellbeingHistory.trend([], liveScore: 57) == nil)
        #expect(WellbeingHistory.trend([entity("2026-03", 49)], liveScore: 57) == nil)
    }

    @Test func trendBuildsFromStoredMonthsAndAnchorsTheDeltaOnTheLiveGhost() throws {
        let stored = [entity("2026-03", 49), entity("2026-04", 52), entity("2026-05", 55)]
        let trend = try #require(WellbeingHistory.trend(stored, liveScore: 57))
        #expect(trend.closed.map(\.score) == [49, 52, 55])
        #expect(trend.closed.first?.yearMonth == YearMonth(id: "2026-03"))
        #expect(trend.firstMonth == YearMonth(id: "2026-03"))
        #expect(trend.liveScore == 57)
        #expect(trend.deltaSinceFirst == 8) // "now" (live 57) − first shown (49)
    }

    @Test func trendDeltaFallsBackToTheLastClosedMonthWhenThereIsNoLiveScore() throws {
        let stored = [entity("2026-03", 49), entity("2026-04", 60)]
        let trend = try #require(WellbeingHistory.trend(stored, liveScore: nil))
        #expect(trend.liveScore == nil)
        #expect(trend.deltaSinceFirst == 11) // last closed (60) − first (49)
    }

    @Test func trendDropsAMalformedPeriodIdAndStillRequiresTwoValidMonths() {
        let mixed = [entity("2026-03", 49), entity("bogus", 50)]
        #expect(WellbeingHistory.trend(mixed, liveScore: 57) == nil) // only one usable point left
    }
}
