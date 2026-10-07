//
//  Debt.swift
//  Budgetty
//
//  Android's `DebtEntity` — one debt the user is paying down, for the Debt payoff planner. Purely a
//  planning record: nothing here is linked to a real account or posts transactions; the payoff
//  schedule is simulated live from these figures (see `DebtPayoffSimulator`). Added in Android Room v28.
//

import Foundation
import SwiftData

@Model
final class Debt {
    var emoji: String
    var name: String
    /// Current balance owed.
    var balance: Decimal
    /// Annual interest rate as a percentage (e.g. 19.9 for a 19.9% card).
    var aprPercent: Decimal
    /// The lender's required minimum payment per month.
    var minPayment: Decimal
    var createdAt: Date

    init(emoji: String = "", name: String = "", balance: Decimal, aprPercent: Decimal,
         minPayment: Decimal, createdAt: Date = .now) {
        self.emoji = emoji
        self.name = name
        self.balance = balance
        self.aprPercent = aprPercent
        self.minPayment = minPayment
        self.createdAt = createdAt
    }
}
