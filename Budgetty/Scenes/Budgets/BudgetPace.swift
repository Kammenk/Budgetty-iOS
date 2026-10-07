//
//  BudgetPace.swift
//  Budgetty
//
//  Pure pace math for a time-boxed budget ("envelope") — no SwiftData/SwiftUI deps, so it's
//  unit-testable. 1:1 port of Android's `ui/budgets/BudgetPace.kt`.
//

import Foundation

/// How a budget is tracking against its time window.
enum PaceState { case onPace, ahead, overPace, overBudget }

/// The derived pace of a budget on a given day: bar fill, the "today" tick, and the derived figures.
struct PaceResult {
    /// 0…1 fraction of the limit spent (capped at 1 for the bar).
    let fill: Double
    /// 0…1 fraction of the window elapsed — the "Today" tick position.
    let todayFraction: Double
    let state: PaceState
    /// limit − spent (can be negative when over budget).
    let remaining: Decimal
    let daysLeft: Int
    /// remaining ÷ days left — the daily allowance to stay on budget.
    let dailyAllowance: Decimal
    /// spent ÷ elapsed days — the actual average so far.
    let avgPerDay: Decimal
    /// Projected end-of-window total at the current pace (spent ÷ elapsed × total).
    let projected: Decimal
}

enum BudgetPace {

    /// Above this spent-vs-elapsed ratio a budget is "over pace"; between 1.0 and here it's "ahead".
    static let aheadRatio = 1.15

    /// Pace for a budget of `limit` that has `spent` over an inclusive window `start`…`end`, as of
    /// `today`. On or below a 1.0 spent/elapsed ratio is on pace; up to `aheadRatio` is slightly ahead;
    /// beyond that, or past 100% spent, is over.
    static func compute(spent: Decimal, limit: Decimal, start: Date, end: Date, today: Date,
                        calendar cal: Calendar = .current) -> PaceResult {
        let startDay = cal.startOfDay(for: start)
        let endDay = cal.startOfDay(for: end)
        let totalDays = Swift.max(1, days(startDay, cal.date(byAdding: .day, value: 1, to: endDay)!, cal))
        let clampedToday = Swift.min(Swift.max(cal.startOfDay(for: today), startDay), endDay)
        let elapsedDays = Swift.min(Swift.max(1, days(startDay, cal.date(byAdding: .day, value: 1, to: clampedToday)!, cal)), totalDays)
        let daysLeft = Swift.max(0, totalDays - elapsedDays)

        let limitD = Swift.max(0.01, dbl(limit))
        let spentFraction = dbl(spent) / limitD
        let elapsedFraction = Double(elapsedDays) / Double(totalDays)
        let ratio = elapsedFraction > 0 ? spentFraction / elapsedFraction : 0
        let state: PaceState =
            spent > limit ? .overBudget : (ratio > aheadRatio ? .overPace : (ratio > 1.0 ? .ahead : .onPace))

        let remaining = limit - spent
        let dailyAllowance = daysLeft > 0 ? round2(remaining / Decimal(daysLeft)) : remaining
        let avgPerDay = round2(spent / Decimal(elapsedDays))
        let projected = round2(spent * Decimal(totalDays) / Decimal(elapsedDays))

        return PaceResult(fill: clamp01(spentFraction), todayFraction: clamp01(elapsedFraction), state: state,
                          remaining: remaining, daysLeft: daysLeft, dailyAllowance: dailyAllowance,
                          avgPerDay: avgPerDay, projected: projected)
    }

    private static func days(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
    private static func dbl(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
    private static func clamp01(_ v: Double) -> Double { Swift.min(1, Swift.max(0, v)) }
    private static func round2(_ d: Decimal) -> Decimal {
        var r = Decimal(); var v = d; NSDecimalRound(&r, &v, 2, .plain); return r
    }
}
