//
//  TagOps.swift
//  Budgetty
//
//  Free-form tag mutations with the same semantics as Android's `TagRepository`: ensure a catalog
//  row exists, set the exact tag set on a line item, and the Manage-screen rename / merge / delete.
//  iOS has no tag ViewModel, so (like `CategoryOps`) these live here and are called from the review
//  screen and the Manage Tags screen. Reads (catalog, counts, recency) come straight from `@Query`
//  over `Tag` in the views — a tag's `items.count` is its transaction count, mirroring `tagCounts`.
//
//  Names are normalized through `Tag.normalize` before anything is stored, so every lookup and link
//  agrees on the same key.
//

import Foundation
import SwiftData

enum TagOps {

    /// The catalog row for `rawName` (normalized), creating and inserting it the first time it's seen.
    /// Returns nil only when the name normalizes to empty.
    @MainActor
    @discardableResult
    static func ensure(_ context: ModelContext, name rawName: String) -> Tag? {
        let key = Tag.normalize(rawName)
        guard !key.isEmpty else { return nil }
        if let existing = tag(context, named: key) { return existing }
        let tag = Tag(name: key)
        context.insert(tag)
        return tag
    }

    /// Replace `item`'s tags with the given names (normalized, de-duplicated, order preserved),
    /// creating any catalog rows that don't exist yet. Used by the save path once a line item exists.
    @MainActor
    static func setTags(_ context: ModelContext, on item: LineItem, names: [String]) {
        var seen = Set<String>()
        let keys = names
            .map { Tag.normalize($0) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        item.tags = keys.compactMap { ensure(context, name: $0) }
    }

    /// Rename `from` to `rawTo`, or merge into it when that name already exists — one operation either
    /// way: make sure the destination is in the catalog, move `from`'s links onto it (keeping items
    /// that already carried the destination), then drop `from`. Line items are never deleted.
    @MainActor
    static func renameOrMerge(_ context: ModelContext, from: String, to rawTo: String) {
        let to = Tag.normalize(rawTo)
        guard !to.isEmpty, to != from else { return }
        guard let source = tag(context, named: from), let dest = ensure(context, name: to) else { return }
        for item in source.items where !item.tags.contains(where: { $0.name == to }) {
            item.tags.append(dest)
        }
        context.delete(source)
        try? context.save()
    }

    /// Remove a tag from the catalog; its links nullify away, the line items are untouched.
    @MainActor
    static func delete(_ context: ModelContext, name: String) {
        guard let t = tag(context, named: name) else { return }
        context.delete(t)
        try? context.save()
    }

    // MARK: - Helpers

    private static func tag(_ context: ModelContext, named name: String) -> Tag? {
        (try? context.fetch(FetchDescriptor<Tag>(predicate: #Predicate { $0.name == name })))?.first
    }
}
