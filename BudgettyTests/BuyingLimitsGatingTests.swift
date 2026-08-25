//
//  BuyingLimitsGatingTests.swift
//  BudgettyTests
//
//  Pins §4.5: the free tier is 3 buying limits, and the Add row only locks for a free user at that cap
//  (mirrors Android's BuyingLimitsGatingTest over the pure `BuyingLimitQuota.isAtCap`).
//

import Testing
@testable import Budgetty

struct BuyingLimitsGatingTests {

    @Test func freeLimitIsThree() {
        #expect(BuyingLimitQuota.freeLimit == 3)
    }

    @Test func freeUserLocksOnlyAtThree() {
        #expect(!BuyingLimitQuota.isAtCap(count: 2, isPremium: false))   // two of three used → still open
        #expect(BuyingLimitQuota.isAtCap(count: 3, isPremium: false))    // three of three used → locked
    }

    @Test func premiumNeverLocks() {
        #expect(!BuyingLimitQuota.isAtCap(count: 5, isPremium: true))
    }
}
