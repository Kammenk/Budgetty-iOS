//
//  Budget.swift
//  Budgetty
//
//  Android's BudgetEntity — a single budget limit keyed by "MONTHLY", "WEEKLY", or "CAT:<category>".
//

import Foundation
import SwiftData

@Model
final class Budget {
    /// "MONTHLY", "WEEKLY", or "CAT:<category>".
    @Attribute(.unique) var key: String
    var amount: Decimal

    init(key: String, amount: Decimal) {
        self.key = key
        self.amount = amount
    }

    static let monthlyKey = "MONTHLY"
    static let weeklyKey = "WEEKLY"
    static let fortnightlyKey = "FORTNIGHTLY"
    static func categoryKey(_ category: String) -> String { "CAT:\(category)" }

    // MARK: - Cadence conversions (Android parity: BudgetProgress.kt)

    /// Average fortnights per month (26 ÷ 12 ≈ 2.1667). 26 fortnights make a year, so a monthly figure
    /// prorates × 12 ÷ 26 to one fortnight — the ÷2 shortcut would overstate a monthly bill by ≈8%.
    private static let fortnightsPerMonth = Decimal(26) / Decimal(12)

    /// The fortnightly-equivalent of a `monthly` budget (monthly × 12 ÷ 26), to 2 decimals.
    static func monthlyToFortnightly(_ monthly: Decimal) -> Decimal {
        rounded2(monthly / fortnightsPerMonth)
    }
    /// The monthly-equivalent of a `fortnightly` budget (fortnightly × 26 ÷ 12), to 2 decimals.
    static func fortnightlyToMonthly(_ fortnightly: Decimal) -> Decimal {
        rounded2(fortnightly * fortnightsPerMonth)
    }

    private static func rounded2(_ d: Decimal) -> Decimal {
        var value = d, result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}
