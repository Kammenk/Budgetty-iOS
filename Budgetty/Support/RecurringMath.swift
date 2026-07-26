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
}
