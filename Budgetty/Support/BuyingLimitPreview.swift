//
//  BuyingLimitPreview.swift
//  Budgetty
//
//  The editor's live "CURRENTLY MATCHES" preview — a 1:1 port of Android's `BuyingLimitPreview`.
//  Computed purely from the saved items so the user sees exactly what a limit will catch before
//  saving; this is how substring matching is kept honest (e.g. warning that "ice" would also catch
//  "juice"). Pure/testable.
//
//  The distinct item NAMES and the too-broad signal are drawn from all saved receipts (what the
//  keyword catches overall); `windowQuantity` is scoped to the selected timeframe's current window
//  (what would count toward the limit right now).
//

import Foundation

struct BuyingLimitPreview {
    enum State { case hidden, noMatch, match }

    let state: State
    /// Up to `maxNames` representative item names (original casing), most-bought first.
    let names: [String]
    /// Distinct matching item names beyond `names` ("+n more"); 0 when all fit.
    let moreCount: Int
    /// Σ quantity matching in the selected timeframe's current window.
    let windowQuantity: Int
    /// True when a short keyword catches a lot of distinct items — a "catching a lot" warning (never
    /// blocks save).
    let tooBroad: Bool
    /// A more specific keyword to suggest instead (already lower-cased), or nil when none is sensible.
    let suggestion: String?

    static let maxNames = 3
    private static let broadMinDistinct = 6
    private static let broadShortLen = 4

    private static var hidden: BuyingLimitPreview {
        BuyingLimitPreview(state: .hidden, names: [], moreCount: 0, windowQuantity: 0,
                           tooBroad: false, suggestion: nil)
    }

    static func compute(items: [CountableItem],
                        rawKeywords: [String],
                        timeframe: BuyingLimitTimeframe,
                        label: String = "",
                        today: Date = .now,
                        startDay: Int = PayCycle.startDay,
                        firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday()) -> BuyingLimitPreview {
        let keywords = BuyingLimit.normalizedKeywords(rawKeywords)
        if keywords.isEmpty { return hidden }

        let matching = items.filter { BuyingLimitCounter.matches($0.name, keywords: keywords) }
        if matching.isEmpty {
            return BuyingLimitPreview(state: .noMatch, names: [], moreCount: 0, windowQuantity: 0,
                                      tooBroad: false, suggestion: nil)
        }

        // Distinct items by normalized name, each with a representative display name + total qty ever,
        // in first-seen order (so the stable sort below matches Android's ordered groupBy).
        var order: [String] = []
        var repName: [String: String] = [:]
        var totalQty: [String: Int] = [:]
        for item in matching {
            let key = BuyingLimitCounter.normalize(item.name)
            if totalQty[key] == nil { order.append(key); repName[key] = item.name }
            totalQty[key, default: 0] += item.quantity
        }
        let groups = order.enumerated()
            .map { (idx, key) in (name: repName[key]!, qty: totalQty[key]!, idx: idx) }
            .sorted { $0.qty != $1.qty ? $0.qty > $1.qty : $0.idx < $1.idx }

        let names = groups.prefix(maxNames).map(\.name)
        let moreCount = max(groups.count - names.count, 0)

        let window = BuyingLimitCounter.window(timeframe, today: today, startDay: startDay,
                                               firstWeekday: firstWeekday)
        let windowQuantity = BuyingLimitCounter.countInWindow(matching, keywords: keywords, window: window)

        let tooBroad = groups.count >= broadMinDistinct && keywords.contains { $0.count <= broadShortLen }
        let suggestion = tooBroad ? suggestFor(label: label, keywords: keywords, topName: groups[0].name) : nil

        return BuyingLimitPreview(state: .match, names: names, moreCount: moreCount,
                                  windowQuantity: windowQuantity, tooBroad: tooBroad, suggestion: suggestion)
    }

    /// A more specific keyword to offer: the user's own `label` if it's a longer term they haven't
    /// already added, else the most-bought matching product's name — either way only when it's
    /// genuinely narrower (longer) than the shortest current keyword.
    private static func suggestFor(label: String, keywords: [String], topName: String) -> String? {
        let shortest = keywords.map(\.count).min() ?? 0
        func candidate(_ raw: String) -> String? {
            let key = BuyingLimitCounter.normalize(raw)
            return (!key.isEmpty && !keywords.contains(key) && key.count > shortest) ? key : nil
        }
        return candidate(label) ?? candidate(topName)
    }
}
