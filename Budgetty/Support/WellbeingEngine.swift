import Foundation

// MARK: - Model
//
// Pure, on-device scoring + tips for the Wellbeing screen — the Swift port of the Android
// `WellbeingEngine`. No SwiftUI, no SwiftData; every value comes from metrics the app already
// derives (savings rate, budgets, goals, spending trend, subscriptions), so it unit-tests in
// isolation (mirrors `SubscriptionDetector` / `SavingsMath`). Money is `Decimal` throughout.

/// Overall grade band; drives the ring/arc colour and the band word.
enum WellbeingBand { case needsWork, gettingThere, healthy, thriving }

/// Bar/label colour tier for a single component sub-score.
enum WellbeingTier { case good, warn, bad }

/// The five areas the score is built from. Order here is presentation order on the screen.
enum WellbeingComponentKey: CaseIterable { case savings, budget, trend, subscriptions, goals }

enum TipTone { case alert, caution, opportunity, win }

enum TipType {
    case negativeCashflow, overBudget, categorySpike, subscriptionCost, missingBudget
    case noGoal, goalOffTrack, savingsWin, categoryImproved
    case budgetPace, smallPurchaseLeak, underPaceWin
}

/// One goal's pace, distilled from `SavingsMath`.
struct GoalPace {
    let name: String
    let reached: Bool
    let behind: Bool
    /// Whole months the goal is projected to miss its target date by, when known.
    var monthsLate: Int? = nil
}

/// Per-category spend this period plus context used by the tip detectors.
struct CategorySpend {
    let category: String
    /// Spend in the current period.
    let current: Decimal
    /// The category's trailing per-period average (0 if no history).
    let average: Decimal
    /// The category's trailing monthly average, for the "no budget on ~€X/mo" detector.
    let monthlyAverage: Decimal
    let hasBudget: Bool
    /// Number of transactions in the period (for small-purchase-leak detection).
    var count: Int = 0
}

struct PacedCategory { let name: String; let percentUsed: Int; let remaining: Decimal }
struct LeakCategory { let name: String; let count: Int; let total: Decimal }
struct UnderPaceCategory { let name: String; let under: Decimal }

/// Everything the weekly check-in tips need.
struct WeeklyInputs {
    let spent: Decimal
    let weeklyBudget: Decimal?
    let daysElapsed: Int
    let daysInWeek: Int
    let deltaPercentVsLastWeek: Int?
    var pacedCategory: PacedCategory? = nil
    var leakCategory: LeakCategory? = nil
    var underPaceCategory: UnderPaceCategory? = nil
}

/// The fully-derived inputs to `WellbeingEngine`. Built by `WellbeingScore.compute` from SwiftData;
/// kept pure so the whole score + tip pipeline unit-tests with plain values.
struct WellbeingInputs {
    // Savings
    let hasIncome: Bool
    let savingsRatePercent: Int
    let income: Decimal
    let saved: Decimal
    let netCashflow: Decimal
    // Budgets
    let hasAnyBudget: Bool
    let budgetedCount: Int
    let overCount: Int
    let overspendTotal: Decimal
    let budgetedTotal: Decimal
    // Trend (nil = not enough history)
    let trendPercent: Int?
    // Subscriptions (share nil = not enough history)
    let subsSharePercent: Int?
    let subsMonthly: Decimal
    let subsCount: Int
    // Goals
    let goals: [GoalPace]
    // Category detail for tip detectors
    let categories: [CategorySpend]
    let spend: Decimal
    // Context
    let receiptsLogged: Int
    let monthsTracked: Int
    /// Last month's total score, when computable, so the screen can show a trend chip.
    var previousScore: Int? = nil
}

/// A single component's sub-score. `score == nil` means "not counted" (no data → excluded, renormalised).
struct WellbeingComponent { let key: WellbeingComponentKey; let weight: Int; let score: Int? }

/// The scored result. `score`/`band` are nil when there isn't enough data yet (first-run state).
struct WellbeingScore {
    let score: Int?
    let band: WellbeingBand?
    let components: [WellbeingComponent]
    let trendDeltaVsPrevious: Int?
    var hasScore: Bool { score != nil }
    var hasExcludedComponent: Bool { components.contains { $0.score == nil } }
}

/// One ranked tip. `type` selects the localized copy in the UI, `id` is the stable dismissal key,
/// and the loosely-typed payload carries the real figures the copy quotes.
struct WellbeingTip: Identifiable, Equatable {
    let type: TipType
    let id: String
    let tone: TipTone
    var amount: Decimal? = nil
    var amount2: Decimal? = nil
    var percent: Int? = nil
    var count: Int? = nil
    var label: String? = nil
}

private extension Decimal {
    var dbl: Double { (self as NSDecimalNumber).doubleValue }
}

// MARK: - Engine

enum WellbeingEngine {

    // Weights (from the approved design). Renormalised across whichever components have data.
    static let wSavings = 25
    static let wBudget = 25
    static let wGoals = 20
    static let wTrend = 15
    static let wSubscriptions = 15

    /// Below this many logged receipts we can't score meaningfully → first-run state.
    static let minReceiptsToScore = 5

    /// A subscription share of 0% only counts as a genuine "no subscriptions" win once there's at
    /// least this many months of history. Before that, a brand-new user simply hasn't accrued
    /// subscription data — scoring the absence as a perfect 100 would hand them a bogus top score,
    /// since it can be their only scored component. Android parity: `MIN_MONTHS_FOR_ZERO_SUBS`.
    static let minMonthsForZeroSubs = 2

    static let monthlyTipCap = 5
    static let weeklyTipCap = 3

    static func band(_ score: Int) -> WellbeingBand {
        if score >= 80 { return .thriving }
        if score >= 60 { return .healthy }
        if score >= 40 { return .gettingThere }
        return .needsWork
    }

    /// Bar/label tier for a single component sub-score: ≥70 good, 40–69 careful, <40 over.
    static func tier(_ score: Int) -> WellbeingTier {
        if score >= 70 { return .good }
        if score >= 40 { return .warn }
        return .bad
    }

    private static func clampScore(_ v: Double) -> Int { min(100, max(0, Int(v.rounded()))) }

    // ── Component sub-scores (0–100, higher = better) ─────────────────────────────

    /// Full marks at ≥20% kept; 0 at ≤−10%; linear between.
    static func savingsScore(ratePercent: Int) -> Int {
        clampScore(Double(min(30, max(0, ratePercent + 10))) / 30.0 * 100.0)
    }

    /// Blends how many budgeted scopes stayed within plan (60%) with the size of the overspend
    /// relative to what was budgeted (40%). Full marks when nothing is over.
    static func budgetScore(budgetedCount: Int, overCount: Int, overspend: Decimal, budgeted: Decimal) -> Int {
        if budgetedCount <= 0 || budgeted <= 0 { return 100 }
        let within = Double(max(0, budgetedCount - overCount)) / Double(budgetedCount)
        let overFrac = min(1.0, overspend.dbl / budgeted.dbl)
        return clampScore(within * 60.0 + (1.0 - min(overFrac * 4.0, 1.0)) * 40.0)
    }

    /// Average of per-goal marks: on-pace (or reached) = 100, behind = 40. Nil when no active goal.
    static func goalsScore(_ goals: [GoalPace]) -> Int? {
        if goals.isEmpty { return nil }
        let each = goals.map { ($0.reached || !$0.behind) ? 100 : 40 }
        return clampScore(Double(each.reduce(0, +)) / Double(each.count))
    }

    /// Flat or falling spend scores full marks; each 1% above the trailing average costs 3 points.
    static func trendScore(percentVsAverage: Int) -> Int {
        clampScore(100.0 - Double(max(0, percentVsAverage)) * 3.0)
    }

    /// Under 5% of spend on subscriptions scores full marks; each 1% above costs 11 points.
    static func subscriptionsScore(sharePercent: Int) -> Int {
        clampScore(100.0 - Double(max(0, sharePercent - 5)) * 11.0)
    }

    /// The subscriptions component's sub-score, or nil when there isn't enough signal to score it — a
    /// 0% share only counts once there are at least `minMonthsForZeroSubs` months of history. This is
    /// what stops a brand-new user (no income/budget/goals/trend yet, no subscriptions) from scoring a
    /// bogus 100 off their only scored component. Android parity: `subscriptionsComponentScore`.
    static func subscriptionsComponentScore(_ i: WellbeingInputs) -> Int? {
        if i.subsCount == 0 && i.monthsTracked < minMonthsForZeroSubs { return nil }
        return i.subsSharePercent.map { subscriptionsScore(sharePercent: $0) }
    }

    // ── Aggregate ─────────────────────────────────────────────────────────────────

    /// Weighted, renormalising mean over the components that have a score. Nil if none do.
    static func aggregate(_ components: [WellbeingComponent]) -> Int? {
        let scored = components.compactMap { c in c.score.map { (score: $0, weight: c.weight) } }
        let totalWeight = scored.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        let sum = scored.reduce(0.0) { $0 + Double($1.score * $1.weight) }
        return min(100, max(0, Int((sum / Double(totalWeight)).rounded())))
    }

    /// Builds the five components (order matches the design: Savings, Budget, Trend, Subscriptions, Goals).
    static func components(_ i: WellbeingInputs) -> [WellbeingComponent] {
        [
            WellbeingComponent(key: .savings, weight: wSavings,
                               score: i.hasIncome ? savingsScore(ratePercent: i.savingsRatePercent) : nil),
            WellbeingComponent(key: .budget, weight: wBudget,
                               score: i.hasAnyBudget ? budgetScore(budgetedCount: i.budgetedCount, overCount: i.overCount, overspend: i.overspendTotal, budgeted: i.budgetedTotal) : nil),
            WellbeingComponent(key: .trend, weight: wTrend,
                               score: i.trendPercent.map { trendScore(percentVsAverage: $0) }),
            WellbeingComponent(key: .subscriptions, weight: wSubscriptions,
                               score: subscriptionsComponentScore(i)),
            WellbeingComponent(key: .goals, weight: wGoals, score: goalsScore(i.goals)),
        ]
    }

    /// The full score result, or nil total when there isn't enough data to score yet (first run).
    static func score(_ inputs: WellbeingInputs) -> WellbeingScore {
        let comps = components(inputs)
        let total = inputs.receiptsLogged >= minReceiptsToScore ? aggregate(comps) : nil
        let delta: Int? = {
            guard let prev = inputs.previousScore, let t = total else { return nil }
            return t - prev
        }()
        return WellbeingScore(score: total, band: total.map { band($0) }, components: comps, trendDeltaVsPrevious: delta)
    }

    // ── Tips ────────────────────────────────────────────────────────────────────

    private static func severity(_ tone: TipTone) -> Int {
        switch tone {
        case .alert: return 0
        case .caution: return 1
        case .opportunity: return 2
        case .win: return 3
        }
    }

    /// Ranks candidates alert→caution→opportunity, caps the list, always keeping one win when available.
    static func rank(_ candidates: [WellbeingTip], cap: Int) -> [WellbeingTip] {
        let ordered = candidates.sorted { severity($0.tone) < severity($1.tone) }
        let wins = ordered.filter { $0.tone == .win }
        let others = ordered.filter { $0.tone != .win }
        if others.isEmpty { return Array(wins.prefix(cap)) }
        if wins.isEmpty { return Array(others.prefix(cap)) }
        return Array(others.prefix(max(1, cap - 1))) + Array(wins.prefix(1))
    }

    static func tips(_ inputs: WellbeingInputs) -> [WellbeingTip] { rank(monthlyCandidates(inputs), cap: monthlyTipCap) }

    static func weeklyTips(_ week: WeeklyInputs) -> [WellbeingTip] { rank(weeklyCandidates(week), cap: weeklyTipCap) }

    private static func monthlyCandidates(_ i: WellbeingInputs) -> [WellbeingTip] {
        var out: [WellbeingTip] = []

        // Alert — spent more than earned.
        if i.hasIncome, i.netCashflow < 0 {
            out.append(WellbeingTip(type: .negativeCashflow, id: "negative_cashflow", tone: .alert, amount: abs(i.netCashflow)))
        }
        // Alert — over budget in one or more categories.
        if i.overCount > 0, i.overspendTotal > 0 {
            out.append(WellbeingTip(type: .overBudget, id: "over_budget", tone: .alert, amount: i.overspendTotal, count: i.overCount))
        }
        // Caution — a spending category well above its own average.
        if let c = i.categories
            .filter({ $0.average > 0 && $0.current.dbl > $0.average.dbl * 1.30 })
            .max(by: { ($0.current.dbl - $0.average.dbl) < ($1.current.dbl - $1.average.dbl) }) {
            let pct = Int(((c.current.dbl / c.average.dbl - 1.0) * 100).rounded())
            out.append(WellbeingTip(type: .categorySpike, id: "spike:\(c.category)", tone: .caution, amount: c.current, amount2: c.average, percent: pct, label: c.category))
        }
        // Caution — subscription load is heavy.
        if let share = i.subsSharePercent, share >= 8, i.subsCount > 0 {
            out.append(WellbeingTip(type: .subscriptionCost, id: "subs_cost", tone: .caution, amount: i.subsMonthly, percent: share, count: i.subsCount))
        }
        // Opportunity — a material category with no budget.
        if let c = i.categories
            .filter({ !$0.hasBudget && $0.monthlyAverage > 0 && $0.monthlyAverage >= 50 })
            .max(by: { $0.monthlyAverage.dbl < $1.monthlyAverage.dbl }) {
            out.append(WellbeingTip(type: .missingBudget, id: "missing_budget:\(c.category)", tone: .opportunity, amount: c.monthlyAverage, label: c.category))
        }
        // Opportunity — no savings goal yet.
        if i.goals.isEmpty {
            out.append(WellbeingTip(type: .noGoal, id: "no_goal", tone: .opportunity))
        }
        // Opportunity — a goal is off track.
        if let g = i.goals.first(where: { $0.behind && !$0.reached }) {
            out.append(WellbeingTip(type: .goalOffTrack, id: "goal_off:\(g.name)", tone: .opportunity, count: g.monthsLate, label: g.name))
        }
        // Win — a healthy savings rate.
        if i.hasIncome, i.savingsRatePercent >= 15 {
            out.append(WellbeingTip(type: .savingsWin, id: "savings_win", tone: .win, amount: i.saved, percent: i.savingsRatePercent))
        }
        // Win — a category clearly down.
        if let c = i.categories
            .filter({ $0.average > 0 && $0.current.dbl < $0.average.dbl * 0.85 && $0.average >= 40 })
            .max(by: { ($0.average.dbl - $0.current.dbl) < ($1.average.dbl - $1.current.dbl) }) {
            let pct = Int(((1.0 - c.current.dbl / c.average.dbl) * 100).rounded())
            out.append(WellbeingTip(type: .categoryImproved, id: "improved:\(c.category)", tone: .win, percent: pct, label: c.category))
        }
        return out
    }

    private static func weeklyCandidates(_ week: WeeklyInputs) -> [WellbeingTip] {
        var out: [WellbeingTip] = []
        if let p = week.pacedCategory, p.percentUsed >= 70 {
            out.append(WellbeingTip(type: .budgetPace, id: "pace:\(p.name)", tone: .caution, amount: p.remaining, percent: p.percentUsed, label: p.name))
        }
        if let l = week.leakCategory {
            out.append(WellbeingTip(type: .smallPurchaseLeak, id: "leak:\(l.name)", tone: .caution, amount: l.total, count: l.count, label: l.name))
        }
        if let u = week.underPaceCategory {
            out.append(WellbeingTip(type: .underPaceWin, id: "under:\(u.name)", tone: .win, amount: u.under, label: u.name))
        }
        return out
    }
}
