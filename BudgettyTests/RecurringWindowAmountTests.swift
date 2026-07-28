//
//  RecurringWindowAmountTests.swift
//  BudgettyTests
//
//  `windowAmount` scales a recurring entry to a period, clipped to the month it was added so a
//  just-added salary isn't projected backward (Android's back-projection fix). Fixed UTC calendar.
//  Amounts are compared as Double: Foundation's `Decimal ==` treats two multiplication-derived but
//  numerically-equal values (e.g. 400×3 vs the computed 1200) as unequal, which the app never relies
//  on — it sums and formats these, never exact-compares them.
//

import Testing
import Foundation
@testable import Budgetty

struct RecurringWindowAmountTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func window(_ from: Date, _ to: Date) -> DateInterval { DateInterval(start: from, end: to) }

    private func entry(_ cadence: Cadence, _ amount: Decimal, created: Date, isIncome: Bool = true) -> Recurring {
        Recurring(label: "Salary", amount: amount, isIncome: isIncome, cadence: cadence, createdAt: created)
    }

    private func amount(_ r: Recurring, _ from: Date, _ to: Date) -> Double {
        (r.windowAmount(window(from, to), calendar: cal) as NSDecimalNumber).doubleValue
    }

    @Test func monthlyScalesByWholeMonths() {
        // Apr 1 – Jul 1 = three whole months; created back in January, so all three count.
        let r = entry(.monthly, 400, created: day(2026, 1, 1))
        #expect(amount(r, day(2026, 4, 1), day(2026, 7, 1)) == 1200)
    }

    @Test func recurringIsNotProjectedBeforeTheMonthItWasAdded() {
        // Same 3-month window, but the salary was added mid-May: only May and June count (not April).
        let r = entry(.monthly, 400, created: day(2026, 5, 15))
        #expect(amount(r, day(2026, 4, 1), day(2026, 7, 1)) == 800)
    }

    @Test func oneTimeCountsOnlyIfAddedInsideTheWindow() {
        let r = entry(.once, 1000, created: day(2026, 5, 10))
        #expect(amount(r, day(2026, 4, 1), day(2026, 7, 1)) == 1000)
        #expect(amount(r, day(2026, 1, 1), day(2026, 4, 1)) == 0)
    }

    @Test func partialWindowScalesByActiveDays() {
        // A 10-day custom window (not whole months) scales the monthly rate by days / 30.4375.
        let r = entry(.monthly, 300, created: day(2026, 1, 1))
        #expect(abs(amount(r, day(2026, 6, 5), day(2026, 6, 15)) - (300.0 * 10.0 / 30.4375)) < 0.01)
    }

    @Test func entryAddedAfterTheWindowContributesNothing() {
        let r = entry(.monthly, 400, created: day(2026, 9, 1))
        #expect(amount(r, day(2026, 4, 1), day(2026, 7, 1)) == 0)
    }
}
