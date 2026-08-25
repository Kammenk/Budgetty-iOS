//
//  StreakEngineTests.swift
//  BudgettyTests
//
//  Pins the §2 outcome-streak contract — the Swift port of Android's `StreakEngineTest`, case for case:
//  per-scope (not all-or-nothing) streaks, closed periods only with a separate live-on-track signal,
//  strict reset on a miss with an always-computed best inside the `StreakEngine.maxStreak` window, and —
//  critically — a period with no receipts at all treated as "no data" rather than conflated with a
//  budgeted scope that simply spent nothing that period.
//

import Testing
import Foundation
@testable import Budgetty

struct StreakEngineTests {

    private func txn(_ period: Int, _ category: String, _ amount: String) -> StreakTxn {
        StreakTxn(periodIndex: period, category: category, amount: Decimal(string: amount)!)
    }

    private func budgetInput(txns: [StreakTxn],
                             categoryBudgets: [String: String] = [:],
                             monthlyBudget: String? = nil,
                             monthlyAdjustment: [Int: String] = [:],
                             live: LiveBudgetPeriod? = nil) -> BudgetStreakInput {
        BudgetStreakInput(
            transactions: txns,
            categoryBudgets: categoryBudgets.mapValues { Decimal(string: $0)! },
            monthlyBudget: monthlyBudget.map { Decimal(string: $0)! },
            kind: .budgetMonth,
            monthlyAdjustmentByPeriod: monthlyAdjustment.mapValues { Decimal(string: $0)! },
            live: live)
    }

    private func onlyStreak(_ input: BudgetStreakInput) -> Streak {
        let streaks = StreakEngine.budgetStreaks(input)
        #expect(streaks.count == 1)
        return streaks[0]
    }

    // ── Consecutive periods ─────────────────────────────────────────────────────────

    @Test func consecutiveClosedPeriodsUnderBudgetCountUp() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80"), txn(1, "Groceries", "90"), txn(2, "Groceries", "70")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(s.kind == .budgetMonth)
        #expect(s.label == "Groceries")
        #expect(s.current == 3)
        #expect(s.best == 3)
        #expect(s.periodsChecked == 3)
    }

    @Test func spendExactlyAtBudgetIsMet() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "100"), txn(1, "Groceries", "100")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == 2)
    }

    // ── Strict reset + current==0 while best>0 ──────────────────────────────────────

    @Test func aMissInTheMostRecentClosedPeriodResetsCurrentToZeroButBestSurvives() {
        let s = onlyStreak(budgetInput(
            // period 0 over budget; the two before it were clean.
            txns: [txn(0, "Groceries", "120"), txn(1, "Groceries", "80"), txn(2, "Groceries", "70")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == 0)
        #expect(s.best == 2)
        #expect(s.periodsChecked == 3)
    }

    @Test func aMidRunMissResetsCurrentButBestIsTheLongerEarlierRun() {
        let s = onlyStreak(budgetInput(
            txns: [
                txn(0, "Groceries", "80"),  // met
                txn(1, "Groceries", "90"),  // met
                txn(2, "Groceries", "150"), // miss
                txn(3, "Groceries", "70"),  // met
                txn(4, "Groceries", "60"),  // met
                txn(5, "Groceries", "50"),  // met
            ],
            categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == 2)
        #expect(s.best == 3)
    }

    // ── best within the 24-period window ────────────────────────────────────────────

    @Test func bestIsComputedWithinTheMaxStreakWindowAndIgnoresPeriodsBeyondIt() {
        var txns: [StreakTxn] = []
        for i in 0...5 { txns.append(txn(i, "Groceries", "80")) }  // 6 met
        txns.append(txn(6, "Groceries", "150"))                    // miss
        for i in 7...40 { txns.append(txn(i, "Groceries", "80")) } // met, 24..40 fall outside the window
        let s = onlyStreak(budgetInput(txns: txns, categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == 6)
        #expect(s.best == 17) // periods 7..23 only — 24..40 are outside maxStreak
        #expect(s.periodsChecked == StreakEngine.maxStreak)
    }

    @Test func currentAndBestAreBoundedByMaxStreak() {
        let txns = (0...29).map { txn($0, "Groceries", "80") } // 30 consecutive met periods
        let s = onlyStreak(budgetInput(txns: txns, categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == StreakEngine.maxStreak)
        #expect(s.best == StreakEngine.maxStreak)
        #expect(s.periodsChecked == StreakEngine.maxStreak)
    }

    // ── liveOnTrack — the open period, never counted in current ──────────────────────

    @Test func liveOnTrackExtendsNothingIntoCurrent() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80"), txn(1, "Groceries", "90")],
            categoryBudgets: ["Groceries": "100"],
            live: LiveBudgetPeriod(transactions: [txn(0, "Groceries", "40")])))
        #expect(s.current == 2) // NOT 3 — the open period is never counted
        #expect(s.liveOnTrack)
    }

    @Test func liveOverBudgetIsNotOnTrack() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80")],
            categoryBudgets: ["Groceries": "100"],
            live: LiveBudgetPeriod(transactions: [txn(0, "Groceries", "150")])))
        #expect(s.current == 1)
        #expect(!s.liveOnTrack)
    }

    @Test func liveWithNoSpendYetIsOnTrack() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80")],
            categoryBudgets: ["Groceries": "100"],
            live: LiveBudgetPeriod(transactions: [])))
        #expect(s.liveOnTrack)
    }

    @Test func noLivePeriodReadsAsNotOnTrack() {
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(!s.liveOnTrack)
    }

    // ── No-budget scope ─────────────────────────────────────────────────────────────

    @Test func noBudgetAtAllProducesNoStreaks() {
        let streaks = StreakEngine.budgetStreaks(budgetInput(txns: [txn(0, "Groceries", "80")]))
        #expect(streaks.isEmpty)
    }

    @Test func aCategoryWithoutABudgetGetsNoStreakOfItsOwn() {
        let streaks = StreakEngine.budgetStreaks(budgetInput(
            txns: [txn(0, "Groceries", "80"), txn(0, "Dining", "40")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(streaks.map(\.label) == ["Groceries"])
    }

    // ── Empty period vs zero-spend-with-data must NOT be conflated ───────────────────

    @Test func aClosedPeriodWithNoReceiptsAtAllBreaksTheStreak() {
        let s = onlyStreak(budgetInput(
            // period 1 has NO transactions anywhere → no data → breaks the run.
            txns: [txn(0, "Groceries", "80"), txn(2, "Groceries", "70")],
            categoryBudgets: ["Groceries": "100"]))
        #expect(s.current == 1)
    }

    @Test func aBudgetedScopeThatSimplySpentNothingInAPeriodWithDataIsMet() {
        // period 0 has receipts (Dining) but Groceries spent nothing → Groceries is MET, not "no data".
        // period 2 has NO receipts at all → that IS "no data" and breaks the run. The two are distinct.
        let s = StreakEngine.budgetStreaks(budgetInput(
            txns: [
                txn(0, "Dining", "50"),     // data present in period 0; Groceries spend = 0
                txn(1, "Groceries", "80"),
                // period 2 intentionally empty (no data)
                txn(3, "Groceries", "70"),
            ],
            categoryBudgets: ["Groceries": "100"])).first { $0.label == "Groceries" }!
        #expect(s.current == 2) // periods 0 (zero-spend, met) + 1 (met); period 2 no-data breaks
        #expect(s.best == 2)
        #expect(s.periodsChecked == 3) // periods 0,1,3 have data; period 2 does not
    }

    // ── Per-scope independence ──────────────────────────────────────────────────────

    @Test func oneCategoryCleanWhileAnotherOverspendsYieldsIndependentStreaks() {
        let streaks = Dictionary(uniqueKeysWithValues: StreakEngine.budgetStreaks(budgetInput(
            txns: [
                txn(0, "Groceries", "80"), txn(0, "Dining", "70"), // Dining over (>50) in period 0
                txn(1, "Groceries", "90"), txn(1, "Dining", "40"),
                txn(2, "Groceries", "70"), txn(2, "Dining", "30"),
            ],
            categoryBudgets: ["Groceries": "100", "Dining": "50"])).map { ($0.label, $0) })

        #expect(streaks["Groceries"]?.current == 3)
        #expect(streaks["Dining"]?.current == 0)  // most recent closed period was over
        #expect(streaks["Dining"]?.best == 2)     // the two clean periods before it
    }

    @Test func categoryBudgetsTakePrecedenceOverTheMonthlyBudget() {
        // Groceries 80 is under its own 100 cap but over the tiny 50 monthly budget → the category cap wins.
        let s = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "80")],
            categoryBudgets: ["Groceries": "100"],
            monthlyBudget: "50"))
        #expect(s.label == "Groceries")
        #expect(s.current == 1)
    }

    // ── Monthly (whole-budget) scope + paid adjustment ──────────────────────────────

    @Test func monthlyScopeUsesTheWholeBudgetWhenNoCategoryBudgetsAreSet() {
        let s = onlyStreak(budgetInput(
            txns: [
                txn(0, "Groceries", "40"), txn(0, "Dining", "40"), // 80 total <= 100
                txn(1, "Groceries", "95"),
            ],
            monthlyBudget: "100"))
        #expect(s.label == "MONTHLY")
        #expect(s.current == 2)
    }

    @Test func thePaidAdjustmentCanTipTheMonthlyScopeOverBudget() {
        let withoutAdjustment = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "90"), txn(1, "Groceries", "90")],
            monthlyBudget: "100"))
        #expect(withoutAdjustment.current == 2)

        let withAdjustment = onlyStreak(budgetInput(
            txns: [txn(0, "Groceries", "90"), txn(1, "Groceries", "90")],
            monthlyBudget: "100",
            monthlyAdjustment: [0: "20"])) // 90 + 20 = 110 > 100 → period 0 misses
        #expect(withAdjustment.current == 0)
        #expect(withAdjustment.best == 1)
    }

    // ── allScopesStreak — the legacy every-scope aggregate ──────────────────────────

    @Test func allScopesStreakCountsOnlyPeriodsWhereEveryScopeStayedUnder() {
        let s = StreakEngine.allScopesStreak(budgetInput(
            txns: [
                txn(0, "Groceries", "80"), txn(0, "Dining", "70"), // Dining over → aggregate misses
                txn(1, "Groceries", "90"), txn(1, "Dining", "40"),
                txn(2, "Groceries", "70"), txn(2, "Dining", "30"),
            ],
            categoryBudgets: ["Groceries": "100", "Dining": "50"]))
        #expect(s.current == 0) // one category over in the most recent period zeroes the aggregate
        #expect(s.best == 2)
    }

    @Test func allScopesStreakCountsUpWhenEveryScopeIsUnder() {
        let s = StreakEngine.allScopesStreak(budgetInput(
            txns: [
                txn(0, "Groceries", "80"), txn(0, "Dining", "40"),
                txn(1, "Groceries", "90"), txn(1, "Dining", "45"),
                txn(2, "Groceries", "70"), txn(2, "Dining", "30"),
            ],
            categoryBudgets: ["Groceries": "100", "Dining": "50"]))
        #expect(s.current == 3)
    }

    @Test func allScopesStreakBreaksOnAPeriodWithNoData() {
        let s = StreakEngine.allScopesStreak(budgetInput(
            txns: [txn(0, "Groceries", "80"), txn(2, "Groceries", "70")],
            monthlyBudget: "100"))
        #expect(s.current == 1)
    }

    @Test func allScopesStreakIsZeroWhenThereIsNoBudget() {
        let s = StreakEngine.allScopesStreak(budgetInput(txns: [txn(0, "Groceries", "80")]))
        #expect(s.current == 0)
        #expect(s.best == 0)
        #expect(s.periodsChecked == 0)
    }

    // ── Limit streaks ───────────────────────────────────────────────────────────────

    @Test func limitStreakCountsConsecutiveClosedWindowsWithinCap() {
        let s = StreakEngine.limitStreak(LimitStreakInput(
            label: "Coke",
            cap: 2,
            closedWindows: [
                LimitWindow(count: 1, hasData: true), // met
                LimitWindow(count: 2, hasData: true), // met (at cap)
                LimitWindow(count: 3, hasData: true), // over cap → miss
                LimitWindow(count: 0, hasData: true), // met
            ]))
        #expect(s.kind == .limit)
        #expect(s.current == 2)
        #expect(s.best == 2)
        #expect(s.periodsChecked == 4)
    }

    @Test func limitWindowWithNoReceiptsIsNoDataButZeroPurchasesWithDataIsMet() {
        let s = StreakEngine.limitStreak(LimitStreakInput(
            label: "Coke",
            cap: 2,
            closedWindows: [
                LimitWindow(count: 0, hasData: true),  // bought nothing but did log receipts → met
                LimitWindow(count: 0, hasData: false), // no receipts at all → no data → breaks
                LimitWindow(count: 1, hasData: true),
            ]))
        #expect(s.current == 1)
        #expect(s.periodsChecked == 2)
    }

    @Test func limitLiveWindowWithinCapIsOnTrackAndNeverCounted() {
        let s = StreakEngine.limitStreak(LimitStreakInput(
            label: "Coke",
            cap: 2,
            closedWindows: [LimitWindow(count: 1, hasData: true), LimitWindow(count: 0, hasData: true)],
            live: LimitWindow(count: 1, hasData: true)))
        #expect(s.current == 2)
        #expect(s.liveOnTrack)
    }

    @Test func limitLiveWindowOverCapIsNotOnTrack() {
        let s = StreakEngine.limitStreak(LimitStreakInput(
            label: "Coke",
            cap: 2,
            closedWindows: [LimitWindow(count: 1, hasData: true)],
            live: LimitWindow(count: 5, hasData: true)))
        #expect(!s.liveOnTrack)
    }

    // ── Minimum bar (§2.7) ──────────────────────────────────────────────────────────

    @Test func surfacedKeepsOnlyStreaksOfAtLeastTwo() {
        let one = Streak(kind: .budgetMonth, label: "A", current: 1, best: 4, periodsChecked: 6, liveOnTrack: true)
        let two = Streak(kind: .budgetMonth, label: "B", current: 2, best: 2, periodsChecked: 2, liveOnTrack: false)
        let six = Streak(kind: .limit, label: "C", current: 6, best: 6, periodsChecked: 6, liveOnTrack: true)
        #expect(StreakEngine.surfaced([one, two, six]).map(\.label) == ["B", "C"])
    }
}
