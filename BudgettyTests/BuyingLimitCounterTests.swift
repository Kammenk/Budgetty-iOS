//
//  BuyingLimitCounterTests.swift
//  BudgettyTests
//
//  Pins the buying-limit substring counter — a port of Android's BuyingLimitCounterTest. It sums
//  QUANTITY (not rows), ORs across keywords, folds case + Cyrillic, and windows on the pay-cycle month
//  / locale week. These are the rules the card count and the save-time nudge both rely on. A fixed UTC
//  Gregorian calendar keeps the day math independent of the runner's timezone.
//

import Testing
import Foundation
@testable import Budgetty

struct BuyingLimitCounterTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `date` at noon UTC — well inside any day-bounded window.
    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func item(_ name: String, _ quantity: Int, _ y: Int, _ m: Int, _ d: Int) -> CountableItem {
        CountableItem(name: name, quantity: quantity, timestamp: at(y, m, d))
    }

    // MARK: - matches(): substring, case, Cyrillic, OR

    @Test func matchesIsSubstringCaseInsensitive() {
        #expect(BuyingLimitCounter.matches("Coke Zero 500ml", keywords: ["coke"]))
        #expect(BuyingLimitCounter.matches("COCA-COLA", keywords: ["cola"]))
        // "coke" is not a substring of "coca-cola" — only "cola"/"coca" would catch it (honest matcher).
        #expect(!BuyingLimitCounter.matches("Coca-Cola 500ml", keywords: ["coke"]))
    }

    @Test func matchesFoldsCyrillic() {
        #expect(BuyingLimitCounter.matches("Кока-Кола 500мл", keywords: ["кока"]))
        // Uppercase Cyrillic folds to the lowercase keyword (Unicode-aware, no ASCII-only shortcut).
        #expect(BuyingLimitCounter.matches("ЛЮТЕНИЦА 500Г", keywords: ["лютеница"]))
    }

    @Test func matchesOrsAcrossKeywords() {
        let keywords = ["coke", "cola", "fanta"]
        #expect(BuyingLimitCounter.matches("Fanta Orange", keywords: keywords))
        #expect(BuyingLimitCounter.matches("Coke Zero", keywords: keywords))
        #expect(!BuyingLimitCounter.matches("Sparkling water", keywords: keywords))
    }

    @Test func matchesEmptyKeywordsNeverMatch() {
        #expect(!BuyingLimitCounter.matches("anything", keywords: []))
    }

    // MARK: - countInWindow(): sums quantity, ORs, respects the window

    @Test func countSumsQuantityAcrossKeywordsInWindow() {
        let today = at(2026, 2, 15)
        let items = [
            item("Coke Zero", 2, 2026, 2, 10),
            item("Coca-Cola 1L", 3, 2026, 2, 12),
            item("Fanta", 1, 2026, 2, 14),
        ]
        let n = BuyingLimitCounter.count(items, keywords: ["coke", "cola"], timeframe: .monthly,
                                         today: today, startDay: 1, calendar: cal)
        #expect(n == 5)   // 2 via coke + 3 via cola, not rows
    }

    // MARK: - Monthly window: calendar month and pay-cycle month

    @Test func monthlyCalendarMonthBoundaries() {
        let today = at(2026, 2, 15)
        let items = [
            item("Coke", 1, 2026, 1, 31),
            item("Coke", 1, 2026, 2, 1),
            item("Coke", 1, 2026, 2, 28),
            item("Coke", 1, 2026, 3, 1),
        ]
        let n = BuyingLimitCounter.count(items, keywords: ["coke"], timeframe: .monthly,
                                         today: today, startDay: 1, calendar: cal)
        #expect(n == 2)   // only the two rows dated within February count
    }

    @Test func monthlyPayCycleShiftsTheWindow() {
        // Pay day 25: the cycle containing Feb 15 runs Jan 25 to Feb 24.
        let today = at(2026, 2, 15)
        let items = [
            item("Coke", 1, 2026, 1, 24),
            item("Coke", 1, 2026, 1, 25),
            item("Coke", 1, 2026, 2, 24),
            item("Coke", 1, 2026, 2, 26),
        ]
        let n = BuyingLimitCounter.count(items, keywords: ["coke"], timeframe: .monthly,
                                         today: today, startDay: 25, calendar: cal)
        #expect(n == 2)   // Jan 25 and Feb 24 are inside the cycle; Jan 24 and Feb 26 are not
    }

    // MARK: - Weekly window: locale first-day-of-week

    @Test func weeklyBoundariesOnFirstDayOfWeek() {
        // Wed 2026-02-11 with a Monday week start: the window is Feb 9 to Feb 15.
        let today = at(2026, 2, 11)
        let items = [
            item("Coke", 1, 2026, 2, 8),
            item("Coke", 2, 2026, 2, 9),
            item("Coke", 1, 2026, 2, 15),
            item("Coke", 1, 2026, 2, 16),
        ]
        let n = BuyingLimitCounter.count(items, keywords: ["coke"], timeframe: .weekly,
                                         today: today, firstWeekday: 2 /* Monday */, calendar: cal)
        #expect(n == 3)   // 2 on Monday + 1 on Sunday, both inside the week
    }

    @Test func weeklySundayFirstDayShiftsWindow() {
        // With Sunday as the week start, Wed Feb 11's week is Feb 8 (Sun) to Feb 14 (Sat).
        let today = at(2026, 2, 11)
        let items = [
            item("Coke", 1, 2026, 2, 8),
            item("Coke", 1, 2026, 2, 15),
        ]
        let n = BuyingLimitCounter.count(items, keywords: ["coke"], timeframe: .weekly,
                                         today: today, firstWeekday: 1 /* Sunday */, calendar: cal)
        #expect(n == 1)   // Feb 8 falls in this Sunday-week; Feb 15 opens the next one
    }

    // MARK: - nextReset(): the window roll-over date

    @Test func nextResetWeeklyIsStartOfNextWeek() {
        let reset = BuyingLimitCounter.nextReset(.weekly, today: at(2026, 2, 11),
                                                 firstWeekday: 2 /* Monday */, calendar: cal)
        #expect(reset == day(2026, 2, 16))
    }

    @Test func nextResetMonthlyIsNextCycleStart() {
        let reset = BuyingLimitCounter.nextReset(.monthly, today: at(2026, 2, 15),
                                                 startDay: 25, calendar: cal)
        #expect(reset == day(2026, 2, 25))   // cycle Jan 25–Feb 24 rolls over on Feb 25
    }
}
