//
//  TripStats.swift
//  Budgetty
//
//  The time-and-pace maths for a trip — pure (no SwiftData, no SwiftUI) so it can be unit-tested
//  against the design's worked example. `spent` and `expenseCount` are summed by the view from the
//  transactions carrying the trip's tag; everything here derives from the trip's dates/budget and
//  `today`. Android parity: `ui/trips/TripStats.kt`.
//
//  With no dates a trip still has a `perDay` (counted from when it was created), but no `totalDays`,
//  `daysLeft`, `dayStrip` or `pace` — those need a known span.
//

import Foundation

/// Where spending sits against the even day-by-day pace of a trip's budget.
enum TripPaceState { case underPace, overPace, overBudget }

/// A trip budget's pace — the same spent-vs-time idea the multiple-budgets pace bar uses. `fill` is
/// the fraction of the budget spent and `tickFraction` the fraction of the trip's days elapsed, both
/// clamped to 0...1 for drawing; `state` compares them. `suggestedDaily` is what you can spend each
/// remaining day and still land on budget (0 once you're over).
struct TripPace {
    let fill: Double
    let tickFraction: Double
    let state: TripPaceState
    let remaining: Decimal
    let suggestedDaily: Decimal
}

struct TripStatsResult {
    let daysElapsed: Int
    let totalDays: Int?
    let daysLeft: Int?
    let perDay: Decimal
    /// One bool per trip day: true for elapsed days. Empty when the trip has no date span.
    let dayStrip: [Bool]
    let pace: TripPace?
}

enum TripStats {

    static func compute(_ trip: Trip, spent: Decimal, today: Date = .now,
                        calendar: Calendar = .current) -> TripStatsResult {
        let startDay = calendar.startOfDay(for: trip.startDate ?? trip.createdAt)
        let endDay = trip.endDate.map { calendar.startOfDay(for: $0) }
        let totalDays = endDay.map { max(1, daysBetween(startDay, $0, calendar) + 1) }

        // Day 1 is the start day itself; clamp into [1, totalDays] so a future start or an overrun
        // still reads sensibly (day 1, or the final day).
        let rawElapsed = daysBetween(startDay, calendar.startOfDay(for: today), calendar) + 1
        let daysElapsed = clamp(rawElapsed, 1, totalDays ?? Int.max)
        let daysLeft = totalDays.map { max(0, $0 - daysElapsed) }

        let perDay = spent / Decimal(daysElapsed)
        let dayStrip = totalDays.map { total in (0..<total).map { $0 < daysElapsed } } ?? []

        let pace: TripPace?
        if let budget = trip.budgetAmount, budget > 0, let total = totalDays {
            pace = computePace(spent: spent, budget: budget, daysElapsed: daysElapsed,
                               totalDays: total, daysLeft: daysLeft ?? 0)
        } else {
            pace = nil
        }

        return TripStatsResult(daysElapsed: daysElapsed, totalDays: totalDays, daysLeft: daysLeft,
                               perDay: perDay, dayStrip: dayStrip, pace: pace)
    }

    private static func computePace(spent: Decimal, budget: Decimal, daysElapsed: Int,
                                    totalDays: Int, daysLeft: Int) -> TripPace {
        let spentFraction = double(spent) / double(budget)
        let timeFraction = Double(daysElapsed) / Double(totalDays)
        let remaining = budget - spent
        let state: TripPaceState =
            spent > budget ? .overBudget :
            (spentFraction > timeFraction ? .overPace : .underPace)
        // What's left, spread over the days still to come (today counts as a day you can still spend).
        let suggestedDaily = remaining <= 0 ? Decimal.zero : remaining / Decimal(max(1, daysLeft))
        return TripPace(fill: clamp01(spentFraction), tickFraction: clamp01(timeFraction),
                        state: state, remaining: remaining, suggestedDaily: suggestedDaily)
    }

    private static func daysBetween(_ a: Date, _ b: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: a, to: b).day ?? 0
    }
    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
    private static func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
    private static func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
}
