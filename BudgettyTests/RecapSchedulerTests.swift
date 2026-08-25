//
//  RecapSchedulerTests.swift
//  BudgettyTests
//
//  Pins the end-of-period recap trigger — the Swift port of Android's `RecapSchedulerTest`: due/not-due
//  per frequency against the last-shown keys and a period boundary (monthly via the pay-cycle, weekly
//  via the first-day-of-week), the both-due-same-open rule, and the first-run / not-enough-data guard.
//  A fixed UTC Gregorian calendar with a Monday first weekday keeps the day math independent of the
//  runner's timezone/locale, matching the Android test's explicit `monday`.
//

import Testing
import Foundation
@testable import Budgetty

struct RecapSchedulerTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday, matching the Android test's DayOfWeek.MONDAY
        return c
    }()

    /// Monday, as a `Calendar` weekday index (1 = Sunday … 7 = Saturday).
    private let monday = 2

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // ── Period-id helpers ────────────────────────────────────────────────────────

    @Test func justClosedMonthId_calendarCycle_isPreviousCalendarMonth() {
        // 1 Aug, calendar cycle → the month that just closed is July.
        #expect(RecapScheduler.justClosedMonthId(day(2026, 8, 1), startDay: 1, calendar: cal) == "2026-07")
        // Mid-August is still inside August's cycle → July is still the just-closed one.
        #expect(RecapScheduler.justClosedMonthId(day(2026, 8, 20), startDay: 1, calendar: cal) == "2026-07")
    }

    @Test func justClosedMonthId_payCycle_followsStartDay() {
        // Pay day = 25th. On 24 Aug we're still in the cycle that opened 25 Jul, so the just-closed
        // cycle is the one that opened 25 Jun ("2026-06").
        #expect(RecapScheduler.justClosedMonthId(day(2026, 8, 24), startDay: 25, calendar: cal) == "2026-06")
        // On 25 Aug the new cycle opens, so the just-closed cycle is the one that opened 25 Jul.
        #expect(RecapScheduler.justClosedMonthId(day(2026, 8, 25), startDay: 25, calendar: cal) == "2026-07")
    }

    @Test func justClosedWeekId_isPreviousWeekStart() {
        // Wed 22 Jul 2026 → this week started Mon 20 Jul → just-closed week started Mon 13 Jul.
        #expect(RecapScheduler.justClosedWeekId(day(2026, 7, 22), firstWeekday: monday, calendar: cal) == "2026-07-13")
        // Sunday belongs to the week that started the previous Monday (13 Jul) → just-closed = 6 Jul.
        #expect(RecapScheduler.justClosedWeekId(day(2026, 7, 19), firstWeekday: monday, calendar: cal) == "2026-07-06")
    }

    // ── Monthly cadence ──────────────────────────────────────────────────────────

    @Test func monthly_due_whenJustClosedMonthNotYetShown() {
        let due = RecapScheduler.due(
            enabled: true, frequency: .monthly, lastShownWeek: "", lastShownMonth: "2026-06",
            today: day(2026, 8, 1), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .monthly)
        #expect(due?.markMonth == "2026-07")
        // Weekly isn't part of MONTHLY frequency, so no week is marked.
        #expect(due?.markWeek == nil)
    }

    @Test func monthly_notDue_whenAlreadyShownThisCycle() {
        let due = RecapScheduler.due(
            enabled: true, frequency: .monthly, lastShownWeek: "", lastShownMonth: "2026-07",
            today: day(2026, 8, 10), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due == nil)
    }

    @Test func monthly_frequency_neverFiresWeekly() {
        // A new week has closed, but a Monthly-only user gets no weekly recap. The month that closed
        // (July, via the 1 Aug boundary) is already stamped, so nothing is due at all.
        let due = RecapScheduler.due(
            enabled: true, frequency: .monthly, lastShownWeek: "", lastShownMonth: "2026-07",
            today: day(2026, 8, 5), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due == nil)
    }

    // ── Weekly cadence ───────────────────────────────────────────────────────────

    @Test func weekly_due_whenJustClosedWeekNotYetShown() {
        let due = RecapScheduler.due(
            enabled: true, frequency: .weekly, lastShownWeek: "2026-07-06", lastShownMonth: "",
            today: day(2026, 7, 22), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .weekly)
        #expect(due?.markWeek == "2026-07-13")
        #expect(due?.markMonth == nil)
    }

    @Test func weekly_notDue_whenAlreadyShownThisWeek() {
        let due = RecapScheduler.due(
            enabled: true, frequency: .weekly, lastShownWeek: "2026-07-13", lastShownMonth: "",
            today: day(2026, 7, 22), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due == nil)
    }

    @Test func weekly_frequency_neverFiresMonthly() {
        // A month closed (1 Aug boundary), but a Weekly-only user gets no monthly recap. The just-closed
        // week as of 5 Aug (Mon 27 Jul) is already stamped, so nothing is due.
        let due = RecapScheduler.due(
            enabled: true, frequency: .weekly, lastShownWeek: "2026-07-27", lastShownMonth: "",
            today: day(2026, 8, 5), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due == nil)
    }

    // ── Both cadences ────────────────────────────────────────────────────────────

    @Test func both_dueSameOpen_showsMonthlyAndMarksBoth() {
        // 1 Aug: a month AND a week have closed and neither is shown → show Monthly, mark both.
        let due = RecapScheduler.due(
            enabled: true, frequency: .both, lastShownWeek: "2026-07-06", lastShownMonth: "2026-06",
            today: day(2026, 8, 1), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .monthly)
        #expect(due?.markMonth == "2026-07")
        // The just-closed week as of 1 Aug (Sat) started Mon 20 Jul.
        #expect(due?.markWeek == "2026-07-20")
    }

    @Test func both_onlyWeeklyDue_showsWeekly() {
        // The just-closed month (June, as of 22 Jul) is already shown, but a fresh week has closed → weekly only.
        let due = RecapScheduler.due(
            enabled: true, frequency: .both, lastShownWeek: "2026-07-06", lastShownMonth: "2026-06",
            today: day(2026, 7, 22), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .weekly)
        #expect(due?.markWeek == "2026-07-13")
        #expect(due?.markMonth == nil)
    }

    @Test func both_onlyMonthlyDue_marksOnlyMonth() {
        // Week already shown, month fresh → monthly only, week not re-marked.
        let due = RecapScheduler.due(
            enabled: true, frequency: .both, lastShownWeek: "2026-07-20", lastShownMonth: "2026-06",
            today: day(2026, 8, 1), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .monthly)
        #expect(due?.markMonth == "2026-07")
        #expect(due?.markWeek == nil)
    }

    // ── Enabled flag ─────────────────────────────────────────────────────────────

    @Test func disabled_neverDue() {
        let due = RecapScheduler.due(
            enabled: false, frequency: .both, lastShownWeek: "", lastShownMonth: "",
            today: day(2026, 8, 1), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due == nil)
    }

    @Test func freshInstall_bothEmpty_isDue_soTheGuardCanSkipAndStamp() {
        // Empty last-shown keys mean the current just-closed periods look "due"; the data guard then
        // skips a first-run user and stamps them, so no empty recap ever shows.
        let due = RecapScheduler.due(
            enabled: true, frequency: .monthly, lastShownWeek: "", lastShownMonth: "",
            today: day(2026, 8, 1), startDay: 1, firstWeekday: monday, calendar: cal)
        #expect(due?.show == .monthly)
        #expect(due?.markMonth == "2026-07")
    }

    // ── Data guard ───────────────────────────────────────────────────────────────

    @Test func guard_underReceiptFloor_skips() {
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: 4, periodReceipts: 4,
                                        periodHasSpend: true, priorPeriodHasSpend: true) == .skip)
    }

    @Test func guard_periodHadNoSpend_skips() {
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: 30, periodReceipts: 12,
                                        periodHasSpend: false, priorPeriodHasSpend: true) == .skip)
    }

    @Test func guard_noPriorPeriod_showsPartial() {
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: 8, periodReceipts: 8,
                                        periodHasSpend: true, priorPeriodHasSpend: false)
                == .show(withComparison: false))
    }

    @Test func guard_enoughDataWithPrior_showsFull() {
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: 40, periodReceipts: 15,
                                        periodHasSpend: true, priorPeriodHasSpend: true)
                == .show(withComparison: true))
    }

    @Test func guard_floorMatchesWellbeing() {
        // Exactly at the floor is enough (5 = minReceipts).
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: RecapDataGuard.minReceipts,
                                        periodReceipts: 5, periodHasSpend: true, priorPeriodHasSpend: true)
                == .show(withComparison: true))
    }

    // ── Weekly data floor (§1.2) ─────────────────────────────────────────────────

    @Test func guard_weekly_underWeekFloor_skips_evenWithLifetimeData() {
        // Clears the lifetime floor and had spend, but only 2 receipts fell in the week → hollow, skip.
        #expect(RecapDataGuard.evaluate(kind: .weekly, totalReceipts: 40,
                                        periodReceipts: RecapDataGuard.minWeekReceipts - 1,
                                        periodHasSpend: true, priorPeriodHasSpend: true) == .skip)
    }

    @Test func guard_weekly_atWeekFloor_shows() {
        #expect(RecapDataGuard.evaluate(kind: .weekly, totalReceipts: 40,
                                        periodReceipts: RecapDataGuard.minWeekReceipts,
                                        periodHasSpend: true, priorPeriodHasSpend: true)
                == .show(withComparison: true))
    }

    @Test func guard_monthly_ignoresWeekFloor() {
        // The same low period-receipt count that skips a weekly recap still shows the monthly report card.
        #expect(RecapDataGuard.evaluate(kind: .monthly, totalReceipts: 40, periodReceipts: 1,
                                        periodHasSpend: true, priorPeriodHasSpend: true)
                == .show(withComparison: true))
    }

    @Test func guard_weekly_belowLifetimeFloor_skips_regardlessOfWeekCount() {
        #expect(RecapDataGuard.evaluate(kind: .weekly, totalReceipts: RecapDataGuard.minReceipts - 1,
                                        periodReceipts: 10, periodHasSpend: true, priorPeriodHasSpend: true)
                == .skip)
    }
}
