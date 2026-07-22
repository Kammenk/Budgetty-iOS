//
//  PremiumBenefitsTests.swift
//  BudgettyTests
//
//  Guards the paywall against the failure it actually had: rows advertising things the app doesn't
//  do. Four of five original claims were false — a free feature sold as premium, a cap that didn't
//  exist, and two unbuilt features. These tests tie the copy back to the code that enforces it, so
//  the same drift can't return silently.
//

import Testing
@testable import Budgetty

struct PremiumBenefitsTests {
    /// Every "real" benefit must be one something actually gates on. If a future row is added here,
    /// it needs an enforcing constant — or it belongs in `soon`.
    @Test func realBenefitsAreOnlyTheEnforcedOnes() {
        #expect(PremiumBenefits.real.map(\.id) == ["scans", "categories", "recurring", "widgets", "themes"])
    }

    /// The numbers must come from the constants, not be retyped. Change a cap and this fails until
    /// the copy follows — which is the whole point of interpolating them.
    @Test func detailsQuoteTheEnforcingConstants() throws {
        let scans = try #require(PremiumBenefits.real.first(where: { $0.id == "scans" }))
        #expect(scans.detail.contains("\(ScanQuota.freeLimit)"))

        let categories = try #require(PremiumBenefits.real.first(where: { $0.id == "categories" }))
        #expect(categories.detail.contains("\(Categories.freeCustomLimit)"))

        let recurring = try #require(PremiumBenefits.real.first(where: { $0.id == "recurring" }))
        #expect(recurring.detail.contains("\(RecurringQuota.freeLimit)"))

        let widgets = try #require(PremiumBenefits.real.first(where: { $0.id == "widgets" }))
        #expect(widgets.detail.contains("\(WidgetQuota.freeLimit)"))
    }

    /// The themes row names three accents; they have to exist, or it's the old "advertise what you
    /// don't ship" bug wearing a new coat.
    @Test func themesRowNamesAccentsThatExist() throws {
        let themes = try #require(PremiumBenefits.real.first(where: { $0.id == "themes" }))
        for accent in [AccentOption.sage, .ocean, .plum] {
            #expect(themes.detail.localizedCaseInsensitiveContains(accent.rawValue))
        }
        // …and they must be distinct colours, not four aliases of the brand violet.
        let hexes = Set(AccentOption.allCases.map { "\($0.hexes.light)-\($0.hexes.dark)" })
        #expect(hexes.count == AccentOption.allCases.count)
    }

    /// Unbuilt features stay visible but flagged; nothing in `real` may claim to be coming.
    @Test func roadmapRowsAreMarkedAndRealOnesAreNot() {
        // `allSatisfy` is rethrows, which #expect treats as throwing — evaluate outside the macro.
        let everyRoadmapRowFlagged = PremiumBenefits.soon.allSatisfy(\.soon)
        let noRealRowFlagged = PremiumBenefits.real.allSatisfy { !$0.soon }
        #expect(everyRoadmapRowFlagged)
        #expect(noRealRowFlagged)
        #expect(PremiumBenefits.soon.map(\.id) == ["cloud"])
    }

    /// The free custom-category cap is 3 — never the "10" the old copy invented.
    ///
    /// The widgets row used to be banned outright here, because nothing gated widgets. It's allowed
    /// back only now that `WidgetQuota` enforces a cap, and only while it quotes that constant —
    /// which `detailsQuoteTheEnforcingConstants` checks. Delete the enforcement and that test fails,
    /// which is the guard that actually matters.
    @Test func retiredFalseClaimsStayGone() {
        let copy = PremiumBenefits.all.map { "\($0.title) \($0.detail)" }.joined(separator: " ")
        #expect(!copy.contains("10 custom"))
        #expect(Categories.freeCustomLimit == 3)
        #expect(Categories.maxCustomLimit == Int.max) // "unlimited" is literal, not marketing
    }
}
