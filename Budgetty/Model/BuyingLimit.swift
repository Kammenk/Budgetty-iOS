//
//  BuyingLimit.swift
//  Budgetty
//
//  Android's BuyingLimitEntity — a keyword-based item purchase cap, a sibling to CategoryRule. The
//  user caps how many of something they buy in a timeframe ("no more than 1 Coke a week"); Budgetty
//  counts matching items off saved receipts and nudges when the count reaches/exceeds `count`.
//
//  `keywords` is a list of **normalized** match keys (see `normalizeKeyword`): each trimmed and
//  lower-cased. Lower-casing is done in Swift (Unicode-aware) — not via a case-insensitive SQL
//  predicate — so Cyrillic keywords (Bulgarian receipts) fold correctly too.
//
//  The count itself is never stored: it's derived on demand by summing the quantity of matching line
//  items in the current window (see `BuyingLimitCounter`), so it always reflects the live receipt
//  data — Budgetty holds no running totals.
//

import Foundation
import SwiftData

/// How often a `BuyingLimit`'s count resets. Stored as its raw string (mirrors `Cadence` on
/// `Recurring`) so SwiftData persists a stable value and the backup DTO round-trips it.
enum BuyingLimitTimeframe: String, Codable, CaseIterable, Identifiable {
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"

    var id: String { rawValue }
}

/// Free tier allows one buying limit; Premium is unlimited (matches savings-1 / recurring-3 /
/// widgets-2 caps).
enum BuyingLimitQuota {
    static let freeLimit = 1
}

@Model
final class BuyingLimit {
    /// Optional per-limit emoji; empty = none, so the card/editor fall back to a generic tag glyph.
    var emoji: String
    /// Optional user label; empty = none, so the display title falls back to the first keyword.
    var label: String
    /// Normalized keywords; any one matching (substring) counts toward this limit. Already trimmed +
    /// lower-cased and de-duplicated on save.
    var keywords: [String]
    /// The reset cadence, stored as `BuyingLimitTimeframe.rawValue`.
    var timeframeRaw: String
    /// The cap, per timeframe window. Floored at 1 by the editor.
    var count: Int
    /// Creation time — orders the limits list by when each was added, and is the stable tiebreak the
    /// save-time nudge uses when two limits are equally over.
    var createdAt: Date

    init(emoji: String = "", label: String = "", keywords: [String] = [],
         timeframe: BuyingLimitTimeframe = .monthly, count: Int = 1, createdAt: Date = .now) {
        self.emoji = emoji
        self.label = label
        self.keywords = keywords
        self.timeframeRaw = timeframe.rawValue
        self.count = max(count, 1)
        self.createdAt = createdAt
    }

    /// The reset cadence.
    var timeframe: BuyingLimitTimeframe {
        get { BuyingLimitTimeframe(rawValue: timeframeRaw) ?? .monthly }
        set { timeframeRaw = newValue.rawValue }
    }

    /// The card/nudge title: the user's `label` if set, otherwise the first keyword with its initial
    /// letter capitalized ("coke" → "Coke"; Cyrillic folds too). Empty only for a limit with no label
    /// and no keywords, which the editor never saves.
    var displayTitle: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard let first = keywords.first, !first.isEmpty else { return "" }
        return first.prefix(1).uppercased() + first.dropFirst()
    }

    /// The canonical match key for a raw keyword: trimmed + lower-cased (Unicode-aware), like the
    /// category-rules key.
    static func normalizeKeyword(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Normalizes, drops blanks, and de-duplicates `raw` into the stored keyword list (order-stable).
    static func normalizedKeywords(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for key in raw.map(normalizeKeyword) where !key.isEmpty && seen.insert(key).inserted {
            result.append(key)
        }
        return result
    }
}
