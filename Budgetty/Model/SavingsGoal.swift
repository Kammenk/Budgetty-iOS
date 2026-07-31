//
//  SavingsGoal.swift
//  Budgetty
//
//  Android's SavingsGoalEntity + SavingsContributionEntity. A savings goal is a manual tracker —
//  Budgetty holds no balances, so the "saved" amount is the signed sum of dated contributions the
//  user logs themselves (a deposit is positive, a withdrawal negative), never a transfer of real
//  money. Deleting a goal cascades to its contributions.
//

import Foundation
import SwiftData

/// Free tier allows one savings goal; Premium is unlimited (matches recurring-3 / widgets-2 caps).
enum SavingsQuota {
    static let freeLimit = 1
}

@Model
final class SavingsGoal {
    var name: String
    var emoji: String
    var targetAmount: Decimal
    /// Optional target date; when set, the card/detail show a monthly pace + on-track/behind hint.
    var targetDate: Date?
    /// Creation time — orders the goals list by when each was added.
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SavingsContribution.goal)
    var contributions: [SavingsContribution] = []

    init(name: String, emoji: String, targetAmount: Decimal, targetDate: Date? = nil,
         createdAt: Date = .now) {
        self.name = name
        self.emoji = emoji
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.createdAt = createdAt
    }
}

@Model
final class SavingsContribution {
    /// Signed: positive = added to savings, negative = withdrawn. A goal's saved total is their sum.
    var amount: Decimal
    var note: String
    /// When the contribution happened; defaults to when it was logged.
    var date: Date
    var goal: SavingsGoal?

    init(amount: Decimal, note: String = "", date: Date = .now, goal: SavingsGoal? = nil) {
        self.amount = amount
        self.note = note
        self.date = date
        self.goal = goal
    }
}
