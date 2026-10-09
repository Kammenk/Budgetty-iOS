//
//  TripTagTests.swift
//  BudgettyTests
//
//  The trip tag is the normalized name stamped with the start year — but a name that already ends in
//  that year must not be stamped twice ("Lisbon 2026" → `lisbon-2026`, device-test bug 9). Same rule
//  as Android's `TripsViewModel.tripTag`. A fixed UTC calendar keeps the year independent of the host.
//

import Testing
import Foundation
@testable import Budgetty

struct TripTagTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func jan(_ year: Int) -> Date { cal.date(from: DateComponents(year: year, month: 1, day: 15))! }

    @Test func plainNameGetsTheStartYear() {
        #expect(TripOps.tripTag("Lisbon", jan(2026), calendar: cal) == "lisbon-2026")
        #expect(TripOps.tripTag("Work Trip", jan(2027), calendar: cal) == "work-trip-2027")
    }

    @Test func nameAlreadyEndingInThatYearIsNotStampedTwice() {
        #expect(TripOps.tripTag("Lisbon 2026", jan(2026), calendar: cal) == "lisbon-2026")
        #expect(TripOps.tripTag("#Lisbon-2026", jan(2026), calendar: cal) == "lisbon-2026")
    }

    @Test func aDifferentTrailingYearOrNumberStillGetsTheStartYear() {
        #expect(TripOps.tripTag("Lisbon 2025", jan(2026), calendar: cal) == "lisbon-2025-2026")
        #expect(TripOps.tripTag("Lisbon12026", jan(2026), calendar: cal) == "lisbon12026-2026")
        // Only a whole "-YYYY" suffix counts — a bare year name has no hyphen before it.
        #expect(TripOps.tripTag("2026", jan(2026), calendar: cal) == "2026-2026")
    }

    @Test func blankNameFallsBackToTrip() {
        #expect(TripOps.tripTag("  ##  ", jan(2026), calendar: cal) == "trip-2026")
    }
}
