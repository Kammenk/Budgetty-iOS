//
//  BuyingLimitCounter.swift
//  Budgetty
//
//  The keyword purchase-cap matcher and counter — a 1:1 port of Android's `BuyingLimitCounter`. Pure
//  (no SwiftData / SwiftUI) so it unit-tests off-screen and the card count and the save-time nudge run
//  through the exact same rule, guaranteeing they always agree.
//
//  The match is a NEW substring matcher — deliberately not CategoryRule (whole-name exact match): a
//  limit's keywords match anywhere inside an item name (so "coke" catches "Coca-Cola 500ml" and "Coke
//  Zero"), multiple keywords OR into one counter (the same product prints under many names), and the
//  counter sums **quantity** within the current window. All folding is trim + lowercased (Unicode-
//  aware, so Cyrillic folds too); there is no diacritic stripping.
//
//  Windows follow the rest of the app: MONTHLY on the pay-cycle month (`PayCycle`), WEEKLY on the
//  locale's first day of week. Line items are windowed by `createdAt` — the timestamp Home/Insights
//  already filter and group by on iOS — so a limit's "this month" matches what the user sees elsewhere.
//

import Foundation

/// A single purchased line reduced to what a buying-limit needs: the item `name` as printed, its
/// `quantity`, and the timestamp it's windowed by (`LineItem.createdAt`). Kept separate from the
/// SwiftData `@Model` so the counting logic stays pure and testable.
struct CountableItem {
    let name: String
    let quantity: Int
    let timestamp: Date

    init(name: String, quantity: Int, timestamp: Date) {
        self.name = name
        self.quantity = quantity
        self.timestamp = timestamp
    }
}

enum BuyingLimitCounter {

    /// The canonical match key for `raw`: trimmed + lower-cased (Unicode-aware).
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// True when `rawName`'s normalized form contains ANY of `keywords` (expected pre-normalized, as
    /// stored). Substring, case- and Cyrillic-insensitive. Blank keywords are ignored.
    static func matches(_ rawName: String, keywords: [String]) -> Bool {
        if keywords.isEmpty { return false }
        let name = normalize(rawName)
        return keywords.contains { !$0.isEmpty && name.contains($0) }
    }

    /// Σ `quantity` of `items` whose name matches any of `keywords` AND whose timestamp falls within
    /// `window`. This is the count "bought" against a limit.
    static func countInWindow(_ items: [CountableItem], keywords: [String], window: DateInterval) -> Int {
        items.reduce(0) { total, item in
            guard window.contains(item.timestamp), matches(item.name, keywords: keywords) else { return total }
            return total + item.quantity
        }
    }

    /// The current `[start, nextStart)` window for `timeframe` as of `today`:
    ///  - `.monthly`: the user's pay-cycle month (`PayCycle`, anchored on `startDay`).
    ///  - `.weekly`: the week containing `today`, starting on the locale's `firstWeekday`.
    static func window(_ timeframe: BuyingLimitTimeframe,
                       today: Date = .now,
                       startDay: Int = PayCycle.startDay,
                       firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                       calendar: Calendar = .current) -> DateInterval {
        switch timeframe {
        case .monthly:
            return PayCycle.monthInterval(today, startDay: startDay, calendar: calendar)
        case .weekly:
            var cal = calendar
            cal.firstWeekday = firstWeekday
            // [weekStart 00:00, nextWeekStart 00:00): the 7-day span containing today, anchored on
            // the locale's first weekday — matches Android's previousOrSame(firstDayOfWeek) span.
            return cal.dateInterval(of: .weekOfYear, for: today)
                ?? DateInterval(start: cal.startOfDay(for: today), duration: 7 * 86_400)
        }
    }

    /// The CLOSED `[start, nextStart)` window for `timeframe`, `closedIndex` periods back: index 0 = the
    /// most recent closed window (last week / last pay-cycle month), increasing into the past. The
    /// current OPEN window is `window(_:)`; this is only the finished ones. Mirrors Android's `closedWindow`.
    static func closedWindow(_ timeframe: BuyingLimitTimeframe,
                             closedIndex: Int,
                             today: Date = .now,
                             startDay: Int = PayCycle.startDay,
                             firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                             calendar: Calendar = .current) -> DateInterval {
        switch timeframe {
        case .monthly:
            return PayCycle.monthInterval(today, startDay: startDay,
                                          offset: -(closedIndex + 1), calendar: calendar)
        case .weekly:
            // The week `closedIndex + 1` weeks before the one containing `today`; adding weeks is
            // firstWeekday-independent, so shift then resolve the week span with `window(_:)`.
            let shifted = calendar.date(byAdding: .weekOfYear, value: -(closedIndex + 1), to: today) ?? today
            return window(.weekly, today: shifted, firstWeekday: firstWeekday, calendar: calendar)
        }
    }

    /// The last `windowCount` CLOSED `timeframe` windows as `LimitWindow`s, MOST-RECENT FIRST (index 0 =
    /// the last closed window). Each carries the matched quantity in that window and whether the window
    /// held ANY receipts at all (`hasData` — any item, not just matching ones — so an empty window reads
    /// as "no data", never a met window). A single derivation feeds BOTH the §4.3 history strip and
    /// `StreakEngine.limitStreak`, so the two can never disagree. Pure; mirrors Android's `closedWindows`.
    static func closedWindows(_ allItems: [CountableItem],
                              keywords: [String],
                              timeframe: BuyingLimitTimeframe,
                              windowCount: Int,
                              today: Date = .now,
                              startDay: Int = PayCycle.startDay,
                              firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                              calendar: Calendar = .current) -> [LimitWindow] {
        (0..<max(windowCount, 0)).map { idx in
            let w = closedWindow(timeframe, closedIndex: idx, today: today, startDay: startDay,
                                 firstWeekday: firstWeekday, calendar: calendar)
            return LimitWindow(count: countInWindow(allItems, keywords: keywords, window: w),
                               hasData: allItems.contains { w.contains($0.timestamp) })
        }
    }

    /// Convenience: the count bought against `timeframe`'s current window.
    static func count(_ items: [CountableItem], keywords: [String], timeframe: BuyingLimitTimeframe,
                      today: Date = .now,
                      startDay: Int = PayCycle.startDay,
                      firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                      calendar: Calendar = .current) -> Int {
        countInWindow(items, keywords: keywords,
                      window: window(timeframe, today: today, startDay: startDay,
                                     firstWeekday: firstWeekday, calendar: calendar))
    }

    /// The date the current window rolls over (its count resets to 0):
    ///  - `.monthly`: the next pay-cycle month's start day.
    ///  - `.weekly`: the start of next week (`firstWeekday`).
    static func nextReset(_ timeframe: BuyingLimitTimeframe,
                          today: Date = .now,
                          startDay: Int = PayCycle.startDay,
                          firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                          calendar: Calendar = .current) -> Date {
        switch timeframe {
        case .monthly:
            return PayCycle.month(today, startDay: startDay, offset: 1, calendar: calendar).start
        case .weekly:
            return window(.weekly, today: today, firstWeekday: firstWeekday, calendar: calendar).end
        }
    }

    /// The locale's first day of the week (Monday across most of Europe, Sunday in a few locales) as a
    /// `Calendar` weekday index (1 = Sunday … 7 = Saturday).
    static func localeFirstWeekday(_ calendar: Calendar = .current) -> Int {
        calendar.firstWeekday
    }
}
