//
//  CategoryParentList.swift
//  Budgetty
//
//  The shared "choose a parent group" list: "None (top-level)" first, then the user's own top-level
//  custom categories, then the built-in groups. `current` is excluded (a category can't parent
//  itself) and only top-level categories appear (a sub-category can't be a parent — two levels only).
//  Used by the create/edit sheet's Parent row and the picker's "Move to Group…" action; the caller
//  decides what a pick means via `onPick` (store on the draft, or re-home immediately).
//

import SwiftUI
import SwiftData

struct CategoryParentList: View {
    let current: String
    let selected: String?
    var onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { $0.isCustom }, sort: \Category.createdAt)
    private var customs: [Category]

    private var primaries: [String] {
        customs.filter { $0.parent == nil && $0.name.caseInsensitiveCompare(current) != .orderedSame }
            .map(\.name)
    }
    private var groups: [String] {
        Categories.groups.map(\.name)
            .filter { $0 != Categories.other && $0.caseInsensitiveCompare(current) != .orderedSame }
    }

    var body: some View {
        List {
            Section {
                row(title: String(localized: "None (top-level)"), emoji: nil, value: nil)
            }
            if !primaries.isEmpty {
                Section("Your categories") {
                    ForEach(primaries, id: \.self) {
                        row(title: Categories.displayName($0), emoji: Categories.emoji(for: $0), value: $0)
                    }
                }
            }
            Section("Groups") {
                ForEach(groups, id: \.self) {
                    row(title: Categories.displayName($0), emoji: Categories.emoji(for: $0), value: $0)
                }
            }
        }
        .navigationTitle("Parent category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isSelected(_ value: String?) -> Bool {
        switch (selected, value) {
        case (nil, nil): return true
        case let (s?, v?): return s.caseInsensitiveCompare(v) == .orderedSame
        default: return false
        }
    }

    private func row(title: String, emoji: String?, value: String?) -> some View {
        Button {
            onPick(value)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let emoji {
                    Text(emoji)
                } else {
                    Image(systemName: "minus.circle").foregroundStyle(Palette.secondaryLabel)
                }
                Text(title).foregroundStyle(Palette.label)
                Spacer()
                if isSelected(value) {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.tint)
                }
            }
        }
    }
}
