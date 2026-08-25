import Testing
import Foundation
@testable import Budgetty

struct WellbeingEngineTests {

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    private func inputs(
        hasIncome: Bool = true,
        savingsRatePercent: Int = 18,
        income: String = "2400",
        saved: String = "432",
        netCashflow: String = "120",
        hasAnyBudget: Bool = true,
        budgetedCount: Int = 6,
        overCount: Int = 0,
        overspendTotal: String = "0",
        budgetedTotal: String = "1200",
        trendPercent: Int? = -3,
        subsSharePercent: Int? = 9,
        subsMonthly: String = "67",
        subsCount: Int = 3,
        goals: [GoalPace] = [GoalPace(name: "Vacation", reached: false, behind: false)],
        categories: [CategorySpend] = [],
        spend: String = "712",
        receiptsLogged: Int = 18,
        monthsTracked: Int = 6,
        previousScore: Int? = nil
    ) -> WellbeingInputs {
        WellbeingInputs(
            hasIncome: hasIncome, savingsRatePercent: savingsRatePercent, income: d(income),
            saved: d(saved), netCashflow: d(netCashflow), hasAnyBudget: hasAnyBudget,
            budgetedCount: budgetedCount, overCount: overCount, overspendTotal: d(overspendTotal),
            budgetedTotal: d(budgetedTotal), trendPercent: trendPercent, subsSharePercent: subsSharePercent,
            subsMonthly: d(subsMonthly), subsCount: subsCount, goals: goals, categories: categories,
            spend: d(spend), receiptsLogged: receiptsLogged, monthsTracked: monthsTracked, previousScore: previousScore
        )
    }

    // MARK: Bands & tiers

    @Test func bandsMapAtDocumentedThresholds() {
        #expect(WellbeingEngine.band(0) == .needsWork)
        #expect(WellbeingEngine.band(39) == .needsWork)
        #expect(WellbeingEngine.band(40) == .gettingThere)
        #expect(WellbeingEngine.band(59) == .gettingThere)
        #expect(WellbeingEngine.band(60) == .healthy)
        #expect(WellbeingEngine.band(79) == .healthy)
        #expect(WellbeingEngine.band(80) == .thriving)
        #expect(WellbeingEngine.band(100) == .thriving)
    }

    @Test func tiersMapAt70And40() {
        #expect(WellbeingEngine.tier(70) == .good)
        #expect(WellbeingEngine.tier(69) == .warn)
        #expect(WellbeingEngine.tier(40) == .warn)
        #expect(WellbeingEngine.tier(39) == .bad)
    }

    // MARK: Component sub-scores

    @Test func savingsScoreFullAt20ZeroAtMinus10AndMonotonic() {
        #expect(WellbeingEngine.savingsScore(ratePercent: 20) == 100)
        #expect(WellbeingEngine.savingsScore(ratePercent: 30) == 100)
        #expect(WellbeingEngine.savingsScore(ratePercent: -10) == 0)
        #expect(WellbeingEngine.savingsScore(ratePercent: -50) == 0)
        #expect(WellbeingEngine.savingsScore(ratePercent: 5) == 50)
        #expect(WellbeingEngine.savingsScore(ratePercent: 2) < WellbeingEngine.savingsScore(ratePercent: 18))
    }

    @Test func subscriptionsScoreFullUnder5PercentThenFalls() {
        #expect(WellbeingEngine.subscriptionsScore(sharePercent: 0) == 100)
        #expect(WellbeingEngine.subscriptionsScore(sharePercent: 5) == 100)
        #expect(WellbeingEngine.subscriptionsScore(sharePercent: 9) == 56)
        #expect(WellbeingEngine.subscriptionsScore(sharePercent: 9) > WellbeingEngine.subscriptionsScore(sharePercent: 15))
    }

    @Test func trendScoreFullWhenFlatOrDownAndPenalisesRises() {
        #expect(WellbeingEngine.trendScore(percentVsAverage: -5) == 100)
        #expect(WellbeingEngine.trendScore(percentVsAverage: 0) == 100)
        #expect(WellbeingEngine.trendScore(percentVsAverage: 22) == 34)
        #expect(WellbeingEngine.trendScore(percentVsAverage: 40) == 0)
    }

    @Test func budgetScoreFullWithNoOverspend() {
        #expect(WellbeingEngine.budgetScore(budgetedCount: 6, overCount: 0, overspend: d("0"), budgeted: d("1200")) == 100)
        let partial = WellbeingEngine.budgetScore(budgetedCount: 6, overCount: 3, overspend: d("214"), budgeted: d("1200"))
        #expect(partial < 100)
        #expect(partial > 0)
    }

    @Test func goalsScoreNilWhenNoneAndBlendsOnPaceWithBehind() {
        #expect(WellbeingEngine.goalsScore([]) == nil)
        #expect(WellbeingEngine.goalsScore([GoalPace(name: "A", reached: false, behind: false)]) == 100)
        #expect(WellbeingEngine.goalsScore([GoalPace(name: "A", reached: false, behind: true)]) == 40)
        #expect(WellbeingEngine.goalsScore([
            GoalPace(name: "A", reached: false, behind: false),
            GoalPace(name: "B", reached: false, behind: true),
        ]) == 70)
    }

    // MARK: Aggregate + renormalisation

    @Test func aggregateRenormalisesOverAvailableComponents() {
        let comps = [
            WellbeingComponent(key: .savings, weight: 25, score: 80),
            WellbeingComponent(key: .budget, weight: 25, score: 60),
            WellbeingComponent(key: .trend, weight: 15, score: 100),
            WellbeingComponent(key: .subscriptions, weight: 15, score: 40),
            WellbeingComponent(key: .goals, weight: 20, score: nil),
        ]
        // (80*25 + 60*25 + 100*15 + 40*15) / (25+25+15+15) = 5600/80 = 70
        #expect(WellbeingEngine.aggregate(comps) == 70)
    }

    @Test func aggregateNilWhenNoComponentHasData() {
        let comps = WellbeingComponentKey.allCases.map { WellbeingComponent(key: $0, weight: 20, score: nil) }
        #expect(WellbeingEngine.aggregate(comps) == nil)
    }

    @Test func scoreIsFirstRunUntilEnoughReceipts() {
        #expect(WellbeingEngine.score(inputs(receiptsLogged: 4)).hasScore == false)
        #expect(WellbeingEngine.score(inputs(receiptsLogged: 5)).hasScore == true)
    }

    @Test func scoreReportsTrendDeltaAgainstPrevious() {
        let s = WellbeingEngine.score(inputs(previousScore: 68))
        #expect(s.score != nil)
        #expect(s.trendDeltaVsPrevious == (s.score! - 68))
    }

    @Test func excludedGoalIsMarkedNotCounted() {
        let s = WellbeingEngine.score(inputs(goals: []))
        let goals = s.components.first { $0.key == .goals }
        #expect(goals?.score == nil)
        #expect(s.hasExcludedComponent == true)
    }

    // MARK: Tip ranking

    @Test func rankOrdersBySeverityAndAlwaysKeepsOneWin() {
        let tips = [
            WellbeingTip(type: .savingsWin, id: "w", tone: .win),
            WellbeingTip(type: .categorySpike, id: "c1", tone: .caution),
            WellbeingTip(type: .categorySpike, id: "c2", tone: .caution),
            WellbeingTip(type: .negativeCashflow, id: "a", tone: .alert),
            WellbeingTip(type: .noGoal, id: "o", tone: .opportunity),
        ]
        let ranked = WellbeingEngine.rank(tips, cap: 3)
        #expect(ranked.count == 3)
        #expect(ranked.first?.tone == .alert)
        #expect(ranked.filter { $0.tone == .win }.count == 1)
    }

    @Test func rankWithoutWinsJustTakesTopSeverity() {
        let tips = [
            WellbeingTip(type: .overBudget, id: "a1", tone: .alert),
            WellbeingTip(type: .negativeCashflow, id: "a2", tone: .alert),
            WellbeingTip(type: .noGoal, id: "o", tone: .opportunity),
        ]
        let ranked = WellbeingEngine.rank(tips, cap: 2)
        #expect(ranked.count == 2)
        #expect(ranked.allSatisfy { $0.tone == .alert })
    }

    // MARK: End-to-end tips

    @Test func healthyInputsYieldAWinAndNoAlert() {
        let tips = WellbeingEngine.tips(inputs(
            netCashflow: "300", overCount: 0, overspendTotal: "0",
            categories: [CategorySpend(category: "Dining", current: d("182"), average: d("136"), monthlyAverage: d("150"), hasBudget: false)]
        ))
        #expect(!tips.contains { $0.tone == .alert })
        #expect(tips.contains { $0.tone == .win })
        #expect(tips.contains { $0.type == .categorySpike })
    }

    @Test func overspentNegativeCashflowAndNoGoalProduceAlertsAndOpportunity() {
        let tips = WellbeingEngine.tips(inputs(
            savingsRatePercent: 2, saved: "48", netCashflow: "-120",
            overCount: 3, overspendTotal: "214", goals: []
        ))
        #expect(tips.contains { $0.type == .negativeCashflow && $0.tone == .alert })
        #expect(tips.contains { $0.type == .overBudget && $0.tone == .alert })
        #expect(tips.contains { $0.type == .noGoal && $0.tone == .opportunity })
        #expect(tips.first?.tone == .alert)
    }

    @Test func weeklyTipsFlagPaceLeakAndAWin() {
        let week = WeeklyInputs(
            spent: d("210"), weeklyBudget: d("300"), daysElapsed: 5, daysInWeek: 7, deltaPercentVsLastWeek: -12,
            pacedCategory: PacedCategory(name: "Dining", percentUsed: 78, remaining: d("22")),
            leakCategory: LeakCategory(name: "Coffee", count: 9, total: d("26")),
            underPaceCategory: UnderPaceCategory(name: "Groceries", under: d("18"))
        )
        let tips = WellbeingEngine.weeklyTips(week)
        #expect(tips.contains { $0.type == .budgetPace })
        #expect(tips.contains { $0.type == .underPaceWin && $0.tone == .win })
        #expect(tips.count <= WellbeingEngine.weeklyTipCap)
    }

    // MARK: Score floor — Subscriptions must not score 100 from the absence of data

    @Test func newUserWithNoSignalAndNoSubscriptionsScoresNil() {
        // A fresh account: 5+ receipts but no income/budget/goals/trend and no subscriptions. Before
        // the fix, Subscriptions scored a perfect 100 from a 0% share and was the only scored
        // component → 100/Thriving. Now every component is nil → no total (first-run state).
        let s = WellbeingEngine.score(inputs(
            hasIncome: false, hasAnyBudget: false, trendPercent: nil,
            subsSharePercent: 0, subsCount: 0, goals: [],
            receiptsLogged: WellbeingEngine.minReceiptsToScore, monthsTracked: 1
        ))
        #expect(s.score == nil)
        #expect(s.band == nil)
    }

    @Test func zeroSubscriptionsOnlyScoresWithEnoughHistory() {
        #expect(WellbeingEngine.subscriptionsComponentScore(
            inputs(subsSharePercent: 0, subsCount: 0, monthsTracked: 1)) == nil)
        // After minMonthsForZeroSubs months, a real 0% share is a genuine win (full marks).
        #expect(WellbeingEngine.subscriptionsComponentScore(
            inputs(subsSharePercent: 0, subsCount: 0, monthsTracked: 2)) == 100)
    }

    @Test func realSignalStillScoresInTheFirstMonth() {
        // A user who set up income has a genuine savings component — that should still score.
        let s = WellbeingEngine.score(inputs(
            hasIncome: true, savingsRatePercent: 20, hasAnyBudget: false, trendPercent: nil,
            subsSharePercent: 0, subsCount: 0, goals: [], monthsTracked: 1
        ))
        #expect(s.score != nil)
    }

    @Test func actualSubscriptionsScoreRegardlessOfHistory() {
        // subsCount > 0 means there IS data to score, from month one: 100 - (10-5)*11 = 45.
        #expect(WellbeingEngine.subscriptionsComponentScore(
            inputs(subsSharePercent: 10, subsCount: 2, monthsTracked: 1)) == 45)
    }

    // MARK: §3.5 Band-up nudge

    @Test func bandUpFiresOnlyWithinThreePointsBelowABoundary() {
        #expect(WellbeingEngine.bandUp(57) == BandUp(pointsAway: 3, nextBand: .healthy))
        #expect(WellbeingEngine.bandUp(59) == BandUp(pointsAway: 1, nextBand: .healthy))
        #expect(WellbeingEngine.bandUp(38) == BandUp(pointsAway: 2, nextBand: .gettingThere))
        #expect(WellbeingEngine.bandUp(78) == BandUp(pointsAway: 2, nextBand: .thriving))
        // Suppressed away from a boundary (a healthy 72), exactly on one (40), and at the top (80).
        #expect(WellbeingEngine.bandUp(72) == nil)
        #expect(WellbeingEngine.bandUp(40) == nil)
        #expect(WellbeingEngine.bandUp(80) == nil)
    }

    // MARK: §3.3 Projection math per tip type

    /// Inputs where BUDGET is the only scored component, so the aggregate delta equals the budget-score
    /// delta — lets each projection be pinned to a concrete number.
    private func budgetOnly(overCount: Int, overspend: String, budgetedCount: Int, budgeted: String) -> WellbeingInputs {
        inputs(hasIncome: false, hasAnyBudget: true, budgetedCount: budgetedCount, overCount: overCount,
               overspendTotal: overspend, budgetedTotal: budgeted, trendPercent: nil,
               subsSharePercent: nil, subsCount: 0, goals: [], monthsTracked: 1)
    }

    @Test func overBudgetProjectionRemovesOneOverAndItsAverageOverspend() {
        // base budgetScore(4,2,200,1000)=38 → projected budgetScore(4,1,100,1000)=69 → +31.
        let i = budgetOnly(overCount: 2, overspend: "200", budgetedCount: 4, budgeted: "1000")
        let tip = WellbeingTip(type: .overBudget, id: "over_budget", tone: .alert, amount: d("200"), count: 2)
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(i)) == 38)
        #expect(WellbeingEngine.projectedGain(i, tip) == 31)
        #expect(WellbeingEngine.showsProjectedGain(31))
    }

    @Test func missingBudgetProjectionAddsAWithinPlanScope() {
        // base budgetScore(2,1,100,400)=30 → projected budgetScore(3,1,100,600)=53 → +23.
        let i = budgetOnly(overCount: 1, overspend: "100", budgetedCount: 2, budgeted: "400")
        let tip = WellbeingTip(type: .missingBudget, id: "m", tone: .opportunity, amount: d("200"), label: "Dining")
        #expect(WellbeingEngine.projectedGain(i, tip) == 23)
    }

    @Test func subscriptionCostProjectionDropsTheShareProportionally() {
        // Subscriptions the only scored component. share 9 → cancel 1 of 3 → newShare round(9*2/3)=6.
        // subscriptionsScore(9)=56 → subscriptionsScore(6)=89 → +33.
        let i = inputs(hasIncome: false, hasAnyBudget: false, trendPercent: nil,
                       subsSharePercent: 9, subsMonthly: "67", subsCount: 3, goals: [], monthsTracked: 6)
        let tip = WellbeingTip(type: .subscriptionCost, id: "s", tone: .caution, amount: d("67"), percent: 9, count: 3)
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(i)) == 56)
        #expect(WellbeingEngine.projectedGain(i, tip) == 33)
    }

    @Test func goalOffTrackProjectionBringsThatGoalOnPace() {
        // Goals the only scored component: one behind goal 40 → 100 → +60.
        let i = inputs(hasIncome: false, hasAnyBudget: false, trendPercent: nil,
                       subsSharePercent: nil, subsCount: 0,
                       goals: [GoalPace(name: "Vacation", reached: false, behind: true)], monthsTracked: 1)
        let tip = WellbeingTip(type: .goalOffTrack, id: "g", tone: .opportunity, label: "Vacation")
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(i)) == 40)
        #expect(WellbeingEngine.projectedGain(i, tip) == 60)
    }

    @Test func winToneTipsAndUnactionableTipsHaveNoProjection() {
        let i = inputs()
        #expect(WellbeingEngine.projectedGain(i, WellbeingTip(type: .savingsWin, id: "w", tone: .win)) == nil)
        #expect(WellbeingEngine.projectedGain(i, WellbeingTip(type: .categorySpike, id: "c", tone: .caution)) == nil)
        #expect(WellbeingEngine.projectedGain(i, WellbeingTip(type: .negativeCashflow, id: "n", tone: .alert)) == nil)
    }

    // MARK: §3.3 The renormalisation-negative guard (the pinned case)

    @Test func noGoalProjectionIsNonPositiveWhenTheBaseIsAlreadyMaxed_andIsSuppressed() {
        // The renormalisation trap: goals ENTERS the mean at 100. When the only other scored component is
        // already 100 (savings at a 25% rate), the maxed base can't move — the modelled delta is 0, NOT a
        // gain. showsProjectedGain must drop it so no "+0" pill is ever rendered. Pins the ≤ 0 case.
        let maxed = inputs(hasIncome: true, savingsRatePercent: 25, hasAnyBudget: false, trendPercent: nil,
                           subsSharePercent: nil, subsCount: 0, goals: [], monthsTracked: 1)
        let noGoal = WellbeingTip(type: .noGoal, id: "no_goal", tone: .opportunity)
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(maxed)) == 100)
        #expect(WellbeingEngine.projectedGain(maxed, noGoal) == 0)
        #expect(WellbeingEngine.showsProjectedGain(WellbeingEngine.projectedGain(maxed, noGoal)) == false)

        // The same guard drops any noise or a hypothetical negative — never a "+1", "+0" or "−N".
        #expect(WellbeingEngine.showsProjectedGain(0) == false)
        #expect(WellbeingEngine.showsProjectedGain(1) == false)
        #expect(WellbeingEngine.showsProjectedGain(-3) == false)
        #expect(WellbeingEngine.showsProjectedGain(2))
        #expect(WellbeingEngine.showsProjectedGain(nil) == false)
    }

    @Test func noGoalProjectionIsAGenuineGainWhenTheBaseHasRoom() {
        // Same tip, base 50 (savings at a 5% rate) → goals enters at 100 → aggregate 72 → +22, shown.
        let room = inputs(hasIncome: true, savingsRatePercent: 5, hasAnyBudget: false, trendPercent: nil,
                          subsSharePercent: nil, subsCount: 0, goals: [], monthsTracked: 1)
        let noGoal = WellbeingTip(type: .noGoal, id: "no_goal", tone: .opportunity)
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(room)) == 50)
        #expect(WellbeingEngine.projectedGain(room, noGoal) == 22)
        #expect(WellbeingEngine.showsProjectedGain(22))
    }

    @Test func projectionIsNilWhenThereIsNoTotalToMoveAgainst() {
        // No scored component at all (first-run-ish): base aggregate is nil, so there's no delta to model.
        let unscored = inputs(hasIncome: false, hasAnyBudget: false, trendPercent: nil,
                              subsSharePercent: nil, subsCount: 0, goals: [], monthsTracked: 1)
        #expect(WellbeingEngine.aggregate(WellbeingEngine.components(unscored)) == nil)
        #expect(WellbeingEngine.projectedGain(unscored, WellbeingTip(type: .noGoal, id: "no_goal", tone: .opportunity)) == nil)
    }

    // MARK: §3.4 Rank by projected gain (secondary key)

    @Test func rankSecondarySortsByProjectedGainWithinATone() {
        let tips = [
            WellbeingTip(type: .missingBudget, id: "m", tone: .opportunity, projectedGain: 1),
            WellbeingTip(type: .goalOffTrack, id: "g", tone: .opportunity, projectedGain: 6),
        ]
        // Same tone → the bigger modelled gain leads (§3.4).
        #expect(WellbeingEngine.rank(tips, cap: 5).map(\.id) == ["g", "m"])
    }

    @Test func rankStillPutsToneSeverityBeforeGain() {
        let tips = [
            WellbeingTip(type: .missingBudget, id: "m", tone: .opportunity, projectedGain: 6),
            WellbeingTip(type: .overBudget, id: "a", tone: .alert, projectedGain: 0),
        ]
        // A high-gain opportunity never outranks an alert — gain is only the SECONDARY key.
        #expect(WellbeingEngine.rank(tips, cap: 5).first?.id == "a")
    }

    @Test func tipsAttachProjectedGainOnceScored() {
        // An over-budget month that IS scored: the OVER_BUDGET tip carries a positive modelled gain.
        let i = inputs(budgetedCount: 6, overCount: 3, overspendTotal: "214", budgetedTotal: "1200",
                       receiptsLogged: 18, monthsTracked: 6)
        let over = WellbeingEngine.tips(i).first { $0.type == .overBudget }
        #expect(over?.projectedGain != nil)
        #expect((over?.projectedGain ?? 0) > 0)
    }

    // MARK: §2.6 Budget-streak evidence surfacing

    @Test func budgetStreakEvidenceSurfacesLongestFirstCappedAndAboveTheFloor() {
        let streaks = [
            Streak(kind: .budgetMonth, label: "Groceries", current: 4, best: 5, periodsChecked: 6, liveOnTrack: true),
            Streak(kind: .budgetMonth, label: "Household", current: 2, best: 3, periodsChecked: 6, liveOnTrack: true),
            Streak(kind: .budgetMonth, label: "Transport", current: 1, best: 2, periodsChecked: 6, liveOnTrack: false),
            Streak(kind: .budgetMonth, label: "Dining", current: 6, best: 6, periodsChecked: 6, liveOnTrack: true),
        ]
        let ev = WellbeingEngine.budgetStreakEvidence(streaks)
        // current < 2 dropped (Transport), longest current first, capped at maxStreakEvidence (2).
        #expect(ev.count == WellbeingEngine.maxStreakEvidence)
        #expect(ev.map(\.label) == ["Dining", "Groceries"])
    }

    @Test func budgetStreakEvidenceIsEmptyWhenNothingClearsTheFloor() {
        let streaks = [Streak(kind: .budgetMonth, label: "A", current: 1, best: 1, periodsChecked: 3, liveOnTrack: false)]
        #expect(WellbeingEngine.budgetStreakEvidence(streaks).isEmpty)
    }
}
