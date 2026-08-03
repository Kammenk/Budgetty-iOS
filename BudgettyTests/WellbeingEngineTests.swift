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
}
