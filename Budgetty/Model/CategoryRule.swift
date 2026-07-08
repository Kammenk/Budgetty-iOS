//
//  CategoryRule.swift
//  Budgetty
//
//  Android's CategoryRuleEntity — a learned "this item name → this category" preference, applied
//  automatically when a receipt is scanned so a user's category choice sticks across future receipts.
//

import Foundation
import SwiftData

@Model
final class CategoryRule {
    /// Normalized match key: trimmed + lower-cased (Unicode-aware, so Cyrillic folds correctly too).
    @Attribute(.unique) var name: String
    var category: String

    init(name: String, category: String) {
        self.name = name
        self.category = category
    }

    /// The canonical match key for a raw item name: trimmed + lower-cased.
    static func key(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
