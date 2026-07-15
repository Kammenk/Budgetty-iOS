//
//  InsightsPeriod.swift
//  Budgetty
//
//  The time window the Insights screen is showing — a port of the Android period model: a
//  calendar-aligned block the stepper walks through one unit at a time (week / month / quarter /
//  half-year), or a user-picked custom start–end range. Both resolve to a DateInterval so the rest
//  of the screen treats them the same.
//

import Foundation

/// The granularity the Insights period stepper moves by. Weeks honor the locale's first weekday;
/// quarters are calendar quarters (Jan–Mar …) and halves are Jan–Jun / Jul–Dec.
enum PeriodUnit: String, CaseIterable, Identifiable {
    case week, month, quarter, halfYear

    var id: String { rawValue }

    /// Name of the unit in the stepper's dropdown.
    var menuLabel: String {
        switch self {
        case .week: String(localized: "Week"); case .month: String(localized: "Month")
        case .quarter: String(localized: "Quarter"); case .halfYear: String(localized: "Half-year")
        }
    }

    /// Small uppercase eyebrow shown over the period value in the stepper pill.
    var eyebrow: String { menuLabel.uppercased() }
}

enum InsightsPeriod: Equatable {
    /// A calendar-aligned block of `unit`, `offset` units back from the one containing today
    /// (0 = current, −1 = previous, …).
    case stepped(unit: PeriodUnit, offset: Int)
    /// A user-picked inclusive day range.
    case custom(start: Date, end: Date)

    var steppedUnit: PeriodUnit? { if case .stepped(let u, _) = self { u } else { nil } }
    var isCustom: Bool { if case .custom = self { true } else { false } }

    /// The half-open [start, end) interval this period covers, in the current calendar.
    var interval: DateInterval {
        let cal = Calendar.current
        switch self {
        case .stepped(let unit, let offset):
            let now = Date.now
            switch unit {
            case .week:
                let base = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
                let start = cal.date(byAdding: .weekOfYear, value: offset, to: base) ?? base
                let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
                return DateInterval(start: start, end: end)
            case .month:
                let base = cal.dateInterval(of: .month, for: now)?.start ?? now
                let start = cal.date(byAdding: .month, value: offset, to: base) ?? base
                let end = cal.date(byAdding: .month, value: 1, to: start) ?? start
                return DateInterval(start: start, end: end)
            case .quarter:
                let c = cal.dateComponents([.year, .month], from: now)
                let firstMonth = ((c.month! - 1) / 3) * 3 + 1
                let base = cal.date(from: DateComponents(year: c.year, month: firstMonth)) ?? now
                let start = cal.date(byAdding: .month, value: offset * 3, to: base) ?? base
                let end = cal.date(byAdding: .month, value: 3, to: start) ?? start
                return DateInterval(start: start, end: end)
            case .halfYear:
                let c = cal.dateComponents([.year, .month], from: now)
                let base = cal.date(from: DateComponents(year: c.year, month: c.month! <= 6 ? 1 : 7)) ?? now
                let start = cal.date(byAdding: .month, value: offset * 6, to: base) ?? base
                let end = cal.date(byAdding: .month, value: 6, to: start) ?? start
                return DateInterval(start: start, end: end)
            }
        case .custom(let s, let e):
            let start = cal.startOfDay(for: min(s, e))
            let last = cal.startOfDay(for: max(s, e))
            let end = cal.date(byAdding: .day, value: 1, to: last) ?? last
            return DateInterval(start: start, end: end)
        }
    }

    /// The equal-length window immediately before this one — powers period-over-period compares
    /// and the trend bars.
    func previous() -> InsightsPeriod {
        switch self {
        case .stepped(let unit, let offset):
            return .stepped(unit: unit, offset: offset - 1)
        case .custom(let s, let e):
            let cal = Calendar.current
            let start = cal.startOfDay(for: min(s, e))
            let last = cal.startOfDay(for: max(s, e))
            let days = cal.dateComponents([.day], from: start, to: last).day ?? 0
            let prevEnd = cal.date(byAdding: .day, value: -1, to: start) ?? start
            let prevStart = cal.date(byAdding: .day, value: -days, to: prevEnd) ?? prevEnd
            return .custom(start: prevStart, end: prevEnd)
        }
    }

    // MARK: - Labels

    /// The stepper's friendly label: relative ("This month", "Last week") near the present,
    /// absolute ("April 2025", "Q2 2026") further out, and a plain date span for weeks and
    /// custom ranges.
    var friendlyLabel: String {
        let cal = Calendar.current
        switch self {
        case .custom(let s, let e):
            return Self.spanLabel(from: s, to: e)
        case .stepped(let unit, let offset):
            let start = interval.start
            switch unit {
            case .week:
                if offset == 0 { return String(localized: "This week") }
                if offset == -1 { return String(localized: "Last week") }
                let last = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
                return Self.spanLabel(from: start, to: last)
            case .month:
                if offset == 0 { return String(localized: "This month") }
                if offset == -1 { return String(localized: "Last month") }
                let f = DateFormatter()
                f.dateFormat = cal.component(.year, from: start) == cal.component(.year, from: .now)
                    ? "LLLL" : "LLLL yyyy"
                return f.string(from: start)
            case .quarter:
                if offset == 0 { return String(localized: "This quarter") }
                if offset == -1 { return String(localized: "Last quarter") }
                return "Q\(Self.quarterOf(start)) \(cal.component(.year, from: start))"
            case .halfYear:
                if offset == 0 { return String(localized: "This half-year") }
                if offset == -1 { return String(localized: "Last half-year") }
                let h = cal.component(.month, from: start) <= 6 ? 1 : 2
                return "H\(h) \(cal.component(.year, from: start))"
            }
        }
    }

    /// Short label under a trend bar for this period.
    var barLabel: String {
        let f = DateFormatter()
        switch self {
        case .custom:
            return DateFormatOption.current.tiny(interval.start)
        case .stepped(let unit, _):
            switch unit {
            case .week: return DateFormatOption.current.tiny(interval.start)
            case .month: f.dateFormat = "MMM"; return f.string(from: interval.start)
            case .quarter: return "Q\(Self.quarterOf(interval.start))"
            case .halfYear:
                let h = Calendar.current.component(.month, from: interval.start) <= 6 ? 1 : 2
                return "H\(h)'\(String(Calendar.current.component(.year, from: interval.start) % 100))"
            }
        }
    }

    /// "this month" / "this week" / … — the caption under the donut total and in empty states.
    var contextNoun: String {
        switch self {
        case .custom: String(localized: "this period")
        case .stepped(let unit, _):
            switch unit {
            case .week: String(localized: "this week"); case .month: String(localized: "this month")
            case .quarter: String(localized: "this quarter"); case .halfYear: String(localized: "this half-year")
            }
        }
    }

    /// "vs last month" / "vs last week" / … — the trend delta pill's comparison caption.
    var compareNoun: String {
        switch self {
        case .custom: String(localized: "vs previous")
        case .stepped(let unit, _):
            switch unit {
            case .week: String(localized: "vs last week"); case .month: String(localized: "vs last month")
            case .quarter: String(localized: "vs last quarter"); case .halfYear: String(localized: "vs last half")
            }
        }
    }

    private static func quarterOf(_ date: Date) -> Int {
        (Calendar.current.component(.month, from: date) - 1) / 3 + 1
    }

    /// "5–11 Jan" style span; appends the year when it isn't the current one, and repeats the
    /// month when the span crosses months ("28 Jan – 3 Feb").
    private static func spanLabel(from start: Date, to end: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatOption.current
        let sameMonth = cal.isDate(start, equalTo: end, toGranularity: .month)
        let currentYear = cal.component(.year, from: end) == cal.component(.year, from: .now)
            && cal.component(.year, from: start) == cal.component(.year, from: .now)
        if fmt == .system {
            let f = DateIntervalFormatter()
            f.dateTemplate = currentYear ? "d MMM" : "d MMM y"
            return f.string(from: start, to: end)
        }
        let short: (Date) -> String = { currentYear ? fmt.short($0) : fmt.shortWithYear($0) }
        // Collapse "5 Jan – 11 Jan" to "5–11 Jan" only for the day-first shape; month-first
        // ("Jan 5") and numeric ("05.01") shapes read wrong when the start loses its month.
        if sameMonth, fmt == .dayMonthYear {
            let day = DateFormatter(); day.dateFormat = "d"
            return "\(day.string(from: start))–\(short(end))"
        }
        return "\(short(start)) – \(short(end))"
    }
}
