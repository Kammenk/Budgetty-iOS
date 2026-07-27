//
//  BudgetRolloverMath.swift
//  Budgetty
//
//  Pure math for budget rollover (unspent-only). A budget's period is the user's pay-cycle month,
//  identified by its cycle-start month as "yyyy-MM" — which sorts lexicographically in chronological
//  order, so period keys can be compared as plain strings. A direct port of Android's `BudgetRollover`.
//

import Foundation

enum BudgetRolloverMath {

    /// "yyyy-MM" of the pay-cycle month containing `today` (the cycle's start month).
    static func currentPeriodKey(_ today: Date = .now,
                                 startDay: Int = PayCycle.startDay,
                                 calendar cal: Calendar = .current) -> String {
        let (start, _) = PayCycle.month(today, startDay: startDay, calendar: cal)
        return key(of: start, cal)
    }

    /// Half-open `[start, nextStart)` window of the pay-cycle whose start month is `periodKey`.
    static func periodWindow(_ periodKey: String,
                             startDay: Int = PayCycle.startDay,
                             calendar cal: Calendar = .current) -> DateInterval {
        let (year, month) = parse(periodKey)
        let start = anchoredStart(year: year, month: month, startDay: startDay, cal)
        let (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1)
        let end = anchoredStart(year: ny, month: nm, startDay: startDay, cal)
        return DateInterval(start: start, end: end)
    }

    /// The period-key immediately after `periodKey`.
    static func nextPeriodKey(_ periodKey: String) -> String {
        let (year, month) = parse(periodKey)
        let (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1)
        return format(year: ny, month: nm)
    }

    /// Rolls the carried balance forward from `storedPeriodKey` up to `currentPeriodKey`. Each elapsed
    /// period's leftover — max(0, budget + carried − spent) — accumulates into the next; overspend is
    /// forgiven (never rolls negative). `spentIn` returns the spend during a given period key. Returns
    /// the carried amount as of `currentPeriodKey`, or `storedCarried` unchanged once already caught up.
    static func rollForward(storedCarried: Decimal,
                            storedPeriodKey: String,
                            currentPeriodKey: String,
                            budget: Decimal,
                            spentIn: (String) -> Decimal) -> Decimal {
        var carried = storedCarried
        var period = storedPeriodKey
        var guardCount = 0
        while period < currentPeriodKey && guardCount < maxPeriods {
            carried = max(0, budget + carried - spentIn(period))
            period = nextPeriodKey(period)
            guardCount += 1
        }
        return carried
    }

    /// Safety bound on the roll-forward loop (≈50 years) against a corrupt/ancient stored period key.
    private static let maxPeriods = 600

    // MARK: - Period-key helpers

    private static func key(of date: Date, _ cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return format(year: c.year ?? 1970, month: c.month ?? 1)
    }

    private static func format(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    private static func parse(_ periodKey: String) -> (year: Int, month: Int) {
        let parts = periodKey.split(separator: "-")
        let year = parts.count > 0 ? (Int(parts[0]) ?? 1970) : 1970
        let month = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        return (year, month)
    }

    /// `startDay` of the given month (start-of-day), clamped to the month's length so short months
    /// stay valid — the same clamp `PayCycle` uses.
    private static func anchoredStart(year: Int, month: Int, startDay: Int, _ cal: Calendar) -> Date {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? .now
        let length = cal.range(of: .day, in: .month, for: first)?.count ?? 28
        let clamped = min(max(startDay, 1), length)
        return cal.date(byAdding: .day, value: clamped - 1, to: first) ?? first
    }
}
