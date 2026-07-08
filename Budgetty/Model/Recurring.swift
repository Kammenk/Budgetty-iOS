//
//  Recurring.swift
//  Budgetty
//
//  Android's RecurringEntity — a recurring money entry on the Budget screen: either an income
//  source (`isIncome == true`) or a recurring payment / bill. Same primitive, opposite signs.
//  Planning-only: these feed the Budget breakdown but never post transactions (the scheduling
//  fields are reserved for a later auto-posting phase).
//

import Foundation
import SwiftData

enum Cadence: String, Codable, CaseIterable {
    case monthly = "MONTHLY"
    case weekly = "WEEKLY"
    case yearly = "YEARLY"
    /// A single, non-repeating entry — counts toward the budget only for its `createdAt` month.
    case once = "ONCE"
}

@Model
final class Recurring {
    var label: String
    var amount: Decimal

    /// True for income sources, false for bills.
    var isIncome: Bool

    /// Spending category for a bill; empty for income.
    var category: String

    /// How often it repeats.
    var cadenceRaw: String

    /// Day-of-month (1...31) for monthly/yearly, or day-of-week (1=Mon...7=Sun) for weekly.
    /// Unused for `.once`, which anchors to `createdAt`.
    var dueDay: Int

    var createdAt: Date

    // Reserved for the later auto-posting phase (unused while planning-only).
    var nextDue: Date?
    var lastPosted: Date?
    var active: Bool

    init(
        label: String,
        amount: Decimal,
        isIncome: Bool,
        category: String = "",
        cadence: Cadence = .monthly,
        dueDay: Int = 1,
        createdAt: Date = .now,
        active: Bool = true
    ) {
        self.label = label
        self.amount = amount
        self.isIncome = isIncome
        self.category = category
        self.cadenceRaw = cadence.rawValue
        self.dueDay = dueDay
        self.createdAt = createdAt
        self.nextDue = nil
        self.lastPosted = nil
        self.active = active
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    /// The amount normalized to a monthly figure (for period-scaled Insights).
    var monthlyEquivalent: Decimal {
        switch cadence {
        case .monthly, .once: amount
        case .weekly: amount * Decimal(52) / Decimal(12)
        case .yearly: amount / Decimal(12)
        }
    }
}
