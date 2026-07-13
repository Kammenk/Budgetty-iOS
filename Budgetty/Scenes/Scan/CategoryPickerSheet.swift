//
//  CategoryPickerSheet.swift
//  Budgetty
//
//  Full-screen category chooser: a searchable 3-column grid with a "Your Categories" section (＋New
//  + user categories) followed by the taxonomy grouped by top-level group. Used when editing a line
//  item's or a bill's category.
//

import SwiftUI
import SwiftData

struct CategoryPickerSheet: View {
    @Binding var selection: String
    /// Called with the chosen category name (in addition to updating the binding).
    var onPicked: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Category> { $0.isCustom }, sort: \Category.createdAt)
    private var customCategories: [Category]

    @State private var search = ""
    @State private var showCreate = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                if search.isEmpty {
                    yourCategoriesSection
                    ForEach(Categories.groups, id: \.name) { group in
                        gridSection(group.name, names: [group.name] + Categories.children(of: group.name).map(\.name))
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
        }
    }

    private var filteredNames: [String] {
        let all = Categories.predefined.map(\.name) + customCategories.map(\.name)
        return all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var yourCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Your Categories")
            LazyVGrid(columns: columns, spacing: 10) {
                Button { showCreate = true } label: { newTile }.buttonStyle(.plain)
                ForEach(customCategories, id: \.name) { cat in
                    tile(cat.name, color: Color(argb: cat.colorArgb), emoji: cat.icon)
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
                    tile(name, color: Color(argb: Categories.color(for: name)), emoji: Categories.emoji(for: name))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 12)
    }

    private func tile(_ name: String, color: Color, emoji: String) -> some View {
        Button {
            selection = name
            onPicked?(name)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color)
                    .frame(width: 44, height: 44)
                    .overlay(Text(emoji).font(.system(size: 22)))
                Text(name).font(.caption).fontWeight(.medium).foregroundStyle(Palette.label)
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
