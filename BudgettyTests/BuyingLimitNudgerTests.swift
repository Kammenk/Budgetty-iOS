//
//  BuyingLimitNudgerTests.swift
//  BudgettyTests
//
//  Pins §4.6 nudge restraint on the pure `BuyingLimitNudger.selectNudge`: exactly one nudge per save
//  (the most-over limit), only on the receipt that actually CROSSES the cap, and never a re-nudge for a
//  limit that was already at/over its cap earlier in the same window. Port of Android's
//  BuyingLimitNudgerTest. A fixed UTC Gregorian calendar + Monday weeks keep the window math deterministic.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct BuyingLimitNudgerTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // Wed 2026-04-15, Monday weeks → the open weekly window is Apr 13–19.
    private var today: Date { cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))! }

    private func at(_ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!
    }
    private func item(_ name: String, _ quantity: Int, _ m: Int, _ d: Int) -> CountableItem {
        CountableItem(name: name, quantity: quantity, timestamp: at(m, d))
    }

    /// A real in-memory context so the `BuyingLimit` @Model instances are fully backed (matches the
    /// backup-restore test's setup); `selectNudge` itself is pure and reads only their fields.
    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Schema(UserStore.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func coke(_ cap: Int, created: Int, in ctx: ModelContext) -> BuyingLimit {
        let l = BuyingLimit(keywords: ["coke"], timeframe: .weekly, count: cap,
                            createdAt: Date(timeIntervalSince1970: TimeInterval(created)))
        ctx.insert(l)
        return l
    }

    private func select(_ limits: [BuyingLimit], _ all: [CountableItem], _ saved: [CountableItem]) -> BuyingLimitNudge? {
        BuyingLimitNudger.selectNudge(limits: limits, allItems: all, savedItems: saved,
                                      today: today, startDay: 1, firstWeekday: 2 /* Monday */, calendar: cal)
    }

    @Test func nudgesOnTheReceiptThatCrossesTheCap() throws {
        let ctx = try context()
        let saved = [item("Coke", 1, 4, 15)]
        let all = [item("Coke", 1, 4, 13)] + saved   // before 1 → after 2, cap 2
        let nudge = select([coke(2, created: 1, in: ctx)], all, saved)
        #expect(nudge?.countAfter == 2)
        #expect(nudge?.limitCount == 2)
    }

    @Test func doesNotReNudgeWhenAlreadyOverBeforeThisReceipt() throws {
        let ctx = try context()
        // Already 2 (at cap) before this save; this receipt pushes to 3 → they know, no re-nudge.
        let saved = [item("Coke", 1, 4, 15)]
        let all = [item("Coke", 2, 4, 13)] + saved
        #expect(select([coke(2, created: 1, in: ctx)], all, saved) == nil)
    }

    @Test func doesNotNudgeWhenThisReceiptDidNotContribute() throws {
        let ctx = try context()
        let saved = [item("Bread", 1, 4, 15)]
        let all = [item("Coke", 2, 4, 13)] + saved
        #expect(select([coke(2, created: 1, in: ctx)], all, saved) == nil)
    }

    @Test func picksTheMostOverAmongCrossingLimitsAtMostOne() throws {
        let ctx = try context()
        let saved = [item("Coke", 1, 4, 15), item("Crisps", 1, 4, 15)]
        let all = [
            item("Coke", 1, 4, 13),     // coke before 1 → after 2 (cap 2): crosses
            item("Crisps", 3, 4, 13),   // crisps before 3 → after 4 (cap 1): already over → excluded
        ] + saved
        let crisps = BuyingLimit(keywords: ["crisps"], timeframe: .weekly, count: 1,
                                 createdAt: Date(timeIntervalSince1970: 2))
        ctx.insert(crisps)
        // crisps was already over before this receipt → excluded; coke crosses → coke wins (the only one).
        let nudge = select([coke(2, created: 1, in: ctx), crisps], all, saved)
        #expect(nudge?.limitCount == 2)     // coke's cap
        #expect(nudge?.countAfter == 2)
        #expect(nudge?.title == "Coke")
    }
}
