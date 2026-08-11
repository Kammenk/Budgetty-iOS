//
//  RecurringPaidTests.swift
//  BudgettyTests
//
//  `isPaidThisCycle` derives "paid" from the reused `lastPosted` timestamp falling inside the bill's
//  current occurrence window, so it resets on its own when the next occurrence begins. A direct port
//  of Android's RecurringPaidTest. A fixed UTC Gregorian calendar keeps the day math timezone-independent.
//

import Testing
import Foundation
@testable import Budgetty

struct RecurringPaidTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let today = { () -> DateComponents in DateComponents(year: 2026, month: 7, day: 25) }()

    /// Noon on the given day, so a timestamp sits comfortably inside its day's bounds.
    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var todayDate: Date { cal.date(from: today)! }

    private func bill(_ cadence: Cadence, paidOn lastPosted: Date?) -> Recurring {
        let r = Recurring(label: "Rent", amount: 800, isIncome: false, cadence: cadence)
        r.lastPosted = lastPosted
        return r
    }

    @Test func neverPostedIsNotPaid() {
        #expect(!bill(.monthly, paidOn: nil).isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func monthlyPaidInsideTheCurrentPayCycleMonthIsPaid() {
        let b = bill(.monthly, paidOn: at(2026, 7, 10))
        #expect(b.isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func monthlyPaidInAPreviousMonthHasAutoResetToUnpaid() {
        let b = bill(.monthly, paidOn: at(2026, 6, 10))
        #expect(!b.isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func payCycleMonthShiftsThePaidWindow() {
        // With startDay 15, today (Jul 25) sits in the Jul 15 – Aug 14 cycle, so a Jul 5 payment
        // belongs to the PREVIOUS cycle and no longer counts as paid.
        let b = bill(.monthly, paidOn: at(2026, 7, 5))
        #expect(b.isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
        #expect(!b.isPaidThisCycle(todayDate, startDay: 15, calendar: cal))
    }

    @Test func weeklyPaidThisWeekIsPaidLastWeekIsNot() {
        #expect(bill(.weekly, paidOn: at(2026, 7, 25)).isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
        #expect(!bill(.weekly, paidOn: at(2026, 7, 18)).isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func oneTimeEntryStaysPaidOnceMarked() {
        let b = bill(.once, paidOn: at(2020, 1, 1))
        #expect(b.isPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    // MARK: - Autopay: derived "effectively paid" once the due day passes (no lastPosted stamp)

    private func autoBill(_ cadence: Cadence, dueDay: Int, autoPay: Bool = true) -> Recurring {
        let r = Recurring(label: "Rent", amount: 800, isIncome: false, cadence: cadence, dueDay: dueDay)
        r.autoPay = autoPay
        return r
    }

    @Test func monthlyDueDayPassedThisCycleUpcomingNotYet() {
        // today = Jul 25; the Jul 10 due day has passed, the Jul 28 one has not.
        #expect(autoBill(.monthly, dueDay: 10).isDuePassedThisCycle(todayDate, startDay: 1, calendar: cal))
        #expect(!autoBill(.monthly, dueDay: 28).isDuePassedThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func weeklyMondayHasPassedByAnyLaterDayOfItsWeek() {
        #expect(autoBill(.weekly, dueDay: 1).isDuePassedThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func yearlyAndOnceNeverAutoMark() {
        #expect(!autoBill(.yearly, dueDay: 1).isDuePassedThisCycle(todayDate, startDay: 1, calendar: cal))
        #expect(!autoBill(.once, dueDay: 1).isDuePassedThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func autopayFillsPaidOnceTheDueDayPasses() {
        #expect(autoBill(.monthly, dueDay: 10).isEffectivelyPaidThisCycle(todayDate, startDay: 1, calendar: cal))
        #expect(!autoBill(.monthly, dueDay: 28).isEffectivelyPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func autopayOffLeavesItToTheManualStamp() {
        let b = autoBill(.monthly, dueDay: 10, autoPay: false)
        #expect(!b.isEffectivelyPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    @Test func aManualPaymentCountsEvenBeforeTheAutopayDueDay() {
        let b = autoBill(.monthly, dueDay: 28)
        b.lastPosted = at(2026, 7, 10)
        #expect(b.isEffectivelyPaidThisCycle(todayDate, startDay: 1, calendar: cal))
    }

    // MARK: - Autopay eligibility: monthly/weekly bills only (fixes the stuck "Auto" chip)

    @Test func autoPayEligibleForMonthlyAndWeeklyBillsOnly() {
        func r(_ cadence: Cadence, income: Bool = false) -> Recurring {
            Recurring(label: "x", amount: 10, isIncome: income, cadence: cadence)
        }
        #expect(r(.monthly).autoPayEligible)
        #expect(r(.weekly).autoPayEligible)
        #expect(!r(.yearly).autoPayEligible)
        #expect(!r(.once).autoPayEligible)
        #expect(!r(.monthly, income: true).autoPayEligible)   // income never autopays
    }

    @Test func isAutoPayActiveRequiresToggleOnAndEligibleCadence() {
        #expect(autoBill(.monthly, dueDay: 1).isAutoPayActive)
        #expect(autoBill(.weekly, dueDay: 1).isAutoPayActive)
        #expect(!autoBill(.monthly, dueDay: 1, autoPay: false).isAutoPayActive)
        // The bug: a yearly/one-off bill that still carries autoPay must NOT read as auto-managed
        // (otherwise its Budget row shows a permanent "Auto" chip with no way to mark it paid).
        #expect(!autoBill(.yearly, dueDay: 1).isAutoPayActive)
        #expect(!autoBill(.once, dueDay: 1).isAutoPayActive)
    }
}
