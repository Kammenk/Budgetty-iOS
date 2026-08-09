//
//  CustomCategorySheet.swift
//  Budgetty
//
//  Create or edit a user category: a live preview + name, an optional parent (sub-category grouping),
//  the expanded searchable icon catalog (EmojiCatalog), and colour — plus the free/premium cap note.
//  Save & delete cascade through `CategoryOps` (a rename repoints references + pulls children along;
//  a delete falls back to "Other" and promotes children to top-level). Mirrors Android's screen.
//

import SwiftUI
import SwiftData

struct CustomCategorySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.premium) private var premium = false

    @Query(filter: #Predicate<Category> { $0.isCustom }) private var customCategories: [Category]

    /// When set, we're editing an existing custom category.
    var editing: Category?
    /// Called with the saved category name (so the picker can select it).
    var onSaved: (String) -> Void = { _ in }

    @State private var name = ""
    @State private var emoji = "🥬"
    @State private var colorArgb = Categories.defaultColor
    @State private var parent: String?
    @State private var query = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)
    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    private var limit: Int { premium ? Categories.maxCustomLimit : Categories.freeCustomLimit }
    private var atLimit: Bool { editing == nil && customCategories.count >= limit }
    private var results: [EmojiCatalog.Entry] { EmojiCatalog.search(query) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                headerRow
                organisationRow
                iconLabel
                iconCard
                colorCard
                footer
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.groupedBackground)
            .navigationTitle(editing == nil ? "New category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .confirmationDialog("Delete this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteCategory() }
            } message: {
                if hasChildren { Text("Its sub-categories are kept and moved to the top level.") }
            }
            .onAppear(perform: loadExisting)
        }
    }

    // MARK: - Header (preview + name)

    private var headerRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(argb: colorArgb))
                .frame(width: 64, height: 64)
                .overlay(Text(emoji).font(.system(size: 31)))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.caption2).fontWeight(.semibold).textCase(.uppercase)
                    .foregroundStyle(Palette.secondaryLabel)
                TextField("Category name", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 14).frame(height: 40)
                    .inputField(cornerRadius: 11)
            }
        }
    }

    // MARK: - Organisation (parent)

    private var organisationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Organisation").font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel).padding(.leading, 4)
            NavigationLink {
                CategoryParentList(current: currentName, selected: parent, onPick: { parent = $0 })
            } label: {
                HStack(spacing: 8) {
                    Text("Parent category").foregroundStyle(Palette.label)
                    Spacer()
                    Text(parent.map { Categories.displayName($0) } ?? String(localized: "None (top-level)"))
                        .foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .padding(.horizontal, 16).frame(height: 48)
                .contentCard(cornerRadius: 12)
            }
            .buttonStyle(.plain)
            if editing != nil && hasChildren {
                Text("Nesting this category moves its sub-categories to the top level.")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel).padding(.leading, 4)
            }
        }
    }

    // MARK: - Icon catalog

    private var iconLabel: some View {
        HStack {
            Text("Icon").font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text(query.isEmpty
                 ? "\(EmojiCatalog.all.count) icons · \(EmojiCatalog.sections.count) sections"
                 : String(localized: "Searching"))
                .font(.caption2).foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 4)
    }

    private var iconCard: some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Palette.separator)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if query.isEmpty {
                        ForEach(EmojiCatalog.sections, id: \.title) { section in
                            iconHeader(section.title, trailing: "\(section.entries.count)")
                            iconGrid(section.entries)
                        }
                    } else if !results.isEmpty {
                        iconHeader(String(localized: "Results"),
                                   trailing: results.count == 1
                                   ? String(localized: "1 match")
                                   : String(localized: "\(results.count) matches"))
                        iconGrid(results)
                    } else {
                        noResults
                    }
                }
                .padding(10)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .contentCard(cornerRadius: 14)
        .frame(maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.secondaryLabel)
            TextField("Search icons", text: $query)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.tertiaryLabel)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).frame(height: 40)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }

    private func iconHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.caption2).fontWeight(.semibold).textCase(.uppercase).tracking(0.5)
                .foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Text(trailing).font(.caption2).foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 4).padding(.top, 4)
    }

    private func iconGrid(_ entries: [EmojiCatalog.Entry]) -> some View {
        LazyVGrid(columns: iconColumns, spacing: 4) {
            ForEach(entries, id: \.emoji) { entry in
                Button { emoji = entry.emoji } label: {
                    Text(entry.emoji).font(.system(size: 22))
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .background(entry.emoji == emoji ? Color(argb: colorArgb) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(entry.emoji == emoji ? 0.75 : 0), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 26))
                .foregroundStyle(Palette.tertiaryLabel)
            Text("No icons match “\(query)”").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Text("Try a word like coffee, gym, parking or rent.")
                .font(.caption).foregroundStyle(Palette.tertiaryLabel).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 24)
    }

    // MARK: - Color

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color").font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel).padding(.leading, 4)
            LazyVGrid(columns: colorColumns, spacing: 12) {
                ForEach(Categories.palette, id: \.self) { c in
                    Button { colorArgb = c } label: {
                        Circle().fill(Color(argb: c)).frame(width: 34, height: 34)
                            .overlay(Circle().strokeBorder(Palette.tint, lineWidth: c == colorArgb ? 3 : 0).padding(-3))
                    }.buttonStyle(.plain)
                }
            }
            .padding(14).contentCard(cornerRadius: 14)
        }
    }

    // MARK: - Footer (cap note + delete)

    private var footer: some View {
        VStack(spacing: 12) {
            premiumNote
            if editing != nil {
                Button("Delete Category", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity).padding(.vertical, 12).contentCard(cornerRadius: 14)
            }
        }
    }

    private var premiumNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.tint)
            Text(atLimit
                 ? "You've reached your \(limit) custom categories. Upgrade to Premium for unlimited."
                 : premium
                 ? "Premium plan: \(customCategories.count) custom categories, no limit."
                 : "Free plan: \(customCategories.count) of \(limit) custom categories.")
                .font(.caption).foregroundStyle(Palette.tint)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - State

    /// The name we're editing under — the typed name if present, else the row's existing name. Used to
    /// exclude the category itself from the parent options.
    private var currentName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? (editing?.name ?? "") : t
    }

    private var hasChildren: Bool {
        guard let e = editing else { return false }
        return !Categories.childNames(of: e.name).isEmpty
    }

    /// True if the (changed) name duplicates another category — the name is the unique identity, so a
    /// clash would collide on save.
    private var nameCollides: Bool {
        let t = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return false }
        if let e = editing, e.name.lowercased() == t { return false }
        let existing = Set(Categories.predefined.map { $0.name.lowercased() }
                           + customCategories.map { $0.name.lowercased() })
        return existing.contains(t)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !atLimit && !nameCollides
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let e = editing else { return }
        name = e.name
        emoji = e.icon.isEmpty ? "🥬" : e.icon
        colorArgb = e.colorArgb
        parent = e.parent
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        CategoryOps.saveCustom(context, editing: editing, name: trimmed,
                               emoji: emoji, colorArgb: colorArgb, parent: parent)
        onSaved(trimmed)
        dismiss()
    }

    private func deleteCategory() {
        if let e = editing { CategoryOps.deleteCustom(context, e) }
        dismiss()
    }
}
