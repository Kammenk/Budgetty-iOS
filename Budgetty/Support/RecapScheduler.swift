//
//  RecapScheduler.swift
//  Budgetty
//
//  Pure scheduler for the end-of-period recap — the Swift port of Android's `RecapScheduler` +
//  `RecapDataGuard`. Decides which recap (if any) is due on an app open, from the user's cadence + the
//  last-shown period keys + the clock. No SwiftUI, no SwiftData — so the whole "when does it fire"
//  contract is unit-testable and matches the Android `RecapSchedulerTest` 1:1.
//
//  It is deliberately split from the data check: this decides the *boundary* has been crossed;
//  `RecapDataGuard` decides — once the store has loaded — whether there's enough data worth showing.
//  The interstitial is modelled on the onboarding/quiz gate + a `ReviewGate`-style last-shown key:
//  shown once per completed period, on first open on/after the boundary.
//

import Foundation

/// A recap that is due on this app open. `show` is the one to display — Monthly wins when both are due,
/// because it's the fuller report — while `markWeek`/`markMonth` are the period ids to stamp as shown.
/// Both are stamped even when only one screen appears, so the other cadence doesn't stack a second
/// interstitial in the same open.
struct RecapDue: Equatable {
    let show: RecapKind
    let markWeek: String?
    let markMonth: String?
}

extension RecapKind: Equatable {}

enum RecapScheduler {

    /// The pay-cycle month that has just closed as of `today` — the one a monthly recap is about. This
    /// is offset −1 from the cycle containing today, so on/after the pay-cycle boundary it names the
    /// month that ended (e.g. opening on 1 Aug with a calendar cycle → "2026-07").
    static func justClosedMonthId(_ today: Date, startDay: Int, calendar cal: Calendar = .current) -> String {
        let (start, _) = PayCycle.month(today, startDay: startDay, offset: -1, calendar: cal)
        return monthFormatter(cal).string(from: start)
    }

    /// Start date (ISO yyyy-MM-dd) of the week that has just closed as of `today` — the week before the
    /// one containing today, anchored on the locale's `firstWeekday`. Its stability across a whole week
    /// is what makes it a per-week key.
    static func justClosedWeekId(_ today: Date, firstWeekday: Int, calendar cal: Calendar = .current) -> String {
        var cal = cal
        cal.firstWeekday = firstWeekday
        let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? cal.startOfDay(for: today)
        let previousWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart) ?? currentWeekStart
        return dayFormatter(cal).string(from: previousWeekStart)
    }

    /// The recap due on this open, or nil when none is (disabled, or the just-closed period's recap was
    /// already shown). When both cadences are due, `RecapDue.show` is `.monthly` but BOTH ids are
    /// returned to mark, so the weekly doesn't also fire in the same open.
    static func due(enabled: Bool,
                    frequency: RecapFrequency,
                    lastShownWeek: String,
                    lastShownMonth: String,
                    today: Date,
                    startDay: Int,
                    firstWeekday: Int,
                    calendar cal: Calendar = .current) -> RecapDue? {
        guard enabled else { return nil }
        let monthId = justClosedMonthId(today, startDay: startDay, calendar: cal)
        let weekId = justClosedWeekId(today, firstWeekday: firstWeekday, calendar: cal)
        let monthlyDue = frequency != .weekly && lastShownMonth != monthId
        let weeklyDue = frequency != .monthly && lastShownWeek != weekId
        if monthlyDue {
            return RecapDue(show: .monthly, markWeek: weeklyDue ? weekId : nil, markMonth: monthId)
        }
        if weeklyDue {
            return RecapDue(show: .weekly, markWeek: weekId, markMonth: nil)
        }
        return nil
    }

    private static func monthFormatter(_ cal: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }

    private static func dayFormatter(_ cal: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

/// Outcome of the data check: skip entirely, or show — with or without the vs-previous comparison.
enum RecapGuard: Equatable {
    /// Not enough data to be worth showing (under the scoring floor, or the period had no spend).
    case skip
    /// Enough to show. `withComparison` is false when there's no prior period to compare against, so
    /// the story drops the comparison-dependent cards rather than showing an empty comparison.
    case show(withComparison: Bool)
}

/// Pure first-run / not-enough-data guard, applied once the store has loaded. Under the wellbeing
/// scoring floor (`WellbeingEngine.minReceiptsToScore` = 5 receipts), or when the just-closed period
/// itself had no spend, the recap is skipped (and marked shown so it isn't re-checked every open). With
/// data but no prior period to compare, a partial recap is shown that drops the comparison cards.
enum RecapDataGuard {
    /// Kept in step with the wellbeing score's first-run floor so the two features agree.
    static let minReceipts = WellbeingEngine.minReceiptsToScore

    static func evaluate(totalReceipts: Int, periodHasSpend: Bool, priorPeriodHasSpend: Bool) -> RecapGuard {
        if totalReceipts < minReceipts || !periodHasSpend { return .skip }
        return .show(withComparison: priorPeriodHasSpend)
    }
}
