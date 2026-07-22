//
//  PlanPricingTests.swift
//  BudgettyTests
//
//  The paywall's per-month line and savings badge are arithmetic over App Store Connect's prices.
//  They were hardcoded ("€2.50 / month", "SAVE 37%") beside a StoreKit-supplied price, so a re-price
//  in App Store Connect would have left the copy lying. These pin the arithmetic and, more usefully,
//  the cases where the claim must be dropped instead of computed.
//

import Foundation
import Testing
@testable import Budgetty

struct PlanPricingTests {
    /// The prices the hardcoded copy was derived from: €29.99/yr really is €2.50/mo and 37% off.
    /// Compared at currency precision, since that's what the paywall renders.
    @Test func matchesTheFiguresTheOldCopyHardcoded() {
        #expect(cents(PlanPricing.perMonth(yearly: 29.99)) == Decimal(string: "2.50")!)
        #expect(PlanPricing.savingsPercent(yearly: 29.99, monthly: 3.99) == 37)
    }

    private func cents(_ value: Decimal) -> Decimal {
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        return rounded
    }

    /// …and follows a re-price instead of keeping the old number, which is the whole point.
    @Test func followsARepricedSubscription() {
        #expect(PlanPricing.savingsPercent(yearly: 19.99, monthly: 2.99) == 44)
        #expect(PlanPricing.savingsPercent(yearly: 49.99, monthly: 4.99) == 16)
    }

    /// Rounds down, so the badge can never overstate the saving.
    @Test func roundsTheSavingDown() {
        // 12 × 1.00 = 12.00 against 8.99 → 25.08% → "25", never "26".
        #expect(PlanPricing.savingsPercent(yearly: 8.99, monthly: 1.00) == 25)
    }

    /// No saving, no badge — rather than "SAVE 0%" or a negative number.
    @Test func dropsTheClaimWhenThereIsNoSaving() {
        #expect(PlanPricing.savingsPercent(yearly: 47.88, monthly: 3.99) == nil) // exactly equal
        #expect(PlanPricing.savingsPercent(yearly: 59.99, monthly: 3.99) == nil) // yearly costs more
        #expect(PlanPricing.savingsPercent(yearly: 47.80, monthly: 3.99) == nil) // rounds to 0%
        #expect(PlanPricing.savingsPercent(yearly: 29.99, monthly: 0) == nil)    // no monthly price
    }
}
