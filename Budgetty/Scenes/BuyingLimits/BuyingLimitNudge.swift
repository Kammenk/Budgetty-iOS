//
//  BuyingLimitNudge.swift
//  Budgetty
//
//  The save-time buying-limit nudge and its app-scoped hand-off — a port of Android's
//  `BuyingLimitNudge` + `BuyingLimitNudgeBus` + `BuyingLimitNudger`. When a just-saved receipt brings
//  a keyword limit to/over its cap, the save flow posts a nudge to the `BuyingLimitNudgeCenter`; the
//  app shell shows a non-blocking floating card over the live screen. In-app only — no push, no
//  background work.
//

import Foundation
import SwiftData

/// A pending save-time nudge: the just-saved receipt brought `title`'s buying limit to/over its cap.
/// Carries only display facts; the reset day and "this week/month" phrasing are resolved in the UI
/// (they need the locale + resources). `countAfter` is the total bought in the current window after
/// this receipt (the "your Nth" figure), `limitCount` the cap.
struct BuyingLimitNudge: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let emoji: String
    let countAfter: Int
    let limitCount: Int
    let timeframe: BuyingLimitTimeframe
}

/// A tiny app-scoped hand-off for the buying-limit save-time nudge — the SwiftUI equivalent of
/// Android's `BuyingLimitNudgeBus`. The receipt save flow posts a nudge as it persists rows; the shell
/// observes it and floats the card over the live screen. A single slot (latest wins); dismiss or "View
/// limits" clears it. `@Observable` + injected via `.environment`, like `AuthModel` / `StoreManager`.
@Observable
final class BuyingLimitNudgeCenter {
    var pending: BuyingLimitNudge?

    func post(_ nudge: BuyingLimitNudge) { pending = nudge }
    func clear() { pending = nil }
}

/// Computes the save-time buying-limit nudge from the just-saved rows plus the live store. Kept out of
/// the save flow as its own collaborator so this logic (window + substring counting) is testable in
/// isolation and mirrors 1:1 on Android.
///
/// A limit qualifies when the just-saved rows contributed at least one matching unit within its
/// current window AND the window's total now meets or exceeds the cap; the most-over limit wins (ties
/// broken by the higher count, then the most-recently-created). Counts sum quantity on the same
/// normalized substring rule the management screen uses, so card and nudge always agree. Non-blocking:
/// the receipt is already saved regardless.
enum BuyingLimitNudger {
    /// `savedItems` = the rows the just-finalized receipt persisted (name, quantity, `createdAt`).
    @MainActor
    static func evaluate(savedItems: [CountableItem],
                         in context: ModelContext,
                         startDay: Int = PayCycle.startDay,
                         today: Date = .now) -> BuyingLimitNudge? {
        let limits = (try? context.fetch(FetchDescriptor<BuyingLimit>())) ?? []
        guard !limits.isEmpty else { return nil }
        let allItems = ((try? context.fetch(FetchDescriptor<LineItem>())) ?? [])
            .map { CountableItem(name: $0.name, quantity: $0.quantity, timestamp: $0.createdAt) }

        var candidates: [(limit: BuyingLimit, countAfter: Int)] = []
        for limit in limits {
            let keywords = limit.keywords
            guard !keywords.isEmpty else { continue }
            let window = BuyingLimitCounter.window(limit.timeframe, today: today, startDay: startDay)
            let contributed = BuyingLimitCounter.countInWindow(savedItems, keywords: keywords, window: window)
            guard contributed > 0 else { continue }
            let countAfter = BuyingLimitCounter.countInWindow(allItems, keywords: keywords, window: window)
            guard countAfter >= limit.count else { continue }
            candidates.append((limit, countAfter))
        }

        guard let winner = candidates.max(by: { a, b in
            let overA = a.countAfter - a.limit.count
            let overB = b.countAfter - b.limit.count
            if overA != overB { return overA < overB }
            if a.countAfter != b.countAfter { return a.countAfter < b.countAfter }
            return a.limit.createdAt < b.limit.createdAt
        }) else { return nil }

        return BuyingLimitNudge(title: winner.limit.displayTitle, emoji: winner.limit.emoji,
                                countAfter: winner.countAfter, limitCount: winner.limit.count,
                                timeframe: winner.limit.timeframe)
    }
}
