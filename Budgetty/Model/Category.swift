//
//  Category.swift
//  Budgetty
//
//  Android's CategoryEntity — a spending category and how it renders across the app.
//  Predefined categories are seeded on first launch; users may add their own (`isCustom`).
//

import Foundation
import SwiftData

@Model
final class Category {
    /// Category name — the identity used everywhere a category is referenced.
    @Attribute(.unique) var name: String

    /// Packed 0xAARRGGBB color (use `Color(argb:)` to render).
    var colorArgb: Int

    /// Emoji icon.
    var icon: String

    /// True for user-created categories — drives the "Your categories" section and the create cap.
    var isCustom: Bool

    /// Creation time; orders custom categories by when they were added. Distant past for seeded ones.
    var createdAt: Date

    /// Optional parent (group) this category is nested under, stored by name. `nil` = default:
    /// a built-in uses its code-defined group, a custom is top-level. A non-nil value re-homes the
    /// category under that parent. Mirrors Android's nullable `parent` column (DB v20). Adding this
    /// optional attribute is lightweight-migratable — existing rows stay `nil` and grouping keeps
    /// resolving from code until a user nests something.
    var parent: String?

    init(
        name: String,
        colorArgb: Int,
        icon: String = "",
        isCustom: Bool = false,
        createdAt: Date = .distantPast,
        parent: String? = nil
    ) {
        self.name = name
        self.colorArgb = colorArgb
        self.icon = icon
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.parent = parent
    }
}
