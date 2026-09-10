//
//  NeedsWantsSplit.swift
//  Budgetty
//
//  Pure derivation for the Insights Needs / Wants / Savings (50/30/20) split — a direct port of the
//  math in Android's `InsightsViewModel`. iOS has no ViewModel, so the logic lives here as a pure,
//  testable enum consumed by computed properties in `InsightsView` (the same pattern as `SavingsMath`
//  / `StreakEngine`). Shares bucket resolution with the Manage-categories tagging UI via
//  `Categories.effectiveBucket(of:in:)`, so re-tagging a category reclassifies its past months.
//

import Foundation

// MARK: - Value types

/// Which way the split leans this period — drives the one-line summary under the card.
enum SplitTone { case balanced, needsOver, wantsOver, underSaving }

/// How a bucket sits against its target, driving its delta pill's colour and wording. Within
/// tolerance is `onTarget` (good). Over on Needs/Wants (`overWarn`) and under on Savings
/// (`underWarn`) use the warn pair; under on Needs/Wants is neutral (`underNeutral`) — spending less
/// than the rule allows isn't a warning; over on Savings is the one other good case (`overGood`).
enum BucketDeltaStatus { case onTarget, overWarn, underNeutral, underWarn, overGood }

/// How Savings is counted in the split — the user's one-time choice (see
/// `SettingsKey.nwsSavingsAllocation`): `unset` hasn't been asked yet (the card shows the inline
/// ask), `countKept` counts everything not spent on Needs/Wants as saved, `setAside` counts only
/// deliberate savings (goal transfers + Savings-tagged spend) and shows the rest as leftover.
enum SavingsAllocation: Int {
    case unset = 0, countKept = 1, setAside = 2

    /// The nullable-Bool form Android stores (`nwsCountLeftoverAsSavings`): nil = unset.
    var countLeftoverAsSavings: Bool? {
        switch self {
        case .unset: nil
        case .countKept: true
        case .setAside: false
        }
    }
}

/// One bucket's share of income for the Needs/Wants/Savings card.
struct BucketShare: Equatable {
    let bucket: CategoryBucket
    let amount: Decimal
    /// amount / income, 0…1+ (unclamped — the bar clamps; the rows show `percent`).
    let fraction: Double
    /// Rounded whole-percent of income, for the headline number and the delta pill.
    let percent: Int
    /// This bucket's 50 / 30 / 20 target.
    let targetPercent: Int
    /// How `percent` sits against `targetPercent` — the delta pill's colour/wording.
    let status: BucketDeltaStatus
    /// Signed distance from target in whole points (positive = over target).
    var deltaPoints: Int { percent - targetPercent }
}

/// The Needs/Wants/Savings 50/30/20 split for the selected period, on an income basis (each share is
/// of income, so the rule is comparable month to month even when spending swings). `nil` → the setup
/// state, shown when there's no income to measure against.
struct NeedsWantsSplit: Equatable {
    let income: Decimal
    let needs: BucketShare
    let wants: BucketShare
    let savings: BucketShare
    /// Income not accounted for by the three buckets, as a 0…1 fraction — the bar's leftover track
    /// (zero under `.countKept`, where Savings absorbs it).
    let leftoverFraction: Double
    let tone: SplitTone
    /// How Savings is counted — drives the one-time ask, the Savings row, and the leftover row.
    let allocation: SavingsAllocation
    /// The leftover amount (income − Needs − Wants − deliberate savings), for the leftover row + copy.
    let leftover: Decimal
}

/// One closed month in the split trend (plotted oldest-first); shares are whole-percent of that
/// month's income.
struct BucketMonth: Equatable {
    /// Short month label under the column, e.g. "Sep".
    let axisLabel: String
    let needsPercent: Int
    let wantsPercent: Int
    let savingsPercent: Int
}

// MARK: - Derivation

enum NeedsWantsSplitMath {
    /// Target share of income for each bucket — the 50/30/20 rule.
    static let needsTarget = 50
    static let wantsTarget = 30
    static let savingsTarget = 20
    /// A bucket within this many points of its target reads as "on target" rather than over/under.
    static let onTargetTolerance = 2
    /// How many closed pay-cycle months the split trend plots at most.
    static let trendMonths = 6
    /// The split trend is hidden until at least this many closed months are available.
    static let minTrendMonths = 2

    /// Category-tagged spend for one month, plus that month's income and net savings contributions —
    /// the per-month inputs the trailing trend is built from (newest closed month first).
    struct MonthInput {
        let axisLabel: String
        let income: Decimal
        /// Spend per raw category name in the month (as the Breakdown attributes it — line totals).
        let spendByCategory: [String: Decimal]
        /// Net (signed) savings-goal contributions dated within the month.
        let savingsContributed: Decimal
    }

    /// The Needs/Wants/Savings split for a period on an income basis. `spendByCategory` is the
    /// period's spend per raw category (Needs/Wants come from category tags; Savings is Savings-tagged
    /// spend plus `savingsContributed`, the net savings-goal contributions in the window). Returns
    /// `nil` when `income` ≤ 0 — nothing to measure 50/30/20 against, so the card shows its setup
    /// state instead.
    ///
    /// `countLeftoverAsSavings` is the user's one-time choice: `true` folds the leftover (income kept
    /// back but not deliberately saved) into Savings; `false`/`nil` keeps Savings to deliberate
    /// savings only and reports the rest as `leftover`. `nil` also marks the split `.unset` so the
    /// card shows the inline ask.
    static func split(
        income: Decimal,
        spendByCategory: [String: Decimal],
        categories: [Category],
        savingsContributed: Decimal,
        countLeftoverAsSavings: Bool?
    ) -> NeedsWantsSplit? {
        guard income > 0 else { return nil }
        let byName = Categories.index(categories)
        let spend = bucketSpend(spendByCategory, byName)
        let deliberateSavings = max(spend.savings + savingsContributed, 0)
        // Income kept back after Needs and Wants that wasn't deliberately saved.
        let leftover = max(income - spend.needs - spend.wants - deliberateSavings, 0)

        let countKept = countLeftoverAsSavings == true
        let savingsAmount = countKept ? max(income - spend.needs - spend.wants, 0) : deliberateSavings

        let needs = share(.need, spend.needs, needsTarget, income)
        let wants = share(.want, spend.wants, wantsTarget, income)
        let savings = share(.savings, savingsAmount, savingsTarget, income)
        let leftoverFraction = countKept ? 0 : clamp01(dbl(leftover) / dbl(income))
        let tone: SplitTone
        if savings.percent < savingsTarget - onTargetTolerance {
            tone = .underSaving
        } else if wants.percent > wantsTarget + onTargetTolerance {
            tone = .wantsOver
        } else if needs.percent > needsTarget + onTargetTolerance {
            tone = .needsOver
        } else {
            tone = .balanced
        }
        let allocation: SavingsAllocation
        switch countLeftoverAsSavings {
        case .none: allocation = .unset
        case .some(true): allocation = .countKept
        case .some(false): allocation = .setAside
        }
        return NeedsWantsSplit(
            income: round2(income), needs: needs, wants: wants, savings: savings,
            leftoverFraction: leftoverFraction, tone: tone, allocation: allocation,
            leftover: round2(leftover)
        )
    }

    /// The split for each of the last `trendMonths` closed pay-cycle months, oldest first. `recentFirst`
    /// carries the candidate months most-recent-closed first; the run stops at the first month with no
    /// income plan (income ≤ 0) so the returned trend is contiguous and never shows an income-less gap.
    /// Mirrors Android's `computeBucketTrend`.
    static func trend(recentFirst months: [MonthInput], categories: [Category]) -> [BucketMonth] {
        let byName = Categories.index(categories)
        var out: [BucketMonth] = []
        for m in months {
            guard m.income > 0 else { break }
            let spend = bucketSpend(m.spendByCategory, byName)
            let savings = max(spend.savings + m.savingsContributed, 0)
            out.insert(
                BucketMonth(
                    axisLabel: m.axisLabel,
                    needsPercent: pctOf(spend.needs, m.income),
                    wantsPercent: pctOf(spend.wants, m.income),
                    savingsPercent: pctOf(savings, m.income)
                ),
                at: 0
            )
        }
        return out
    }

    /// Whole-percent share of `income` (rounds half away from zero, like Android's `pctOf`).
    static func pctOf(_ amount: Decimal, _ income: Decimal) -> Int {
        guard income > 0 else { return 0 }
        return Int((dbl(amount) / dbl(income) * 100).rounded())
    }

    // MARK: - Internals

    /// Category-tagged spend split into the three buckets. Savings here is only Savings-tagged
    /// category spend; the caller adds goal contributions.
    private static func bucketSpend(
        _ spendByCategory: [String: Decimal], _ byName: [String: Category]
    ) -> (needs: Decimal, wants: Decimal, savings: Decimal) {
        var needs = Decimal.zero, wants = Decimal.zero, savings = Decimal.zero
        for (category, amount) in spendByCategory {
            switch Categories.effectiveBucket(of: category, in: byName) {
            case .need: needs += amount
            case .want: wants += amount
            case .savings: savings += amount
            }
        }
        return (needs, wants, savings)
    }

    private static func share(
        _ bucket: CategoryBucket, _ amount: Decimal, _ target: Int, _ income: Decimal
    ) -> BucketShare {
        let percent = pctOf(amount, income)
        let delta = percent - target
        let status: BucketDeltaStatus
        if abs(delta) <= onTargetTolerance {
            status = .onTarget
        } else if bucket == .savings {
            status = delta > 0 ? .overGood : .underWarn
        } else {
            status = delta > 0 ? .overWarn : .underNeutral
        }
        return BucketShare(
            bucket: bucket, amount: round2(amount),
            fraction: max(dbl(amount) / dbl(income), 0), percent: percent,
            targetPercent: target, status: status
        )
    }

    private static func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }
    private static func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func round2(_ d: Decimal) -> Decimal {
        (d as NSDecimalNumber).rounding(accordingToBehavior: round2Handler).decimalValue
    }
    private static let round2Handler = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false,
        raiseOnUnderflow: false, raiseOnDivideByZero: false)
}
