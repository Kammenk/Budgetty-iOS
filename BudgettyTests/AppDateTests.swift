//
//  AppDateTests.swift
//  BudgettyTests
//
//  The Date-format preference. Only the digit-based (locale-independent) shapes are asserted here —
//  the `.system` and month-name variants depend on the runner's locale and aren't pinned.
//

import Testing
import Foundation
@testable import Budgetty

struct AppDateTests {
    /// 5 June 2026, built at local noon so no timezone offset can push it across a day boundary
    /// (construction and formatting both use the default calendar/timezone).
    private var fifthOfJune: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12))!
    }

    @Test func numericFormatsAreZeroPaddedDotted() {
        #expect(DateFormatOption.numeric.short(fifthOfJune) == "05.06")
        #expect(DateFormatOption.numeric.long(fifthOfJune) == "05.06.2026")
        #expect(DateFormatOption.numeric.shortWithYear(fifthOfJune) == "05.06.2026")
    }

    @Test func tinyEncodesDayMonthOrdering() {
        // day=5, month=6 disambiguates the ordering between the options.
        #expect(DateFormatOption.numeric.tiny(fifthOfJune) == "5.6")
        #expect(DateFormatOption.dayMonthYear.tiny(fifthOfJune) == "5/6")
        #expect(DateFormatOption.monthDayYear.tiny(fifthOfJune) == "6/5")
    }
}
