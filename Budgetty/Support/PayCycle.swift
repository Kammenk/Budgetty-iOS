//
//  PayCycle.swift
//  Budgetty
//
//  The user's "financial month" — a month that begins on their pay day instead of the calendar 1st.
//  A port of Android's `PayCycle`. `startDay` (1–31; 1 = the ordinary calendar month) comes from the
//  "Month starts on" preference; a 29/30/31 pay day clamps to a short month's last day, the same
//  clamp a recurring bill's due-day already uses. Only the "month" concept shifts — week, quarter
//  and half-year stay calendar/locale-aligned (matching Android's scope decision).
//

import Foundation

enum PayCycle {
    /// The stored pay day (1–31), clamped; 1 (or unset) is the ordinary calendar month. Read straight
    /// from `UserDefaults` — like `DateFormatOption.current` — so non-view callers (the widget
    /// snapshot, `InsightsPeriod`) resolve it too; views also declare
    /// `@AppStorage(SettingsKey.monthStartDay)` so they re-render when it changes.
    static var startDay: Int {
        let raw = UserDefaults.standard.integer(forKey: SettingsKey.monthStartDay)
        return raw == 0 ? 1 : min(max(raw, 1), 31)   // 0 == never set → calendar month
    }

    /// The pay-cycle month `offset` cycles from the one containing `today` (0 = current, −1 = previous,
    /// +1 = next), as an inclusive `[start, end]` pair of days. With `startDay == 1` this is the plain
    /// calendar month; otherwise the cycle is anchored on `startDay`, clamped per month length.
    static func month(_ today: Date = .now,
                      startDay: Int = PayCycle.startDay,
                      offset: Int = 0,
                      calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let day = cal.startOfDay(for: today)
        let thisMonthFirst = firstOfMonth(day, cal)
        // The cycle containing today opens on this month's anchored start once it has arrived,
        // otherwise last month's (today sits in the previous cycle's tail).
        let currentCycleFirst = day < anchor(thisMonthFirst, startDay, cal)
            ? cal.date(byAdding: .month, value: -1, to: thisMonthFirst)!
            : thisMonthFirst
        let cycleFirst = cal.date(byAdding: .month, value: offset, to: currentCycleFirst)!
        let start = anchor(cycleFirst, startDay, cal)
        let nextFirst = cal.date(byAdding: .month, value: 1, to: cycleFirst)!
        let end = cal.date(byAdding: .day, value: -1, to: anchor(nextFirst, startDay, cal))!
        return (start, end)
    }

    /// Half-open `[start, nextStart)` interval of the same pay-cycle month, for `interval.contains`
    /// filters — the whole of `end`'s day is included.
    static func monthInterval(_ today: Date = .now,
                              startDay: Int = PayCycle.startDay,
                              offset: Int = 0,
                              calendar cal: Calendar = .current) -> DateInterval {
        let (start, end) = month(today, startDay: startDay, offset: offset, calendar: cal)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return DateInterval(start: cal.startOfDay(for: start), end: endExclusive)
    }

    // MARK: - Fortnight (Android parity: PayCycle.fortnight — the Fortnightly budget cadence)

    /// A fortnight is a fixed 14-day block, unlike the 28–31-day pay-cycle month.
    static let fortnightDays = 14

    /// Days between a fixed reference (1970-01-01, local) and `date`'s start of day — the "epoch day"
    /// used to persist a fortnight anchor in `UserDefaults` (Android's `LocalDate.toEpochDay`).
    static func epochDay(_ date: Date, _ cal: Calendar = .current) -> Int {
        let ref = cal.startOfDay(for: Date(timeIntervalSince1970: 0))
        return cal.dateComponents([.day], from: ref, to: cal.startOfDay(for: date)).day ?? 0
    }
    private static func date(fromEpochDay day: Int, _ cal: Calendar = .current) -> Date {
        let ref = cal.startOfDay(for: Date(timeIntervalSince1970: 0))
        return cal.date(byAdding: .day, value: day, to: ref)!
    }

    /// The 14-day fortnight `offset` fortnights from the one containing `today`, as an inclusive
    /// `[start, end]` day pair. Fortnights run continuously every 14 days from `anchorEpochDay` (a
    /// reference pay day), so — unlike `month` — they keep the same length across month boundaries and
    /// never re-anchor; the block containing today is found by snapping down to the nearest 14-day
    /// boundary (floor division, so a today before the anchor still resolves to its containing block).
    static func fortnight(_ today: Date = .now, anchorEpochDay: Int, offset: Int = 0,
                          calendar cal: Calendar = .current) -> (start: Date, end: Date) {
        let anchor = date(fromEpochDay: anchorEpochDay, cal)
        let daysBetween = cal.dateComponents([.day], from: anchor, to: cal.startOfDay(for: today)).day ?? 0
        let blocks = Int(floor(Double(daysBetween) / Double(fortnightDays)))
        let start = cal.date(byAdding: .day, value: (blocks + offset) * fortnightDays, to: anchor)!
        let end = cal.date(byAdding: .day, value: fortnightDays - 1, to: start)!
        return (start, end)
    }

    /// Half-open interval of the fortnight, for `interval.contains` filters.
    static func fortnightInterval(_ today: Date = .now, anchorEpochDay: Int, offset: Int = 0,
                                  calendar cal: Calendar = .current) -> DateInterval {
        let (start, end) = fortnight(today, anchorEpochDay: anchorEpochDay, offset: offset, calendar: cal)
        let endExclusive = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: end))!
        return DateInterval(start: cal.startOfDay(for: start), end: endExclusive)
    }

    /// A stable default fortnight anchor (epoch day) when none is persisted: the start of the pay-cycle
    /// month containing `today`. Pinned once so fortnights don't drift (re-deriving monthly would jump
    /// the anchor by a non-multiple of 14 days). Android: `defaultFortnightAnchor`.
    static func defaultFortnightAnchor(_ today: Date = .now, startDay: Int = PayCycle.startDay,
                                       calendar cal: Calendar = .current) -> Int {
        epochDay(month(today, startDay: startDay, calendar: cal).start, cal)
    }

    /// First day (start-of-day) of the calendar month containing `date`.
    private static func firstOfMonth(_ date: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date))!
    }

    /// `startDay` of the calendar month that `monthFirst` opens, clamped to the month's length so
    /// short months stay valid (a 31st pay day starts February on the 28th/29th). Counted forward
    /// from day 1 rather than built with a day component so an out-of-range day can't be invalid.
    private static func anchor(_ monthFirst: Date, _ startDay: Int, _ cal: Calendar) -> Date {
        let length = cal.range(of: .day, in: .month, for: monthFirst)?.count ?? 28
        let clamped = min(max(startDay, 1), length)
        return cal.date(byAdding: .day, value: clamped - 1, to: monthFirst)!
    }
}
