//
//  BudgetRollover.swift
//  Budgetty
//
//  Android's `BudgetRolloverEntity` — the unspent budget carried into the current period for one
//  budget key ("MONTHLY" or "CAT:<name>", mirroring `Budget.key`). Persisted rather than recomputed,
//  because budget amounts change without history: `carried` is the leftover accumulated as of
//  `periodKey` (the pay-cycle month, as "yyyy-MM" of the cycle's start). Rows exist only while
//  rollover is enabled and are wiped when it's turned off. See `Support/BudgetRolloverMath.swift`.
//

import Foundation
import SwiftData

@Model
final class BudgetRollover {
    /// The budget key this carry-over belongs to: "MONTHLY" or "CAT:<name>".
    @Attribute(.unique) var key: String
    var carried: Decimal
    /// "yyyy-MM" of the pay-cycle start month this `carried` was last rolled to.
    var periodKey: String

    init(key: String, carried: Decimal, periodKey: String) {
        self.key = key
        self.carried = carried
        self.periodKey = periodKey
    }
}
