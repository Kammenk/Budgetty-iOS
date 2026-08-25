//
//  RecapWeekStreakTests.swift
//  BudgettyTests
//
//  Pins the two pure pieces of the weekly outcome-streak sourcing (§1.3) — the Swift port of Android's
//  `RecapWeekStreakTest`, case for case: `RecapBuilder.weeklyShareOf` (a monthly budget sliced to one
//  week) and `RecapBuilder.pickWeekStreak` (which single scope the weekly Streak card surfaces — a live
//  current run first, else a best-run fallback, both at the ≥ 2 floor).
//

import Testing
import Foundation
@testable import Budgetty

struct RecapWeekStreakTests {

    private func weekStreak(_ label: String, current: Int, best: Int, live: Bool = false) -> Streak {
        Streak(kind: .budgetWeek, label: label, current: current, best: best,
               periodsChecked: max(current, best), liveOnTrack: live)
    }

    // ── weeklyShareOf: monthly budget → weekly allowance (× 12 ⁄ 52) ──────────────

    @Test func weekly_share_slices_a_monthly_budget_to_a_week() {
        // 400 × 12 ⁄ 52 = 92.3076… → 92.31 (2dp, HALF_UP).
        #expect(RecapBuilder.weeklyShareOf(Decimal(string: "400")!) == Decimal(string: "92.31"))
    }

    @Test func weekly_share_is_exact_when_it_divides_evenly() {
        // 130 × 12 ⁄ 52 = 30 exactly.
        #expect(RecapBuilder.weeklyShareOf(Decimal(string: "130")!) == Decimal(30))
    }

    @Test func weekly_share_of_zero_is_zero() {
        #expect(RecapBuilder.weeklyShareOf(Decimal.zero) == Decimal.zero)
    }

    // ── pickWeekStreak: which single scope surfaces ───────────────────────────────

    @Test func prefers_a_live_current_run_over_a_longer_best_run() {
        // A has a huge best but 0 current; B is a live current run — a current run always wins.
        let picked = RecapBuilder.pickWeekStreak([
            weekStreak("A", current: 0, best: 12),
            weekStreak("B", current: 3, best: 3),
        ])
        #expect(picked?.label == "B")
        #expect(picked?.current == 3)
    }

    @Test func among_current_runs_picks_the_longest_then_the_higher_best() {
        let picked = RecapBuilder.pickWeekStreak([
            weekStreak("A", current: 2, best: 9),
            weekStreak("B", current: 3, best: 3),
            weekStreak("C", current: 3, best: 8),
        ])
        // B and C tie on current 3; C's higher best breaks it.
        #expect(picked?.label == "C")
    }

    @Test func the_one_period_floor_is_respected_a_current_of_one_never_surfaces() {
        // current 1 < minToSurface and best 1 < the floor too → nothing to show.
        let picked = RecapBuilder.pickWeekStreak([
            weekStreak("A", current: 1, best: 1),
            weekStreak("B", current: 0, best: 1),
        ])
        #expect(picked == nil)
    }

    @Test func falls_back_to_the_strongest_best_run_when_no_current_run_qualifies() {
        let picked = RecapBuilder.pickWeekStreak([
            weekStreak("A", current: 0, best: 6),
            weekStreak("B", current: 1, best: 4),
        ])
        #expect(picked?.label == "A")
        #expect(picked?.current == 0) // rendered as the best-run fallback
        #expect(picked?.best == 6)
    }

    @Test func returns_nil_when_the_list_is_empty() {
        #expect(RecapBuilder.pickWeekStreak([]) == nil)
    }
}
