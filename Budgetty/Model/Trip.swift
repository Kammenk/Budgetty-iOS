//
//  Trip.swift
//  Budgetty
//
//  Android's `TripEntity` — "Travel mode". A trip is nothing more than metadata wrapped around one
//  tag: a name, an optional date span, an optional budget and an active flag. Everything that already
//  works on tags (the History filter, Insights "By tag", rename/merge) keeps working on a trip's
//  expenses for free. While a trip is `active`, the review screen pre-applies its tag to every new
//  expense (removable per expense), which is the whole point of the mode.
//
//  `tag` is a normalized `Tag.normalize` key that also lives in the `tags` catalog — kept here as a
//  plain string (not a relationship) so a trip survives even if its tag is later deleted from Manage,
//  and so the catalog row can be created independently. Only one trip is active at a time (`TripOps`
//  deactivates any other when a new one starts).
//

import Foundation
import SwiftData

@Model
final class Trip {
    var name: String
    /// The normalized tag key this trip owns (also a `Tag` catalog row). Not a relationship on purpose.
    var tag: String
    var startDate: Date?
    var endDate: Date?
    var budgetAmount: Decimal?
    /// True while this is the running trip. At most one trip is active (enforced in `TripOps.start`).
    var active: Bool
    var createdAt: Date
    /// nil while active; set to the end moment when the trip is ended (drives past-trip order).
    var endedAt: Date?

    init(
        name: String,
        tag: String,
        startDate: Date? = nil,
        endDate: Date? = nil,
        budgetAmount: Decimal? = nil,
        active: Bool = true,
        createdAt: Date = .now,
        endedAt: Date? = nil
    ) {
        self.name = name
        self.tag = tag
        self.startDate = startDate
        self.endDate = endDate
        self.budgetAmount = budgetAmount
        self.active = active
        self.createdAt = createdAt
        self.endedAt = endedAt
    }

    var hasDates: Bool { startDate != nil && endDate != nil }
    var hasBudget: Bool { (budgetAmount ?? 0) > 0 }
}
