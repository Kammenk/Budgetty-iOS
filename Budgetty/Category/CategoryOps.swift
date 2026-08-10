//
//  CategoryOps.swift
//  Budgetty
//
//  Category create / rename / delete / re-home with the reference cascades Android performs in its
//  ViewModels + Room migrations. iOS has no category ViewModel, so these live here and are called
//  from the create/edit sheet and the picker.
//
//  Every category is referenced BY NAME (there is no id), so a rename or delete must repoint the
//  category string on LineItem / Recurring / CategoryRule and the "CAT:<name>" Budget key — the same
//  value-repoint `Migrations.splitSubscriptionsAndServices` does for the one-off split. Sub-category
//  moves also rewrite the nullable `parent` on child rows, keeping the hierarchy two levels deep.
//

import Foundation
import SwiftData

enum CategoryOps {

    /// Re-read the stored rows into `Categories`' caches and refresh the widget snapshot. Call after
    /// any mutation so grouping, custom rendering and widgets stay in sync.
    @MainActor
    static func refreshTaxonomy(_ context: ModelContext) {
        Categories.setStored((try? context.fetch(FetchDescriptor<Category>())) ?? [])
        WidgetSharing.update(from: context)
    }

    // MARK: - Create / edit

    /// Create a custom category, or edit `editing` in place. A rename cascades to every reference and
    /// to child categories (children follow); giving a category a parent while it has children of its
    /// own releases those children to top-level (two levels only). `parent` is the chosen group name,
    /// or nil for top-level.
    @MainActor
    static func saveCustom(_ context: ModelContext, editing: Category?, name: String,
                           emoji: String, colorArgb: Int, parent: String?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let newParent = normalizedParent(parent, for: trimmed)

        if let e = editing {
            // Compare EXACTLY (not case-insensitively): a case-only rename ("Coffee" → "COFFEE") is
            // still a rename, so its references must repoint too — otherwise transactions / rules /
            // budget / children keep the old-cased name and detach from the renamed category. (iOS
            // edits the row in place, so unlike Android there's no duplicate row — only stale refs.)
            // Android parity.
            if e.name != trimmed {
                renameReferences(context, from: e.name, to: trimmed)   // repoint refs + children
            }
            e.name = trimmed
            e.icon = emoji
            e.colorArgb = colorArgb
            e.parent = newParent
        } else {
            context.insert(Category(name: trimmed, colorArgb: colorArgb, icon: emoji,
                                    isCustom: true, createdAt: .now, parent: newParent))
        }
        if newParent != nil { orphanChildren(context, of: trimmed) }   // nesting releases own children
        try? context.save()
        refreshTaxonomy(context)
    }

    // MARK: - Delete

    /// Delete a custom category: its transactions/recurring/rules fall back to "Other", its budget row
    /// is removed, and its children are promoted to top-level (kept, not deleted). Android's
    /// `deleteCustomCategory`.
    @MainActor
    static func deleteCustom(_ context: ModelContext, _ category: Category) {
        let name = category.name
        repointReferences(context, from: name, to: Categories.other)
        removeBudget(context, for: name)
        orphanChildren(context, of: name)   // children promoted to top-level
        context.delete(category)
        try? context.save()
        refreshTaxonomy(context)
    }

    // MARK: - Re-home (shared by the parent selector and the built-in "Move to group")

    /// Set (or clear, with nil) the parent of `name`. Works for a custom or a built-in — built-ins are
    /// seeded as rows, so the override is stored on the existing row. Nesting a category that has
    /// children releases those children to top-level (two levels only).
    @MainActor
    static func setParent(_ context: ModelContext, name: String, to newParent: String?) {
        let resolved = normalizedParent(newParent, for: name)
        guard let row = row(context, named: name) else { return }
        row.parent = resolved
        if resolved != nil { orphanChildren(context, of: name) }
        try? context.save()
        refreshTaxonomy(context)
    }

    // MARK: - Helpers

    /// A parent is only meaningful if it's non-empty and not the category itself.
    private static func normalizedParent(_ parent: String?, for name: String) -> String? {
        guard let p = parent?.trimmingCharacters(in: .whitespaces), !p.isEmpty,
              p.caseInsensitiveCompare(name) != .orderedSame else { return nil }
        return p
    }

    private static func row(_ context: ModelContext, named name: String) -> Category? {
        (try? context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.name == name })))?.first
    }

    /// Every stored row whose parent is `parent` (case-insensitive). The category table is tiny, so an
    /// in-memory filter is simpler and safer than a `#Predicate` over the optional `parent`.
    private static func childRows(_ context: ModelContext, of parent: String) -> [Category] {
        ((try? context.fetch(FetchDescriptor<Category>())) ?? [])
            .filter { $0.parent?.caseInsensitiveCompare(parent) == .orderedSame }
    }

    /// Send `parent`'s children back to top-level (parent → nil). Used both when promoting a deleted
    /// primary's children and when releasing a newly-nested category's own children.
    private static func orphanChildren(_ context: ModelContext, of parent: String) {
        for c in childRows(context, of: parent) { c.parent = nil }
    }

    /// Rename cascade: repoint references old→new, move its budget key, and pull its children along.
    private static func renameReferences(_ context: ModelContext, from old: String, to new: String) {
        repointReferences(context, from: old, to: new)
        moveBudget(context, from: old, to: new)
        for c in childRows(context, of: old) { c.parent = new }
    }

    /// Repoint the category string on LineItem / Recurring / CategoryRule (the migration's pattern).
    private static func repointReferences(_ context: ModelContext, from old: String, to new: String) {
        for i in (try? context.fetch(FetchDescriptor<LineItem>(predicate: #Predicate { $0.category == old }))) ?? [] {
            i.category = new
        }
        for r in (try? context.fetch(FetchDescriptor<Recurring>(predicate: #Predicate { $0.category == old }))) ?? [] {
            r.category = new
        }
        for r in (try? context.fetch(FetchDescriptor<CategoryRule>(predicate: #Predicate { $0.category == old }))) ?? [] {
            r.category = new
        }
    }

    /// Move the "CAT:<name>" budget key old→new. `Budget.key` is unique, so drop the stale row on a
    /// collision (Android's `UPDATE OR REPLACE`).
    private static func moveBudget(_ context: ModelContext, from old: String, to new: String) {
        let oldKey = Budget.categoryKey(old)
        let newKey = Budget.categoryKey(new)
        let budgets = (try? context.fetch(FetchDescriptor<Budget>(
            predicate: #Predicate { $0.key == oldKey || $0.key == newKey }))) ?? []
        guard let stale = budgets.first(where: { $0.key == oldKey }) else { return }
        if budgets.contains(where: { $0.key == newKey }) { context.delete(stale) }
        else { stale.key = newKey }
    }

    private static func removeBudget(_ context: ModelContext, for name: String) {
        let key = Budget.categoryKey(name)
        for b in (try? context.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.key == key }))) ?? [] {
            context.delete(b)
        }
    }
}
