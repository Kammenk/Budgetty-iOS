//
//  CategorySuggester.swift
//  Budgetty
//
//  Ranks a user's categories for the picker's "Suggested for you" row — frequency weighted toward
//  recent use, so the categories they reach for lately float to the top. Pure (no SwiftData/SwiftUI)
//  so it stays testable and runs off a cheap (category, date) snapshot; the UI resolves emoji/colour
//  for whatever names come back. Android parity: `category/CategorySuggester.kt`.
//
//  Needs no new data model — ranking is a read over the line items the user already has, and the
//  learned name → category rules (applied separately, by the picker) power the context-aware lead.
//

import Foundation

enum CategorySuggester {

    /// How many chips the Suggested row shows at most.
    static let limit = 5

    /// Below this many categorised line items there isn't a meaningful habit yet, so the row shows
    /// generic `commonPicks` labelled "Common picks" rather than personalised ones.
    static let minForPersonalized = 5

    /// Recency half-life: an item this many days old counts half as much as a brand-new one.
    private static let halfLifeDays = 30.0
    private static let dayMs = 86_400_000.0

    /// Generic starter suggestions for users without enough history — everyday essentials. Filtered to
    /// names still in the taxonomy so a future rename/removal can never surface a dead chip.
    static let commonPicks: [String] =
        ["Groceries", "Restaurant & Dining", "Coffee & Cafés", "Public Transport", "Fuel"]
            .filter { Categories.isPredefined($0) }

    /// `categories` best-first; `personalized` is false when these are the generic `commonPicks`.
    struct Ranked { let categories: [String]; let personalized: Bool }

    /// Ranks `stamps` (each a category + its moment) by frequency weighted toward recent use: every
    /// item adds `0.5^(ageDays / halfLifeDays)` to its category's score, so recent spend counts most
    /// and a dormant category sinks. Returns the top `limit` once there are at least
    /// `minForPersonalized` items; otherwise the generic `commonPicks`.
    static func rank(_ stamps: [(category: String, date: Date)], now: Date = .now,
                     limit: Int = limit) -> Ranked {
        let usable = stamps.filter { !$0.category.trimmingCharacters(in: .whitespaces).isEmpty }
        guard usable.count >= minForPersonalized else {
            return Ranked(categories: Array(commonPicks.prefix(limit)), personalized: false)
        }
        var scores: [String: Double] = [:]
        let nowSecs = now.timeIntervalSince1970
        for s in usable {
            let ageDays = max(0, nowSecs - s.date.timeIntervalSince1970) / 86_400
            let weight = pow(0.5, ageDays / halfLifeDays)
            scores[s.category, default: 0] += weight
        }
        let ranked = scores
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
        return Ranked(categories: Array(ranked), personalized: true)
    }
}
