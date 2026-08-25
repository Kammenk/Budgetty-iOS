//
//  BuyingLimitSuggestions.swift
//  Budgetty
//
//  Frequency-derived buying-limit suggestions (§4.4) — a 1:1 port of Android's `BuyingLimitSuggestions`.
//  Pure (no SwiftData / SwiftUI) so the ranking unit-tests off-screen and mirrors the Kotlin exactly.
//
//  A name qualifies when its total quantity over the last `lookbackDays` days is at least `minQuantity`
//  AND it was bought at least once in the last `recentDays` days (so a stale item isn't offered as "most
//  bought lately"). Anything already caught by an existing limit's keyword, or whose key the user has
//  dismissed, is dropped and never returns. Candidates are ranked by the last-month count (the number
//  the prompt shows), so the visible list is sorted by its visible figure. Frequency-only — no attempt
//  to guess which items are "staples" (that would misfire across 16 locales; letting the user reject is
//  better, §4.4).
//

import Foundation

/// A frequency-derived buying-limit suggestion (§4.4): an item the user buys a lot but hasn't capped.
struct LimitSuggestion: Identifiable, Equatable {
    /// Representative display name in its original casing, e.g. "Coca-Cola".
    let name: String
    /// The normalized keyword to seed the editor with (`BuyingLimitCounter.normalize`); also the dismissal key.
    let keyword: String
    /// Quantity bought in the last month — the "N×" shown in the prompt.
    let monthCount: Int
    /// Suggested weekly cap = the current weekly rate rounded down, floored at 1.
    let suggestedCap: Int
    /// The timeframe the `suggestedCap` is expressed in (always weekly for now).
    var timeframe: BuyingLimitTimeframe = .weekly

    /// Stable identity for `ForEach`: the normalized keyword is unique across a suggestion list.
    var id: String { keyword }
}

enum BuyingLimitSuggestions {

    /// Qualification window: total quantity is summed over this many days back.
    static let lookbackDays = 60

    /// "Most bought lately": a candidate must also have been bought within this many days back.
    static let recentDays = 30

    /// Minimum total quantity in the `lookbackDays` window to be worth suggesting a cap for.
    static let minQuantity = 6

    /// At most this many suggestions are ever offered at once.
    static let maxSuggestions = 3

    private static let weekDays = 7

    /// The suggestions to offer, best (most-bought-lately) first.
    ///
    /// - Parameters:
    ///   - items: every saved purchased line (name / quantity / made-date).
    ///   - existingKeywords: all normalized keywords across the user's existing limits — a candidate
    ///     already matched by any of them is skipped (no duplicate-limit suggestions).
    ///   - dismissed: normalized keys the user has dismissed; each is skipped for good.
    static func suggest(items: [CountableItem],
                        existingKeywords: [String],
                        dismissed: Set<String>,
                        today: Date = .now,
                        calendar: Calendar = .current) -> [LimitSuggestion] {
        let startOfToday = calendar.startOfDay(for: today)
        let lookbackStart = calendar.date(byAdding: .day, value: -lookbackDays, to: startOfToday) ?? startOfToday
        let recentStart = calendar.date(byAdding: .day, value: -recentDays, to: startOfToday) ?? startOfToday
        // Inclusive through the whole of today (matches Android's `today.plusDays(1) - 1ms`).
        let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday

        let inWindow = items.filter { $0.timestamp >= lookbackStart && $0.timestamp < end && !$0.name.isEmpty }
        let byKey = Dictionary(grouping: inWindow) { BuyingLimitCounter.normalize($0.name) }

        return byKey
            .compactMap { key, rows in
                candidate(key: key, rows: rows, recentStart: recentStart, end: end,
                          existingKeywords: existingKeywords, dismissed: dismissed)
            }
            // Ranked by the last-month figure the prompt shows; ties break by display name for stability.
            .sorted { $0.monthCount != $1.monthCount ? $0.monthCount > $1.monthCount : $0.name < $1.name }
            .prefix(maxSuggestions)
            .map { $0 }
    }

    private static func candidate(key: String,
                                  rows: [CountableItem],
                                  recentStart: Date,
                                  end: Date,
                                  existingKeywords: [String],
                                  dismissed: Set<String>) -> LimitSuggestion? {
        guard !key.isEmpty, !dismissed.contains(key) else { return nil }
        // Already covered by an existing limit (any of its keywords matches this name) → don't re-suggest.
        guard let first = rows.first, !BuyingLimitCounter.matches(first.name, keywords: existingKeywords) else {
            return nil
        }
        let total = rows.reduce(0) { $0 + $1.quantity }
        guard total >= minQuantity else { return nil }
        let monthCount = rows.filter { $0.timestamp >= recentStart && $0.timestamp < end }
            .reduce(0) { $0 + $1.quantity }
        guard monthCount > 0 else { return nil }
        // The most-recently-bought row lends its original casing, so the name reads current.
        let displayName = rows.max { $0.timestamp < $1.timestamp }?.name ?? first.name
        return LimitSuggestion(
            name: displayName,
            keyword: key,
            monthCount: monthCount,
            // Weekly rate implied by last month's purchases, rounded down, floored at 1.
            suggestedCap: max(monthCount * weekDays / recentDays, 1))
    }
}
