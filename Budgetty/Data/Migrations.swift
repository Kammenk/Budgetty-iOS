//
//  Migrations.swift
//  Budgetty
//
//  One-off data fix-ups for stores written by an older build. SwiftData migrates the *schema* on
//  its own; these repoint *values* it can't know about — the same job Android does in numbered Room
//  migrations, which is why each one names its Android counterpart.
//
//  Every step is idempotent: it matches on the old value, so once it has run there is nothing left
//  to match and re-running is a no-op. They are cheap enough to run on each launch.
//

import Foundation
import SwiftData

enum Migrations {
    /// Android `MIGRATION_17_18`: splits the sub-category "Subscriptions & Services" into
    /// "Subscriptions" and "Services". The old name sat inside a group called "Services &
    /// Subscriptions" — near-identical and unreadable in a picker.
    ///
    /// "Services" arrives via the normal seed (no work here); everything below repoints what already
    /// referenced the old name, which is stored as the category *name* — there is no id — so a
    /// rename is the whole migration. Everything lands on "Subscriptions": the old category covered
    /// both meanings and subscriptions are the far more common recurring line, so re-filing a
    /// genuine one-off service is a two-tap edit, whereas splitting by guesswork isn't reversible.
    ///
    /// ⚠️ Must run **before** `Seed.categoriesIfNeeded`. Seeding inserts "Subscriptions" as a fresh
    /// row; if it went first, the rename below would always hit the collision branch and discard the
    /// old row — losing the colour and any `isCustom`/`createdAt` the user's row carried.
    @MainActor
    static func splitSubscriptionsAndServices(_ context: ModelContext) {
        let old = "Subscriptions & Services"
        let new = "Subscriptions"

        var touched = false

        // `Category.name` is @Attribute(.unique), so a rename can collide if the new category already
        // exists (a scan can return "Subscriptions" as soon as the Cloud Function's category list is
        // deployed, before this build ever launches). Dropping the stale row is Android's
        // `UPDATE OR REPLACE`, and leaves exactly one row either way.
        let categories = (try? context.fetch(
            FetchDescriptor<Category>(predicate: #Predicate { $0.name == old || $0.name == new })
        )) ?? []
        if let stale = categories.first(where: { $0.name == old }) {
            if categories.contains(where: { $0.name == new }) {
                context.delete(stale)
            } else {
                stale.name = new
            }
            touched = true
        }

        // The three tables that store a category by name.
        for item in (try? context.fetch(
            FetchDescriptor<LineItem>(predicate: #Predicate { $0.category == old })
        )) ?? [] {
            item.category = new
            touched = true
        }
        for recurring in (try? context.fetch(
            FetchDescriptor<Recurring>(predicate: #Predicate { $0.category == old })
        )) ?? [] {
            recurring.category = new
            touched = true
        }
        for rule in (try? context.fetch(
            FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.category == old })
        )) ?? [] {
            rule.category = new
            touched = true
        }

        // Per-category budgets are keyed "CAT:<name>", so the key moves too — and `Budget.key` is
        // unique, so the same collision rule applies.
        let oldKey = Budget.categoryKey(old)
        let newKey = Budget.categoryKey(new)
        let budgets = (try? context.fetch(
            FetchDescriptor<Budget>(predicate: #Predicate { $0.key == oldKey || $0.key == newKey })
        )) ?? []
        if let stale = budgets.first(where: { $0.key == oldKey }) {
            if budgets.contains(where: { $0.key == newKey }) {
                context.delete(stale)
            } else {
                stale.key = newKey
            }
            touched = true
        }

        if touched {
            try? context.save()
        }
    }
}
