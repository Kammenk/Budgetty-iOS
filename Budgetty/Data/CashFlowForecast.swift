//
//  CashFlowForecast.swift
//  Budgetty
//
//  Pure day-by-day cash-flow projection + the recurring→events expansion — no SwiftData/SwiftUI deps,
//  so the whole math is unit-testable. Everything is modelled forward from a user-entered balance; it
//  is an estimate, never a bank balance (Budgetty doesn't connect to banks). 1:1 port of Android's
//  `data/forecast/CashFlowForecast.kt` + `ForecastEvents.kt`.
//

import Foundation

/// A dated cash movement in the forecast: positive for income, negative for a bill.
struct CashEvent { let date: Date; let amount: Decimal }

/// One month's projected flows (magnitudes) and the balance it ends on.
struct MonthProjection: Identifiable {
    /// First day of the month, for labelling.
    let month: Date
    let income: Decimal
    let bills: Decimal
    let discretionary: Decimal
    let net: Decimal
    let endBalance: Decimal
    let trough: Decimal
    let troughDate: Date
    let dipsBelowComfort: Bool
    var id: Date { month }
}

/// A point on the projected balance curve.
struct ForecastPoint { let date: Date; let balance: Decimal }

/// The whole projection: the daily balance curve, the overall trough, end balance and per-month rows.
struct ForecastResult {
    let points: [ForecastPoint]
    let startBalance: Decimal
    let endBalance: Decimal
    let endDate: Date
    let trough: Decimal
    let troughDate: Date
    let dipsBelowComfort: Bool
    let months: [MonthProjection]
}

enum CashFlowForecast {

    /// Projects the daily balance from `startBalance` on `today` over `horizonMonths` whole months (the
    /// current month's remaining days plus the following months), applying each dated `events` movement
    /// on its day and spreading `monthlyDiscretionary` evenly across every day (× 12 ÷ 365).
    /// `comfortThreshold` is the "warn me below" line used to flag the trough.
    static func project(startBalance: Decimal, today: Date, horizonMonths: Int, events: [CashEvent],
                        monthlyDiscretionary: Decimal, comfortThreshold: Decimal,
                        calendar cal: Calendar = .current) -> ForecastResult {
        let start = cal.startOfDay(for: today)
        let endDate = endOfMonth(monthsAfter: max(1, horizonMonths) - 1, from: start, cal)
        let dailyDisc = round2(monthlyDiscretionary * 12 / 365)

        var incomeByDay: [Date: Decimal] = [:]
        var billByDay: [Date: Decimal] = [:]
        for e in events {
            let day = cal.startOfDay(for: e.date)
            if day < start || day > endDate { continue }
            if e.amount >= 0 { incomeByDay[day, default: 0] += e.amount }
            else { billByDay[day, default: 0] += -e.amount }
        }

        struct DayRow { let date: Date; let balance: Decimal; let income: Decimal; let bill: Decimal; let disc: Decimal }
        var daily: [DayRow] = []
        var balance = startBalance
        daily.append(DayRow(date: start, balance: balance, income: 0, bill: 0, disc: 0))
        var day = cal.date(byAdding: .day, value: 1, to: start)!
        while day <= endDate {
            let inc = incomeByDay[day] ?? 0
            let bill = billByDay[day] ?? 0
            balance = balance + inc - bill - dailyDisc
            daily.append(DayRow(date: day, balance: balance, income: inc, bill: bill, disc: dailyDisc))
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }

        let troughRow = daily.min { $0.balance < $1.balance } ?? daily[0]

        // Group consecutive days by month, preserving order.
        var months: [MonthProjection] = []
        var bucket: [DayRow] = []
        func flush() {
            guard let first = bucket.first, let last = bucket.last else { return }
            let lowest = bucket.min { $0.balance < $1.balance } ?? first
            let income = round2(bucket.reduce(Decimal.zero) { $0 + $1.income })
            let bills = round2(bucket.reduce(Decimal.zero) { $0 + $1.bill })
            let disc = round2(bucket.reduce(Decimal.zero) { $0 + $1.disc })
            months.append(MonthProjection(
                month: firstOfMonth(first.date, cal), income: income, bills: bills, discretionary: disc,
                net: round2(income - bills - disc), endBalance: last.balance,
                trough: lowest.balance, troughDate: lowest.date,
                dipsBelowComfort: lowest.balance < comfortThreshold))
        }
        for row in daily {
            if let last = bucket.last, !cal.isDate(last.date, equalTo: row.date, toGranularity: .month) { flush(); bucket = [] }
            bucket.append(row)
        }
        flush()

        return ForecastResult(
            points: daily.map { ForecastPoint(date: $0.date, balance: $0.balance) },
            startBalance: startBalance, endBalance: daily.last!.balance, endDate: daily.last!.date,
            trough: troughRow.balance, troughDate: troughRow.date,
            dipsBelowComfort: troughRow.balance < comfortThreshold, months: months)
    }

    /// The projection's last day: the end of the month `horizonMonths - 1` months after `today`. The
    /// caller uses this to bound `toForecastEvents` to the same window `project` applies.
    static func horizonEndDate(today: Date, horizonMonths: Int, calendar cal: Calendar = .current) -> Date {
        endOfMonth(monthsAfter: max(1, horizonMonths) - 1, from: cal.startOfDay(for: today), cal)
    }

    private static func firstOfMonth(_ date: Date, _ cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func endOfMonth(monthsAfter n: Int, from date: Date, _ cal: Calendar) -> Date {
        let first = firstOfMonth(date, cal)
        let targetFirst = cal.date(byAdding: .month, value: n, to: first) ?? first
        let nextFirst = cal.date(byAdding: .month, value: 1, to: targetFirst) ?? targetFirst
        return cal.date(byAdding: .day, value: -1, to: nextFirst) ?? targetFirst
    }

    private static func round2(_ d: Decimal) -> Decimal {
        var result = Decimal(); var value = d
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}

extension Array where Element == Recurring {
    /// Expands recurring income & bills into the dated `CashEvent`s the forecast projects over
    /// `[today, endDate]`: a monthly entry lands on its due-day each month; a weekly entry on each
    /// matching weekday (1 = Monday … 7 = Sunday). Yearly entries (which store no month) and one-offs
    /// don't project forward and are skipped. Income is positive, a bill negative.
    func toForecastEvents(today: Date, endDate: Date, calendar cal: Calendar = .current) -> [CashEvent] {
        let start = cal.startOfDay(for: today)
        let end = cal.startOfDay(for: endDate)
        var events: [CashEvent] = []
        for r in self {
            let signed = r.isIncome ? r.amount : -r.amount
            switch r.cadence {
            case .monthly:
                var monthFirst = cal.date(from: cal.dateComponents([.year, .month], from: start))!
                let lastMonthFirst = cal.date(from: cal.dateComponents([.year, .month], from: end))!
                while monthFirst <= lastMonthFirst {
                    let daysInMonth = cal.range(of: .day, in: .month, for: monthFirst)?.count ?? 28
                    let dom = Swift.min(Swift.max(r.dueDay, 1), daysInMonth)
                    if let date = cal.date(byAdding: .day, value: dom - 1, to: monthFirst), date >= start, date <= end {
                        events.append(CashEvent(date: date, amount: signed))
                    }
                    monthFirst = cal.date(byAdding: .month, value: 1, to: monthFirst)!
                }
            case .weekly:
                let target = Swift.min(Swift.max(r.dueDay, 1), 7)   // 1 = Monday … 7 = Sunday
                var date = start
                while date <= end {
                    let iso = (cal.component(.weekday, from: date) + 5) % 7 + 1   // Sun..Sat → Mon=1..Sun=7
                    if iso == target { events.append(CashEvent(date: date, amount: signed)) }
                    date = cal.date(byAdding: .day, value: 1, to: date)!
                }
            case .yearly, .once:
                break   // yearly stores no month; once is a past one-off — neither projects forward.
            }
        }
        return events
    }
}
