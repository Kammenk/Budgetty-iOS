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

    init(
        name: String,
        colorArgb: Int,
        icon: String = "",
        isCustom: Bool = false,
        createdAt: Date = .distantPast
    ) {
        self.name = name
        self.colorArgb = colorArgb
        self.icon = icon
        self.isCustom = isCustom
        self.createdAt = createdAt
    }
}
