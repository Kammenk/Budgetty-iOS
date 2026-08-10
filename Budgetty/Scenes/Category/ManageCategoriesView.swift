//
//  ManageCategoriesView.swift
//  Budgetty
//
//  Account → Manage categories: a permanent home for category CRUD, mirroring Android's
//  ManageCategoriesScreen. The user's custom categories (tap to edit) with an "In {group}" sub-line,
//  a Create row that turns into a Premium prompt at the free cap, and collapsible built-in groups
//  whose sub-rows can be re-homed via a "Move to group" dialog. Create/edit reuse `CustomCategorySheet`;
//  moves go through `CategoryOps.setParent`. Rendered as a native grouped List (the platform-native
//  form of the same rows-not-tiles design).
//

import SwiftUI
import SwiftData

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.premium) private var premium = false
    @Query(sort: \Category.createdAt) private var categories: [Category]

    @State private var creating = false
    @State private var editing: Category?
    @State private var moving: Category?
    @State private var showPaywall = false
    @State private var expanded: Set<String> = []

    // MARK: - Derived model

    private var customs: [Category] {
        categories.filter(\.isCustom).sorted { $0.createdAt < $1.createdAt }
    }
    private var cap: Int { Categories.freeCustomLimit }
    private var atCap: Bool { !premium && customs.count >= cap }
    private var realGroupCount: Int { Categories.groups.filter { $0.name != Categories.other }.count }
    private var builtInSubCount: Int { groupRows.reduce(0) { $0 + $1.subs.count } }

    /// A category's effective parent — its stored override, else its code-defined group, else nil.
    private func effectiveParent(_ c: Category) -> String? {
        if let p = c.parent, !p.isEmpty { return p }
        return Categories.defaultParentOf(c.name)
    }

    private struct GroupRow: Identifiable {
        let name: String
        let subs: [Category]
        let customCount: Int
        var id: String { name }
    }

    private var groupRows: [GroupRow] {
        let order = Dictionary(
            uniqueKeysWithValues: Categories.predefined.enumerated().map { ($1.name, $0) }
        )
        return Categories.groups.map { g in
            let subs = categories
                .filter { !$0.isCustom && $0.name != g.name && effectiveParent($0) == g.name }
                .sorted { (order[$0.name] ?? .max) < (order[$1.name] ?? .max) }
            let count = customs.filter { effectiveParent($0) == g.name }.count
            return GroupRow(name: g.name, subs: subs, customCount: count)
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            yourCategoriesSection
            builtInSection
        }
        .navigationTitle("Manage categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { CustomCategorySheet(editing: nil) }
        .sheet(item: $editing) { CustomCategorySheet(editing: $0) }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .confirmationDialog(
            "Move to group",
            isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
            titleVisibility: .visible
        ) {
            if let cat = moving {
                ForEach(Categories.groups.filter { $0.name != Categories.other }, id: \.name) { g in
                    Button(Categories.displayName(g.name)) {
                        CategoryOps.setParent(context, name: cat.name, to: g.name)
                        CategoryOps.refreshTaxonomy(context)
                        moving = nil
                    }
                }
            }
        }
    }

    // MARK: - Your categories

    @ViewBuilder private var yourCategoriesSection: some View {
        Section {
            if customs.isEmpty {
                Text("No custom categories yet — create one to tag spending your own way.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(customs) { c in
                    Button { editing = c } label: { customRow(c) }.buttonStyle(.plain)
                }
            }
            Button {
                if atCap { showPaywall = true } else { creating = true }
            } label: {
                createRow
            }.buttonStyle(.plain)
        } header: {
            HStack {
                Text("Your categories")
                Spacer()
                if !premium { Text("\(customs.count) / \(cap)").foregroundStyle(.secondary) }
            }
        } footer: {
            if !premium {
                Text("Free includes \(cap) custom categories · Unlimited with Premium")
            }
        }
    }

    private func customRow(_ c: Category) -> some View {
        HStack(spacing: 12) {
            tile(c.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Categories.displayName(c.name)).font(.body.weight(.semibold))
                    .foregroundStyle(Palette.label)
                Text(effectiveParent(c).map { String(localized: "In \(Categories.displayName($0))") }
                     ?? String(localized: "Top level"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "pencil").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var createRow: some View {
        HStack(spacing: 12) {
            Image(systemName: atCap ? "lock.fill" : "plus.circle.fill")
                .font(.title3).foregroundStyle(Palette.tint)
            Text("Create category").font(.body.weight(.semibold)).foregroundStyle(Palette.tint)
            Spacer()
            if atCap {
                Text("Premium").font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Palette.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(Palette.tint)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Built-in

    @ViewBuilder private var builtInSection: some View {
        Section {
            ForEach(groupRows) { g in
                DisclosureGroup(isExpanded: expandedBinding(g.name)) {
                    if g.subs.isEmpty {
                        Text("No sub-categories").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(g.subs) { sub in
                        subRow(sub, movable: g.name != Categories.other)
                    }
                } label: {
                    groupLabel(g)
                }
            }
        } header: {
            HStack {
                Text("Built-in")
                Spacer()
                Text("\(realGroupCount) groups · \(builtInSubCount) categories").foregroundStyle(.secondary)
            }
        }
    }

    private func groupLabel(_ g: GroupRow) -> some View {
        HStack(spacing: 12) {
            tile(g.name, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(Categories.displayName(g.name)).font(.body.weight(.semibold))
                    .foregroundStyle(Palette.label)
                Text(subLine(g)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func subLine(_ g: GroupRow) -> String {
        let base = g.subs.count == 1
            ? String(localized: "1 sub-category")
            : String(localized: "\(g.subs.count) sub-categories")
        return g.customCount > 0 ? base + String(localized: " · \(g.customCount) yours") : base
    }

    private func subRow(_ sub: Category, movable: Bool) -> some View {
        HStack(spacing: 12) {
            tile(sub.name, size: 26)
            Text(Categories.displayName(sub.name)).font(.subheadline).foregroundStyle(Palette.label)
            Spacer()
            if movable {
                Button { moving = sub } label: {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private func tile(_ name: String, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(argb: Categories.color(for: name)))
            .frame(width: size, height: size)
            .overlay(Text(Categories.emoji(for: name)).font(.system(size: size * 0.5)))
    }

    private func expandedBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(name) },
            set: { isOn in if isOn { expanded.insert(name) } else { expanded.remove(name) } }
        )
    }
}
