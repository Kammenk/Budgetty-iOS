//
//  Seed.swift
//  Budgetty
//
//  First-launch seeding of the predefined categories, mirroring Android's `seedCategories`.
//  Idempotent: inserts only the built-ins that are missing, so it is safe to run on every launch
//  and never clobbers a user's custom categories.
//

import Foundation
import SwiftData

enum Seed {
    /// Insert any predefined categories not already present. Custom categories are left untouched.
    @MainActor
    static func categoriesIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        let existingNames = Set(existing.map { $0.name.lowercased() })

        var inserted = 0
        for c in Categories.predefined where !existingNames.contains(c.name.lowercased()) {
            context.insert(
                Category(name: c.name, colorArgb: c.colorArgb, icon: c.emoji, isCustom: false)
            )
            inserted += 1
        }
        if inserted > 0 {
            try? context.save()
        }
    }
}
