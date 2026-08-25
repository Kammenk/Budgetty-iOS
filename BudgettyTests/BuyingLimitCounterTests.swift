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

    // MARK: - closedWindows(): the last N CLOSED windows, most-recent first, each (count, hasData)
    // This single derivation feeds both the §4.3 history strip and StreakEngine.limitStreak.

    @Test func closedWindowsMonthlyMetMissedNoData() {
        // Today Apr 15; closed months (idx 0..3) = Mar, Feb, Jan, Dec 2025.
        let today = at(2026, 4, 15)
        let items = [
            item("Coke", 2, 2026, 3, 10),   // March: 2 coke → met vs cap 2
            item("Milk", 1, 2026, 3, 2),    // March: a receipt (no-match) — still hasData
            item("Coke", 5, 2026, 1, 20),   // Jan: 5 coke → over cap → not-met
        ]
        let w = BuyingLimitCounter.closedWindows(items, keywords: ["coke"], timeframe: .monthly,
                                                 windowCount: 4, today: today, startDay: 1, calendar: cal)
        #expect(w.count == 4)
        #expect(w[0].count == 2 && w[0].hasData)      // Mar: 2 matched, had data
        #expect(w[1].count == 0 && !w[1].hasData)     // Feb: empty → no-data
        #expect(w[2].count == 5 && w[2].hasData)      // Jan: 5 matched, had data
        #expect(w[3].count == 0 && !w[3].hasData)     // Dec: empty → no-data
    }

    @Test func closedWindowsReceiptButNoMatchIsDataNotMiss() {
        // A closed window that held a receipt but nothing matching is (0, hasData=true) — the engine
        // scores it MET (count 0 ≤ cap), never NO_DATA. This distinction must survive the derivation.
        let today = at(2026, 4, 15)
        let items = [item("Bread", 1, 2026, 3, 10)]
        let w = BuyingLimitCounter.closedWindows(items, keywords: ["coke"], timeframe: .monthly,
                                                 windowCount: 1, today: today, startDay: 1, calendar: cal)
        #expect(w[0].count == 0 && w[0].hasData)
    }

    @Test func closedWindowsWeeklyMostRecentFirst() {
        // Today Wed Apr 15 (Monday weeks): closed weeks idx0 = Apr 6–12, idx1 = Mar 30–Apr 5.
        let today = at(2026, 4, 15)
        let items = [
            item("Coke", 1, 2026, 4, 8),    // last full week
            item("Coke", 3, 2026, 3, 31),   // the week before
        ]
        let w = BuyingLimitCounter.closedWindows(items, keywords: ["coke"], timeframe: .weekly,
                                                 windowCount: 2, today: today,
                                                 firstWeekday: 2 /* Monday */, calendar: cal)
        #expect(w[0].count == 1 && w[0].hasData)
        #expect(w[1].count == 3 && w[1].hasData)
    }
}
