//
//  Tag.swift
//  Budgetty
//
//  Android's `TagEntity` + `TransactionTagEntity` join, modeled as a SwiftData many-to-many between
//  `LineItem` and `Tag`. A free-form tag is orthogonal to the category taxonomy: a line item has
//  exactly one category but any number of tags, and tags never change categorisation or the learned
//  category rules.
//
//  The catalog is its own table (not derived from the links) so a tag can exist before anything
//  carries it — e.g. a Travel-mode trip tag created before its first expense. Deleting a line item
//  nullifies its links (the Tag catalog row stays); deleting a Tag nullifies the links too but never
//  deletes the line items (see `TagOps`).
//

import Foundation
import SwiftData

@Model
final class Tag {
    /// The normalized key (see `normalize`): trimmed, lower-cased, a leading '#' dropped, spaces turned
    /// to hyphens, anything that isn't a letter/number/hyphen removed. Lower-casing is Unicode-aware so
    /// Cyrillic ("#дача") folds correctly, exactly like the learned category-rule keys.
    @Attribute(.unique) var name: String

    /// Creation time; set the first time a name is seen. Orders nothing user-facing — counts drive the
    /// Manage list — but preserved across backup like Android's `createdAt`.
    var createdAt: Date

    /// The line items carrying this tag. `.nullify` so deleting a tag drops the links, never the items.
    @Relationship(deleteRule: .nullify, inverse: \LineItem.tags)
    var items: [LineItem]

    init(name: String, createdAt: Date = .now) {
        self.name = name
        self.createdAt = createdAt
        self.items = []
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-")
        return set
    }()

    /// The canonical key for `raw`, mirroring Android's `TagEntity.normalize` and the mockup's JS:
    /// trimmed, lower-cased, leading '#'s stripped, internal whitespace turned to single hyphens, and
    /// any character that isn't a Unicode letter/number or a hyphen removed. Unicode-aware, so
    /// "Work Trip" → "work-trip" and "#Дача" → "дача". Returns "" for input with no usable chars.
    static func normalize(_ raw: String) -> String {
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var trimmed = Substring(lowered)
        while trimmed.first == "#" { trimmed = trimmed.dropFirst() }
        let hyphenated = trimmed.replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
        let kept = hyphenated.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }
}
