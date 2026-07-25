//
//  PayCycleTests.swift
//  BudgettyTests
//
//  The pay-cycle "financial month" resolver (Account → "Month starts on"). A direct port of
//  Android's PayCycleTest: paging, the before/after-pay-day boundary, and short-month clamping.
//  A fixed UTC Gregorian calendar keeps the day math independent of the runner's timezone.
//

import Testing
import Foundation
@testable import Budgetty

struct PayCycleTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func startDay1IsTheOrdinaryCalendarMonth() {
        let (start, end) = PayCycle.month(day(2026, 7, 15), startDay: 1, calendar: cal)
        #expect(start == day(2026, 7, 1))
        #expect(end == day(2026, 7, 31))
    }

    @Test func onThePayDayTheCurrentCycleStartsThatDay() {
        let (start, end) = PayCycle.month(day(2026, 7, 25), startDay: 25, calendar: cal)
        #expect(start == day(2026, 7, 25))
        #expect(end == day(2026, 8, 24))
    }

    @Test func beforeThePayDayTodaySitsInThePreviousCycle() {
        let (start, end) = PayCycle.month(day(2026, 7, 10), startDay: 25, calendar: cal)
        #expect(start == day(2026, 6, 25))
        #expect(end == day(2026, 7, 24))
    }

    @Test func previousOffsetStepsBackOneWholeCycle() {
        let (start, end) = PayCycle.month(day(2026, 7, 25), startDay: 25, offset: -1, calendar: cal)
        #expect(start == day(2026, 6, 25))
        #expect(end == day(2026, 7, 24))
    }

    @Test func a31stPayDayClampsToTheLastDayOfAShortMonth() {
        // Viewing mid-March with a 31st pay day: the cycle that contains today starts on Feb's last
        // day (28th in 2026, a non-leap year) and ends the day before March's 31st.
        let (start, end) = PayCycle.month(day(2026, 3, 15), startDay: 31, calendar: cal)
        #expect(start == day(2026, 2, 28))
        #expect(end == day(2026, 3, 30))
    }

    @Test func monthIntervalRunsFromStartToNextCycleStart() {
        let interval = PayCycle.monthInterval(day(2026, 7, 15), startDay: 1, calendar: cal)
        #expect(interval.start == day(2026, 7, 1))
        #expect(interval.end == day(2026, 8, 1))            // next-cycle start bounds the window
        #expect(interval.contains(day(2026, 7, 31)))        // last day is inside
        #expect(!interval.contains(day(2026, 6, 30)))       // the day before the cycle is not
    }
}
