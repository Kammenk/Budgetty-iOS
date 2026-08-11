//
//  Recurring.swift
//  Budgetty
//
//  Android's RecurringEntity — a recurring money entry on the Budget screen: either an income
//  source (`isIncome == true`) or a recurring payment / bill. Same primitive, opposite signs.
//  Planning-only: these feed the Budget breakdown but never post transactions (the scheduling
//  fields are reserved for a later auto-posting phase).
//

import Foundation
import SwiftData

enum Cadence: String, Codable, CaseIterable {
    case monthly = "MONTHLY"
    case weekly = "WEEKLY"
    case yearly = "YEARLY"
    /// A single, non-repeating entry — counts toward the budget only for its `createdAt` month.
    case once = "ONCE"
}

@Model
final class Recurring {
    var label: String
    var amount: Decimal

    /// True for income sources, false for bills.
    var isIncome: Bool

    /// Spending category for a bill; empty for income.
    var category: String

    /// How often it repeats.
    var cadenceRaw: String

    /// Day-of-month (1...31) for monthly/yearly, or day-of-week (1=Mon...7=Sun) for weekly.
    /// Unused for `.once`, which anchors to `createdAt`.
    var dueDay: Int

    var createdAt: Date

    /// Bills only: when true, the bill auto-marks as paid once `dueDay` passes each cycle (monthly &
    /// weekly only — yearly stores no month, one-offs don't recur). Derived on read, no scheduled job.
    /// Defaulted so SwiftData lightweight-migrates existing rows.
    var autoPay: Bool = false

    // Reserved for the later auto-posting phase (unused while planning-only).
    var nextDue: Date?
    var lastPosted: Date?
    var active: Bool

    init(
        label: String,
        amount: Decimal,
        isIncome: Bool,
        category: String = "",
        cadence: Cadence = .monthly,
        dueDay: Int = 1,
        createdAt: Date = .now,
        active: Bool = true
    ) {
        self.label = label
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.cadenceRaw = cadence.rawValue
        self.dueDay = dueDay
        self.createdAt = createdAt
        self.nextDue = nil
        self.lastPosted = nil
        self.active = active
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    /// Whether autopay can apply to this entry at all — bills only (never income), and only monthly or
    /// weekly cadences: yearly stores no month and one-offs don't recur, so neither has a due date to
    /// auto-mark against. Independent of the `autoPay` toggle. Android parity: `autoPayEligible`.
    var autoPayEligible: Bool { !isIncome && (cadence == .monthly || cadence == .weekly) }

    /// True when autopay is both switched on and `autoPayEligible` for this entry's cadence — the
    /// single source of truth for "this bill is auto-managed". Used when persisting (so a yearly/
    /// one-off entry can never keep a stuck autopay flag) and when displaying (so the Budget row shows
    /// a manual paid toggle, not the "Auto" chip, for any ineligible entry — including rows saved
    /// before the rule was enforced). Android parity: `isAutoPayActive`.
    var isAutoPayActive: Bool { autoPay && autoPayEligible }

    /// The amount normalized to a monthly figure (for period-scaled Insights).
    var monthlyEquivalent: Decimal {
        switch cadence {
        case .monthly, .once: amount
        case .weekly: amount * Decimal(52) / Decimal(12)
        case .yearly: amount / Decimal(12)
        }
    }

    /// The entry's contribution to `window`, counting a recurring cadence only from the month it was
    /// added (`createdAt`) onward — so a salary or bill is never projected back onto months it didn't
    /// yet exist for (a half-year view no longer shows 6× a just-added salary). A one-time entry counts
    /// its full amount once, and only if it was added inside the window. A window that is a whole number
    /// of monthly steps from its own start day — the calendar month, the user's pay-cycle month (e.g.
    /// the 10th → the 9th) and quarters/halves — counts by months, so one such period is exactly one
    /// month's rate whatever its 28–31 day length; only genuinely partial windows (a week step, a custom
    /// range) are day-scaled over an average month (30.4375). A direct port of Android's
    /// `RecurringEntity.windowAmount` — the createdAt-clip that fixed the back-projection bug.
    func windowAmount(_ window: DateInterval, calendar cal: Calendar = .current) -> Decimal {
        if cadence == .once {
            return window.contains(createdAt) ? amount : 0
        }
        let rate = monthlyEquivalent
        if rate == 0 { return 0 }

        let startDate = cal.startOfDay(for: window.start)
        // window.end is exclusive, so the last included day is the day before it.
        let lastDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: window.end) ?? window.end)
        let createdDay = cal.startOfDay(for: createdAt)
        let createdMonth = cal.date(from: cal.dateComponents([.year, .month], from: createdAt)) ?? startDate
        // Clip to the part of the window on/after the month the entry was added.
        let activeStart = max(startDate, createdMonth)
        if activeStart > lastDate { return 0 }

        // Whole-month window: an exact integer number of monthly steps from the window's own start day —
        // the calendar month (1st → next 1st), the user's pay-cycle month (e.g. the 10th → the 9th), and
        // quarters/halves. Such a period counts as exactly one month's rate whether it spans 28 or 31
        // days, instead of being day-scaled. `months == 0` ⇒ a genuine partial window (a week step or a
        // custom range). A pay day clamped into a short month (29–31) can leave a boundary that isn't a
        // clean month step; that rare case falls back to day-scaling below.
        let endExclusive = cal.date(byAdding: .day, value: 1, to: lastDate) ?? lastDate
        let months = cal.dateComponents([.month], from: startDate, to: endExclusive).month ?? 0
        let landsExactly = cal.date(byAdding: .month, value: months, to: startDate) == endExclusive
        if months >= 1 && landsExactly {
            // Count only the month-steps whose occurrence began on/after the entry was added, so a plan
            // is never projected back onto cycles before it existed (matches Android's clip).
            var eligible = 0
            for step in 0..<months {
                let boundary = cal.date(byAdding: .month, value: step + 1, to: startDate) ?? endExclusive
                if boundary > createdDay { eligible += 1 }
            }
            return rate * Decimal(eligible)
        }
        // Partial window: scale by active days over an average month, matching Android's factor.
        let activeDays = (cal.dateComponents([.day], from: activeStart, to: lastDate).day ?? 0) + 1
        return rate * Decimal(activeDays) / (Decimal(string: "30.4375") ?? 30)
    }
}
