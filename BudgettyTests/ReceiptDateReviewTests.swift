//
//  ReceiptDateReviewTests.swift
//  BudgettyTests
//
//  Pins `ReceiptDateReview.needsReview` — the Swift port of Android's `receiptDateNeedsReview`
//  (ReceiptDateReviewTest): a scanned receipt date is flagged for confirmation when it can't plausibly
//  be a recent purchase (a future date, or one older than `windowDays`), so a misread month or year is
//  caught before saving. The two "flagged" cases are the tester receipts that regressed: 08.09.2026
//  misread as 8 Apr 2026 (wrong month, right year — which the earlier year-only check missed) and
//  01.09.2026 misread as 1 Sep 2020 (wrong year).
//
//  A fixed UTC Gregorian calendar keeps the day math independent of the runner's timezone, matching the
//  Android test's explicit `LocalDate`s.
//

import Testing
import Foundation
@testable import Budgetty

struct ReceiptDateReviewTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    /// `needsReview` for a receipt dated (y, m, d), scanned on 2026-09-09. Window edge is 2026-07-26.
    private func needsReview(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        ReceiptDateReview.needsReview(day(y, m, d), today: day(2026, 9, 9), calendar: cal)
    }

    @Test func todayIsNotFlagged() {
        #expect(!needsReview(2026, 9, 9))
    }

    @Test func recentWithinWindowIsNotFlagged() {
        #expect(!needsReview(2026, 8, 20))
    }

    @Test func farEdgeOfWindowIsStillAccepted() {
        #expect(!needsReview(2026, 7, 26)) // today − 45 days
    }

    @Test func justPastWindowIsFlagged() {
        #expect(needsReview(2026, 7, 25)) // today − 46 days
    }

    @Test func wrongMonthWithinCurrentYearIsFlagged() {
        #expect(needsReview(2026, 4, 8)) // 08.09.2026 misread as 8 Apr 2026
    }

    @Test func wrongYearIsFlagged() {
        #expect(needsReview(2020, 9, 1)) // 01.09.2026 misread as 1 Sep 2020
    }

    @Test func futureDateIsFlagged() {
        #expect(needsReview(2026, 12, 25))
    }
}
