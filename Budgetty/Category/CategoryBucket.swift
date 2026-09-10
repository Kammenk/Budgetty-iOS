//
//  CategoryBucket.swift
//  Budgetty
//
//  Which bucket of the 50/30/20 rule a category's spend counts toward, for the Insights
//  Needs / Wants / Savings split. Ported from Android's category/CategoryBucket.kt.
//

import Foundation

/// The 50/30/20 bucket a category's spend counts toward:
/// - `need`    — the things you'd keep paying in a lean month (housing, utilities, groceries,
///               transport, insurance, health). Target 50% of income.
/// - `want`    — discretionary spending (dining, shopping, entertainment, travel). Target 30%.
/// - `savings` — money set aside (savings-goal transfers, investments). Target 20%.
///
/// Every category resolves to a bucket: a built-in from `Categories.defaultBucket(of:)` (its group's
/// default, with a few per-category exceptions), a sub-category inherits its parent's, and a user can
/// override any of them in Manage categories. Persisted as its `rawValue` on the `Category` row — the
/// tokens deliberately match Android's enum names (NEED / WANT / SAVINGS) so a cross-platform backup
/// round-trips the tag. `allCases` order (need, want, savings) matches the Android enum's ordinals,
/// so the Manage-categories segmented control preselects the right segment on both platforms.
enum CategoryBucket: String, CaseIterable, Identifiable, Equatable {
    case need = "NEED"
    case want = "WANT"
    case savings = "SAVINGS"

    var id: String { rawValue }
}
