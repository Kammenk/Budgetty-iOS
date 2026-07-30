//
//  EmojiCatalogTests.swift
//  BudgettyTests
//
//  The custom-category icon pool + its search, ported 1:1 from Android's EmojiCatalog. Pure data, so
//  these are the cross-platform parity anchor for the ranking rule (exact-token beats prefix).
//

import Testing
@testable import Budgetty

struct EmojiCatalogTests {
    @Test func poolIsNineSectionsWithUniqueGlyphs() {
        #expect(EmojiCatalog.sections.count == 9)
        let all = EmojiCatalog.all
        #expect(all.count == EmojiCatalog.sections.reduce(0) { $0 + $1.entries.count })
        #expect(Set(all).count == all.count)        // every glyph distinct
        #expect(all.count > 200)                     // ~220 curated icons
    }

    @Test func blankQueryReturnsNothing() {
        #expect(EmojiCatalog.search("").isEmpty)
        #expect(EmojiCatalog.search("   ").isEmpty)
    }

    /// The load-bearing rule: an exact keyword hit wins, and prefix-only matches drop when any exact
    /// hit exists — so "car" surfaces the vehicles, not "carton"/"carrot".
    @Test func exactTokenBeatsPrefix() {
        let hits = EmojiCatalog.search("car").map(\.emoji)
        #expect(hits.contains("🚗"))
        #expect(!hits.contains("🧃"))   // juice carton — prefix only
        #expect(!hits.contains("🥕"))   // carrot — prefix only
    }

    @Test func prefixMatchesOnlyWhenNoExactHit() {
        // "cof" is nobody's exact keyword but prefixes "coffee" → the espresso cup surfaces.
        #expect(EmojiCatalog.search("cof").map(\.emoji).contains("☕"))
    }

    @Test func gymReturnsTheFitnessCluster() {
        let hits = Set(EmojiCatalog.search("gym").map(\.emoji))
        #expect(hits.isSuperset(of: ["🏋️", "🧘", "🏃"]))
    }

    @Test func searchIsCaseAndWhitespaceInsensitive() {
        #expect(EmojiCatalog.search("  CAR ").map(\.emoji).contains("🚗"))
    }

    @Test func nonsenseReturnsEmpty() {
        #expect(EmojiCatalog.search("zzzzzzz").isEmpty)
    }
}
