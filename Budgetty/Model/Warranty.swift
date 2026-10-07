//
//  Warranty.swift
//  Budgetty
//
//  Android's `WarrantyEntity` — a tracked product warranty: what was bought, when, and for how long
//  it's covered. The expiry is derived (purchaseDate + durationMonths), not stored, so a length edit
//  never leaves a stale date. `receiptId` optionally links the warranty to the receipt it came from
//  (0 = none); no photo is kept, matching the no-image-storage rule.
//

import Foundation
import SwiftData

@Model
final class Warranty {
    var name: String
    var emoji: String
    var store: String
    /// Spending category (for the emoji/eligibility heuristic); empty when unknown.
    var category: String
    /// Purchase date at local midnight.
    var purchaseDate: Date
    /// Warranty length in whole months.
    var durationMonths: Int
    /// Free-text coverage detail (e.g. "Battery covered 1 yr"); optional.
    var coverageNote: String
    /// The receipt this warranty came from (Receipt.createdAt as epoch seconds); 0 when manual.
    var receiptId: Double
    var createdAt: Date

    init(name: String, emoji: String = "🛡️", store: String = "", category: String = "",
         purchaseDate: Date, durationMonths: Int, coverageNote: String = "",
         receiptId: Double = 0, createdAt: Date = .now) {
        self.name = name
        self.emoji = emoji
        self.store = store
        self.category = category
        self.purchaseDate = purchaseDate
        self.durationMonths = durationMonths
        self.coverageNote = coverageNote
        self.receiptId = receiptId
        self.createdAt = createdAt
    }
}
