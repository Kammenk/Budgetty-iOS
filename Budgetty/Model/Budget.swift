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
    static func categoryKey(_ category: String) -> String { "CAT:\(category)" }
}
