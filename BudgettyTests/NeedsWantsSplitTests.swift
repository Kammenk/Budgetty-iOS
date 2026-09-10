//
//  NeedsWantsSplitTests.swift
//  BudgettyTests
//
//  The Needs / Wants / Savings (50/30/20) derivation — ported 1:1 from Android's InsightsViewModel
//  math, so these invariants double as a cross-platform parity check. Pure logic: no ModelContext,
//  Category rows are built in-memory just to carry an explicit `bucket` / `parent`.
//

import Testing
import Foundation
@testable import Budgetty

struct NeedsWantsSplitTests {

    private func cat(_ name: String, parent: String? = nil, bucket: String? = nil) -> Budgetty.Category {
        Budgetty.Category(name: name, colorArgb: 0, icon: "", isCustom: false, createdAt: .distantPast,
                          parent: parent, bucket: bucket)
    }

    // MARK: - Default bucket mapping

    @Test func defaultBucketFollowsGroupWithExceptions() {
        #expect(Categories.defaultBucket(of: "Groceries") == .need)          // group default
        #expect(Categories.defaultBucket(of: "Fruits & Vegetables") == .need) // sub inherits group
        #expect(Categories.defaultBucket(of: "Restaurant & Dining") == .want) // Dining group → want
        #expect(Categories.defaultBucket(of: "Rent") == .need)                // Services & Subs → need
        #expect(Categories.defaultBucket(of: "Travel & Accommodation") == .want) // per-category exception
        #expect(Categories.defaultBucket(of: "Subscriptions") == .want)          // per-category exception
        #expect(Categories.defaultBucket(of: "Savings") == .savings)             // anchors Savings
        #expect(Categories.defaultBucket(of: "Investments") == .savings)
        #expect(Categories.defaultBucket(of: "Some Custom Thing") == .want)      // unmapped → want
    }

    // MARK: - Effective bucket resolution (own tag → parent's tag → code default)

    @Test func explicitTagWinsOverDefault() {
        let byName = Categories.index([cat("Groceries", bucket: "WANT")])
        #expect(Categories.effectiveBucket(of: "Groceries", in: byName) == .want)
    }

    @Test func subInheritsParentExplicitTag() {
        // Fuel's code default is Need (Transportation). Tagging its parent Want should cascade to it
        // when Fuel itself has no explicit tag.
        let byName = Categories.index([cat("Transportation", bucket: "WANT"), cat("Fuel", parent: "Transportation")])
        #expect(Categories.effectiveBucket(of: "Fuel", in: byName) == .want)
    }

    @Test func ownTagBeatsParentTag() {
        let byName = Categories.index([cat("Transportation", bucket: "WANT"),
                                       cat("Fuel", parent: "Transportation", bucket: "SAVINGS")])
        #expect(Categories.effectiveBucket(of: "Fuel", in: byName) == .savings)
    }

    // MARK: - split()

    @Test func noIncomeGivesSetupState() {
        #expect(NeedsWantsSplitMath.split(income: 0, spendByCategory: ["Groceries": 100],
                                          categories: [], savingsContributed: 0,
                                          countLeftoverAsSavings: false) == nil)
    }

    @Test func balancedFiftyThirtyTwentySetAside() {
        let split = NeedsWantsSplitMath.split(
            income: 2000,
            spendByCategory: ["Groceries": 1000, "Restaurant & Dining": 600],
            categories: [], savingsContributed: 400, countLeftoverAsSavings: false)
        let s = try! #require(split)
        #expect(s.needs.percent == 50)
        #expect(s.wants.percent == 30)
        #expect(s.savings.percent == 20)   // deliberate = 0 tagged + 400 contributed
        #expect(s.needs.status == .onTarget)
        #expect(s.wants.status == .onTarget)
        #expect(s.savings.status == .onTarget)
        #expect(s.tone == .balanced)
        #expect(s.allocation == .setAside)
        #expect(s.leftover == 0)
    }

    @Test func countKeptFoldsLeftoverIntoSavings() {
        // No contributions, no Savings-tagged spend: "set aside" reports 0% saved with 20% leftover,
        // "count kept" folds that leftover into Savings → 20%.
        let aside = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 1000, "Restaurant & Dining": 600],
            categories: [], savingsContributed: 0, countLeftoverAsSavings: false)
        #expect(try! #require(aside).savings.percent == 0)
        #expect(try! #require(aside).leftover == 400)

        let kept = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 1000, "Restaurant & Dining": 600],
            categories: [], savingsContributed: 0, countLeftoverAsSavings: true)
        let k = try! #require(kept)
        #expect(k.savings.percent == 20)
        #expect(k.savings.amount == 400)
        #expect(k.leftoverFraction == 0)
        #expect(k.allocation == .countKept)
    }

    @Test func unsetWhenNotAsked() {
        let split = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 1000], categories: [],
            savingsContributed: 0, countLeftoverAsSavings: nil)
        #expect(try! #require(split).allocation == .unset)
    }

    @Test func toneUnderSavingWhenSavingsBelowTolerance() {
        // Needs 55%, Wants 38%, deliberate savings 7% → under-saving.
        let split = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 1100, "Restaurant & Dining": 760],
            categories: [], savingsContributed: 140, countLeftoverAsSavings: false)
        let s = try! #require(split)
        #expect(s.savings.percent == 7)
        #expect(s.savings.status == .underWarn)
        #expect(s.tone == .underSaving)
    }

    @Test func toneWantsOverAndDeltaPill() {
        // Needs 48% (on target), Wants 40% (>32), Savings 20% (on target, so under-saving doesn't
        // pre-empt) → wants-over; the Wants pill is an over-warn +10.
        let split = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 960, "Restaurant & Dining": 800],
            categories: [], savingsContributed: 400, countLeftoverAsSavings: false)
        let s = try! #require(split)
        #expect(s.wants.percent == 40)
        #expect(s.wants.deltaPoints == 10)
        #expect(s.wants.status == .overWarn)
        #expect(s.tone == .wantsOver)
    }

    @Test func savingsOverTargetIsGood() {
        let split = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 800, "Restaurant & Dining": 400],
            categories: [], savingsContributed: 800, countLeftoverAsSavings: false)
        let s = try! #require(split)
        #expect(s.savings.percent == 40)
        #expect(s.savings.status == .overGood)
    }

    @Test func needsUnderIsNeutralNotWarn() {
        // Needs 40% (under 50, outside tolerance) reads neutral — spending less than the rule isn't bad.
        let split = NeedsWantsSplitMath.split(
            income: 2000, spendByCategory: ["Groceries": 800, "Restaurant & Dining": 600],
            categories: [], savingsContributed: 600, countLeftoverAsSavings: false)
        #expect(try! #require(split).needs.status == .underNeutral)
    }

    // MARK: - trend()

    @Test func trendStopsAtFirstIncomelessMonth() {
        let months = [
            NeedsWantsSplitMath.MonthInput(axisLabel: "Sep", income: 2000,
                spendByCategory: ["Groceries": 1000], savingsContributed: 400),
            NeedsWantsSplitMath.MonthInput(axisLabel: "Aug", income: 2000,
                spendByCategory: ["Groceries": 900], savingsContributed: 300),
            NeedsWantsSplitMath.MonthInput(axisLabel: "Jul", income: 0,  // no income plan yet → stop
                spendByCategory: ["Groceries": 500], savingsContributed: 0),
            NeedsWantsSplitMath.MonthInput(axisLabel: "Jun", income: 2000,
                spendByCategory: ["Groceries": 800], savingsContributed: 0),
        ]
        let trend = NeedsWantsSplitMath.trend(recentFirst: months, categories: [])
        #expect(trend.count == 2)                 // Sep + Aug only, contiguous
        #expect(trend.first?.axisLabel == "Aug")  // oldest first
        #expect(trend.last?.axisLabel == "Sep")
        #expect(trend.last?.needsPercent == 50)
        #expect(trend.last?.savingsPercent == 20)
    }

    @Test func pctOfRoundsHalfAway() {
        #expect(NeedsWantsSplitMath.pctOf(0, 0) == 0)
        #expect(NeedsWantsSplitMath.pctOf(500, 2000) == 25)
        #expect(NeedsWantsSplitMath.pctOf(1, 8) == 13)  // 12.5 → 13
    }
}
