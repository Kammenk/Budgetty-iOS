//
//  CustomCategorySheet.swift
//  Budgetty
//
//  Create or edit a user category: live preview, name, emoji grid, color swatches, and the free/
//  premium cap note. Mirrors Android's custom-category limits (3 free / 10 premium).
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
    @State private var confirmDelete = false

    private let emojiColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    private var limit: Int { premium ? Categories.maxCustomLimit : Categories.freeCustomLimit }
    private var atLimit: Bool { editing == nil && customCategories.count >= limit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview
                    field("Name") {
                        TextField("Category name", text: $name)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, 16).frame(height: 44)
                            .inputField(cornerRadius: 12)
                    }
                    field("Emoji") { emojiGrid }
                    field("Color") { colorGrid }
                    premiumNote
                    if editing != nil {
                        Button("Delete Category", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .contentCard(cornerRadius: 14)
                    }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(editing == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteCategory() }
            }
            .onAppear(perform: loadExisting)
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !atLimit
    }

    private var preview: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(argb: colorArgb))
            .frame(width: 72, height: 72)
            .overlay(Text(emoji).font(.system(size: 34)))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
    }

    private var emojiGrid: some View {
        LazyVGrid(columns: emojiColumns, spacing: 6) {
            ForEach(Categories.iconChoices, id: \.self) { e in
                Button { emoji = e } label: {
                    Text(e).font(.system(size: 22))
                        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .background(e == emoji ? Palette.tintSoft : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .contentCard(cornerRadius: 14)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: colorColumns, spacing: 12) {
            ForEach(Categories.palette, id: \.self) { c in
                Button { colorArgb = c } label: {
                    Circle().fill(Color(argb: c)).frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Palette.tint, lineWidth: c == colorArgb ? 3 : 0)
                            .padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .contentCard(cornerRadius: 14)
    }

    private var premiumNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.tint)
            Text(atLimit
                 ? "You've reached your \(limit) custom categories. Upgrade to Premium for \(Categories.maxCustomLimit)."
                 : "\(premium ? "Premium" : "Free") plan: \(customCategories.count) of \(limit) custom categories.")
                .font(.caption).foregroundStyle(Palette.tint)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption).fontWeight(.semibold).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel).padding(.leading, 16)
            content()
        }
    }

    private func loadExisting() {
        guard let e = editing else { return }
        name = e.name; emoji = e.icon.isEmpty ? "🥬" : e.icon; colorArgb = e.colorArgb
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let e = editing {
            e.name = trimmed; e.icon = emoji; e.colorArgb = colorArgb
        } else {
            context.insert(Category(name: trimmed, colorArgb: colorArgb, icon: emoji,
                                    isCustom: true, createdAt: .now))
        }
        try? context.save()
        onSaved(trimmed)
        dismiss()
    }

    private func deleteCategory() {
        if let e = editing { context.delete(e); try? context.save() }
        dismiss()
    }
}
