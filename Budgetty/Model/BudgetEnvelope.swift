//
//  BudgetEnvelope.swift
//  Budgetty
//
//  Android's `BudgetEnvelopeEntity` — a named spending budget ("envelope") beyond the single main
//  budget: a `limitAmount` over an inclusive date window, scoped either to all spending (`categories`
//  empty) or to a set of category names. Spend is summed live from line items in the window matching
//  the scope; nothing is denormalised. Added in Android Room v28.
//

import Foundation
import SwiftData

@Model
final class BudgetEnvelope {
    var name: String
    var emoji: String
    var limitAmount: Decimal
    /// Inclusive window start, at local midnight.
    var startDate: Date
    /// Inclusive window end, at local midnight.
    var endDate: Date
    /// Category names the budget counts; empty = all spending.
    var categories: [String]
    var sortOrder: Int
    var createdAt: Date

    init(name: String, emoji: String = "🧾", limitAmount: Decimal, startDate: Date, endDate: Date,
         categories: [String] = [], sortOrder: Int = 0, createdAt: Date = .now) {
        self.name = name
        self.emoji = emoji
        self.limitAmount = limitAmount
        self.startDate = startDate
        self.endDate = endDate
        self.categories = categories
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// True when the budget counts every category (its scope is all spending).
    var isAllSpending: Bool { categories.isEmpty }
}
