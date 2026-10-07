//
//  CategoryPickerSheet.swift
//  Budgetty
//
//  Full-screen category chooser: a searchable 3-column grid with a "Your Categories" section (＋New
//  + flat user categories), then any user-made primary groups, then the built-in taxonomy grouped by
//  top-level group. Custom sub-categories and re-homed built-ins fold under their effective parent
//  via `Categories.childNames`. A long-press context menu manages a category in place — edit, re-home
//  ("Move to Group…"), set a budget, or delete. Used when editing a line item's or a bill's category.
//

import SwiftUI
import SwiftData

struct CategoryPickerSheet: View {
    @Binding var selection: String
    /// The name of the item being categorised (the review row), if any — lets the "Suggested for you"
    /// row float a learned-rule match first with a "because you usually…" reason. nil elsewhere.
    var contextName: String? = nil
    /// Called with the chosen category name (in addition to updating the binding).
    var onPicked: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<Category> { $0.isCustom }, sort: \Category.createdAt)
    private var customCategories: [Category]
    /// Recent line items (category + date) the habit ranking reads from, and the learned rules the
    /// context lead reads from — both power the Suggested row (see `CategorySuggester`).
    @Query(sort: \LineItem.createdAt, order: .reverse) private var recentItems: [LineItem]
    @Query private var rules: [CategoryRule]

    @State private var search = ""
    @State private var showCreate = false

    // Context-menu routes.
    @State private var editTarget: Category?
    @State private var moveTarget: NameRoute?
    @State private var budgetTarget: NameRoute?
    @State private var deleteTarget: Category?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    /// Identifiable wrapper so a category *name* can drive `.sheet(item:)`.
    private struct NameRoute: Identifiable { let id: String }

    /// Top-level customs with no children of their own — shown as flat tiles in "Your Categories".
    private var flatCustoms: [Category] {
        customCategories.filter { $0.parent == nil && Categories.childNames(of: $0.name).isEmpty }
    }
    /// Top-level customs that have children — shown as their own group (header + children), like a
    /// built-in group (mockup Fork 1 Option A: the primary is the section's first, tappable tile).
    private var primaryCustoms: [Category] {
        customCategories.filter { $0.parent == nil && !Categories.childNames(of: $0.name).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if search.isEmpty {
                    suggestionRow
                    yourCategoriesSection
                    ForEach(primaryCustoms, id: \.name) { c in
                        gridSection(c.name, names: [c.name] + Categories.childNames(of: c.name))
                    }
                    ForEach(Categories.groups, id: \.name) { group in
                        gridSection(group.name, names: [group.name] + Categories.childNames(of: group.name))
                    }
                } else {
                    gridSection(nil, names: filteredNames)
                }
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CustomCategorySheet(onSaved: { name in selection = name; dismiss() })
            }
            .sheet(item: $editTarget) { cat in
                CustomCategorySheet(editing: cat)
            }
            .sheet(item: $budgetTarget) { route in
                CategoryBudgetSheet(group: route.id)
            }
            .sheet(item: $moveTarget) { route in
                NavigationStack {
                    CategoryParentList(current: route.id, selected: Categories.parentOf(route.id)) { newParent in
                        CategoryOps.setParent(context, name: route.id, to: newParent)
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { moveTarget = nil } } }
                }
                .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Delete this category?",
                                isPresented: Binding(get: { deleteTarget != nil },
                                                     set: { if !$0 { deleteTarget = nil } }),
                                titleVisibility: .visible, presenting: deleteTarget) { cat in
                Button("Delete", role: .destructive) { CategoryOps.deleteCustom(context, cat); deleteTarget = nil }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: { cat in
                if !Categories.childNames(of: cat.name).isEmpty {
                    Text("Its sub-categories are kept and moved to the top level.")
                }
            }
        }
    }

    private var filteredNames: [String] {
        let all = Categories.predefined.map(\.name) + customCategories.map(\.name)
        return all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    // MARK: - Suggested for you (habit-based)

    private var suggestions: CategorySuggester.Ranked {
        CategorySuggester.rank(recentItems.prefix(500).map { (category: $0.category, date: $0.createdAt) })
    }
    /// A learned-rule category for the opened item's name, if any — the context lead.
    private var leadMatch: String? {
        guard let name = contextName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let key = CategoryRule.key(name)
        return rules.first { $0.name == key }?.category
    }
    /// The lead (if any) first, then the ranked categories, de-duped and capped.
    private var suggestionChips: [String] {
        var out: [String] = []
        if let lead = leadMatch { out.append(lead) }
        for name in suggestions.categories where !out.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            out.append(name)
        }
        return Array(out.prefix(CategorySuggester.limit))
    }

    /// The "Suggested for you" / "Common picks" row above the grid (Android parity: `SuggestionRow`).
    @ViewBuilder
    private var suggestionRow: some View {
        let chips = suggestionChips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(verbatim: "✦").font(.system(size: 12, weight: .black)).foregroundStyle(Palette.tint)
                    Text(suggestions.personalized ? "Suggested for you" : "Common picks")
                        .font(.caption2).fontWeight(.bold).textCase(.uppercase).tracking(0.7)
                        .foregroundStyle(Palette.tint)
                }
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(chips, id: \.self) { suggestionChip($0) }
                }
                if let lead = leadMatch, let ctx = contextName?.trimmingCharacters(in: .whitespaces), !ctx.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: "✦").font(.system(size: 11)).foregroundStyle(Palette.tint)
                        Text("Because you usually file \u{2018}\(ctx)\u{2019} as \(Categories.displayName(lead))")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                } else if !suggestions.personalized {
                    Text("These become your own suggestions after a few expenses.")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Divider().padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
    }

    private func suggestionChip(_ name: String) -> some View {
        let isLead = name.caseInsensitiveCompare(leadMatch ?? "\u{0}") == .orderedSame
        let isSelected = name.caseInsensitiveCompare(selection) == .orderedSame
        return Button {
            selection = name; onPicked?(name); dismiss()
        } label: {
            HStack(spacing: 6) {
                Text(Categories.emoji(for: name)).font(.system(size: 14))
                Text(Categories.displayName(name)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.label).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(isLead || isSelected ? Palette.tintSoft : Palette.fill))
            .overlay(Capsule().strokeBorder(isLead || isSelected ? Palette.tint : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var yourCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Your Categories")
            LazyVGrid(columns: columns, spacing: 10) {
                Button { showCreate = true } label: { newTile }.buttonStyle(.plain)
                ForEach(flatCustoms, id: \.name) { cat in
                    tile(cat.name)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
    }

    private func gridSection(_ title: String?, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { sectionHeader(title) } else { Color.clear.frame(height: 8) }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(names, id: \.self) { name in
                    tile(name)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private func tile(_ name: String) -> some View {
        let custom = customCategories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        return Button {
            selection = name
            onPicked?(name)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(argb: Categories.color(for: name)))
                    .frame(width: 44, height: 44)
                    .overlay(Text(Categories.emoji(for: name)).font(.system(size: 22)))
                Text(Categories.displayName(name)).font(.caption).fontWeight(.medium).foregroundStyle(Palette.label)
                    .multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 8)
            .contentCard(cornerRadius: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(name.caseInsensitiveCompare(selection) == .orderedSame ? Palette.tint : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu { menu(for: name, custom: custom) }
    }

    @ViewBuilder
    private func menu(for name: String, custom: Category?) -> some View {
        if let custom {
            Button { editTarget = custom } label: { Label("Edit", systemImage: "pencil") }
        }
        Button { moveTarget = NameRoute(id: name) } label: { Label("Move to Group…", systemImage: "folder") }
        Button { budgetTarget = NameRoute(id: Categories.groupOf(name)) } label: {
            Label("Set Budget…", systemImage: "eurosign.circle")
        }
        if let custom {
            Divider()
            Button(role: .destructive) { deleteTarget = custom } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var newTile: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.tintSoft)
                .frame(width: 44, height: 44)
                .overlay(Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.tint))
            Text("New").font(.caption).fontWeight(.semibold).foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(Palette.tint)
        )
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
            .foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 36).padding(.top, 8)
    }
}
