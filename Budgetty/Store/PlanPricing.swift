//
//  PlanPricing.swift
//  Budgetty
//
//  The paywall's derived figures — the "/ mo" line and the savings badge — as pure arithmetic over
//  the loaded products' prices. At the shipping prices (€59.99/yr, €5.99/mo) that renders
//  "€5.00 / mo" and "−16%".
//
//  These used to be hardcoded strings sitting next to a StoreKit-supplied price, so re-pricing the
//  subscription in App Store Connect would have made the paywall quietly lie. Keeping the maths here
//  (rather than inline in the view) is what lets it be tested without a StoreKit session, which on a
//  simulator without a .storekit configuration is otherwise impossible.
//

import Foundation

enum PlanPricing {
    /// A yearly price spread across the 12 months it covers.
    static func perMonth(yearly: Decimal) -> Decimal { yearly / 12 }

    /// How much cheaper the yearly plan is than paying monthly for a year, as a whole percent
    /// rounded down. Nil when the comparison isn't meaningful — no monthly price, or a yearly plan
    /// that isn't actually a saving. Callers drop the claim rather than print a zero.
    static func savingsPercent(yearly: Decimal, monthly: Decimal) -> Int? {
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else { return nil }
        let fraction = (twelveMonths - yearly) / twelveMonths * 100
        let percent = Int(NSDecimalNumber(decimal: fraction).doubleValue)
        return percent > 0 ? percent : nil
    }
}
