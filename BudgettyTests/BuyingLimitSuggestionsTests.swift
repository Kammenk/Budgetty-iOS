//
//  BuyingLimitSuggestionsTests.swift
//  BudgettyTests
//
//  Pins the §4.4 buying-limit suggestion ranking + dismissal — a port of Android's
//  BuyingLimitSuggestionsTest: frequency-only, a ≥ 6 total over 60 days, recent activity required,
//  existing-limit and dismissed exclusions, weekly-rate cap, ranked by the last-month figure the prompt
//  shows. A fixed UTC Gregorian calendar keeps the day math independent of the runner's timezone.
//

import Testing
import Foundation
@testable import Budgetty

struct BuyingLimitSuggestionsTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var today: Date { cal.date(from: DateComponents(year: 2026, month: 4, day: 15, hour: 12))! }

    private func item(_ name: String, _ quantity: Int, _ m: Int, _ d: Int) -> CountableItem {
        CountableItem(name: name, quantity: quantity,
                      timestamp: cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: 12))!)
    }

    private func suggest(_ items: [CountableItem],
                         existing: [String] = [],
                         dismissed: Set<String> = []) -> [LimitSuggestion] {
        BuyingLimitSuggestions.suggest(items: items, existingKeywords: existing,
                                       dismissed: dismissed, today: today, calendar: cal)
    }

    @Test func ranksByLastMonthCountWithWeeklyCap() {
        let out = suggest([item("Coca-Cola", 14, 4, 1), item("Crisps", 11, 4, 5)])
        #expect(out.count == 2)
        #expect(out[0].keyword == "coca-cola")
        #expect(out[0].monthCount == 14)
        #expect(out[0].suggestedCap == 3)          // 14×/month → floor(14·7/30)
        #expect(out[0].timeframe == .weekly)
        #expect(out[0].name == "Coca-Cola")
        #expect(out[1].keyword == "crisps")
        #expect(out[1].suggestedCap == 2)
    }

    @Test func dropsBelowMinimumQuantity() {
        // 5 total over the window is under the ≥ 6 bar — no suggestion.
        #expect(suggest([item("Rare treat", 5, 4, 2)]).isEmpty)
    }

    @Test func dropsStaleItemsNotBoughtLately() {
        // 8 total qualifies on 60 days, but all of it is older than 30 days → not "most bought lately".
        #expect(suggest([item("Old staple", 8, 2, 20)]).isEmpty)
    }

    @Test func excludesItemsAlreadyCoveredByAnExistingLimit() {
        let out = suggest([item("Coffee beans", 9, 4, 3)], existing: ["coffee"])
        #expect(out.isEmpty)   // an existing "coffee" keyword already caps this
    }

    @Test func aDismissedSuggestionNeverReturns() {
        let items = [item("Coca-Cola", 14, 4, 1), item("Crisps", 11, 4, 5)]
        let out = suggest(items, dismissed: ["coca-cola"])
        #expect(out.count == 1)
        #expect(out[0].keyword == "crisps")   // dismissed coke is gone; crisps remains
    }

    @Test func capsAtThreeSuggestions() {
        let out = suggest([
            item("Coke", 20, 4, 1), item("Crisps", 15, 4, 1), item("Chocolate", 12, 4, 1),
            item("Beer", 10, 4, 1), item("Energy drink", 8, 4, 1),
        ])
        #expect(out.count == 3)
        #expect(out.map(\.keyword) == ["coke", "crisps", "chocolate"])
    }
}
