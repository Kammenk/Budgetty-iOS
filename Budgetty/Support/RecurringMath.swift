//
//  RecurringMath.swift
//  Budgetty
//
//  Shared money-flow math for recurring entries. Port of the paid-state half of Android's
//  `RecurringMath` — the "mark as paid" feature derives paid-state from the reused `lastPosted`
//  timestamp, so it auto-resets each cycle with no schema change and no scheduled job.
//

import Foundation

extension Recurring {

    /// Whether this bill is marked paid for its CURRENT occurrence — its `lastPosted` (set to "now"
    /// when the user taps Paid) falls inside the window of the occurrence that contains `today`: the
    /// pay-cycle month for a monthly bill, the Mon–Sun week for a weekly one, the calendar year for a
    /// yearly one. It therefore resets on its own when the next occurrence begins — last cycle's
    /// timestamp lands outside the new window — with no scheduled job. A one-time entry stays paid
    /// once set. Mirrors Android's `RecurringEntity.isPaidThisCycle`.
    func isPaidThisCycle(_ today: Date = .now,
                         startDay: Int = PayCycle.startDay,
                         calendar cal: Calendar = .current) -> Bool {
        guard let lastPosted else { return false }
        if cadence == .once { return true }

        let start: Date
        let endExclusive: Date
        switch cadence {
        case .weekly:
            // Mon–Sun week containing today, regardless of the locale's first weekday (Android uses
            // an explicit Monday anchor, so pin firstWeekday to match).
            var weekCal = cal
            weekCal.firstWeekday = 2 // Monday
            let weekStart = weekCal.dateInterval(of: .weekOfYear, for: today)?.start
                ?? cal.startOfDay(for: today)
            start = weekStart
            endExclusive = weekCal.date(byAdding: .day, value: 7, to: weekStart) ?? today
        case .yearly:
            let year = cal.component(.year, from: today)
            start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
            endExclusive = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? today
        default: // monthly
            let iv = PayCycle.monthInterval(today, startDay: startDay, calendar: cal)
            start = iv.start
            endExclusive = iv.end
        }
        return lastPosted >= start && lastPosted < endExclusive
    }

    /// Whether this bill's due date within its current occurrence has already arrived (today on/after
    /// it): the `dueDay`-th of the pay-cycle month for a monthly bill, the `dueDay` weekday of this
    /// Mon–Sun week for a weekly one. Yearly (no stored month) and one-offs return false — they have no
    /// computable due date to auto-mark against. Mirrors Android's `isDuePassedThisCycle`.
    func isDuePassedThisCycle(_ today: Date = .now,
                              startDay: Int = PayCycle.startDay,
                              calendar cal: Calendar = .current) -> Bool {
        let todayStart = cal.startOfDay(for: today)
        switch cadence {
        case .monthly:
            let iv = PayCycle.monthInterval(today, startDay: startDay, calendar: cal)
            return todayStart >= Self.dueDate(inCycle: iv, day: dueDay, calendar: cal)
        case .weekly:
            var weekCal = cal
            weekCal.firstWeekday = 2 // Monday
            let weekStart = weekCal.dateInterval(of: .weekOfYear, for: today)?.start ?? todayStart
            let offset = min(max(dueDay, 1), 7) - 1
            let due = weekCal.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            return todayStart >= cal.startOfDay(for: due)
        default: // yearly / once — no computable due date
            return false
        }
    }

    /// Whether a bill counts as paid for this cycle: manually marked (`isPaidThisCycle`) or, when
    /// `autoPay` is on, its due date has already passed (`isDuePassedThisCycle`). Auto-pay only fills
    /// paid in once the day arrives; it never clears a manual payment. Mirrors Android.
    func isEffectivelyPaidThisCycle(_ today: Date = .now,
                                    startDay: Int = PayCycle.startDay,
                                    calendar cal: Calendar = .current) -> Bool {
        isPaidThisCycle(today, startDay: startDay, calendar: cal)
            || (autoPay && isDuePassedThisCycle(today, startDay: startDay, calendar: cal))
    }

    /// The date inside pay-cycle interval `iv` whose day-of-month is `day` (clamped to the month). The
    /// cycle can span two calendar months (a non-1 start day), so fall back to the later month's day.
    private static func dueDate(inCycle iv: DateInterval, day: Int, calendar cal: Calendar) -> Date {
        func dayInMonth(of ref: Date) -> Date {
            let len = cal.range(of: .day, in: .month, for: ref)?.count ?? 28
            var c = cal.dateComponents([.year, .month], from: ref)
            c.day = min(max(day, 1), len)
            return cal.date(from: c) ?? ref
        }
        let candidate = dayInMonth(of: iv.start)
        if candidate >= iv.start && candidate < iv.end { return candidate }
        let lastDay = cal.date(byAdding: .day, value: -1, to: iv.end) ?? iv.start
        return dayInMonth(of: lastDay)
    }
}
