//
//  IgnoredSubscription.swift
//  Budgetty
//
//  A merchant the user dismissed from subscription detection (Android's IgnoredSubscriptionEntity).
//  Keyed by the normalized merchant name — dismissed, never deleted, because detection would just
//  surface it again from the same receipts.
//

import Foundation
import SwiftData

@Model
final class IgnoredSubscription {
    @Attribute(.unique) var merchant: String
    var ignoredAt: Date

    init(merchant: String, ignoredAt: Date = .now) {
        self.merchant = merchant
        self.ignoredAt = ignoredAt
    }
}
