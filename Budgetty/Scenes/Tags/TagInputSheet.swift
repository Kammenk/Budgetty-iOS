//
//  TagInputSheet.swift
//  Budgetty
//
//  The tag picker sheet from mockup 2b: the selected tags as filled capsules, a search-style input,
//  autocomplete from the existing catalog (substring matches first, then a looser "similar" fallback),
//  a "Create '#…'" row when the typed tag is new, and a Recent row. Normalisation is live and matches
//  `Tag.normalize` (lowercase, spaces → hyphens), so what the user sees is exactly what gets stored.
//
//  It mutates a `[String]` binding of normalized names; the review surface persists them to the catalog
//  on save (`TagOps.setTags`), so a tag typed here isn't created in the catalog until the receipt saves.
//

import SwiftUI
import SwiftData

struct TagInputSheet: View {
    @Binding var tags: [String]
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tag.name) private var allTags: [Tag]
    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private struct CatalogTag { let name: String; let count: Int; let lastUse: Date? }

    private var catalog: [CatalogTag] {
        allTags.map { CatalogTag(name: $0.name, count: $0.items.count,
                                 lastUse: $0.items.map(\.createdAt).max()) }
    }
    private var qn: String { Tag.normalize(query) }
    private var exact: Bool { catalog.contains { $0.name == qn } }

    /// (matches, whether they came from the looser "similar" fallback) — drives the section header.
    private var suggestions: (rows: [CatalogTag], similar: Bool) {
        let available = catalog.filter { !tags.contains($0.name) }
        guard !qn.isEmpty else { return ([], false) }
        let sub = available.filter { $0.name.contains(qn) }.sorted { $0.count > $1.count }
        if !sub.isEmpty { return (Array(sub.prefix(4)), false) }
        guard qn.count >= 3 else { return ([], false) }
        let prefix = String(qn.prefix(3))
        let near = available.filter { !$0.name.contains(qn) && $0.name.hasPrefix(prefix) }
            .sorted { $0.count > $1.count }
        return (Array(near.prefix(4)), true)
    }
    private var canCreate: Bool { !qn.isEmpty && !exact && !tags.contains(qn) }
    private var recent: [String] {
        catalog.filter { !tags.contains($0.name) && $0.lastUse != nil }
            .sorted { ($0.lastUse ?? .distantPast) > ($1.lastUse ?? .distantPast) }
            .prefix(6).map(\.name)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !tags.isEmpty { selectedChips }
                    inputField
                    suggestionsCard
                    if !recent.isEmpty { recentSection }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Tags").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onAppear { fieldFocused = true }
    }

    private var selectedChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button { remove(tag) } label: {
                    HStack(spacing: 5) {
                        Text("#\(tag)").font(.system(size: 15))
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.leading, 12).padding(.trailing, 10).frame(height: 32)
                    .background(Palette.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var inputField: some View {
        HStack(spacing: 6) {
            Text(verbatim: "#").font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.tint)
            TextField("Add a tag", text: $query)
                .font(.system(size: 17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit { if canCreate { add(qn) } }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var suggestionsCard: some View {
        let result = suggestions
        if !result.rows.isEmpty || canCreate {
            VStack(alignment: .leading, spacing: 8) {
                if !result.rows.isEmpty {
                    Text(result.similar ? "SIMILAR" : "EXISTING TAGS")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                        .padding(.leading, 4)
                }
                VStack(spacing: 0) {
                    ForEach(Array(result.rows.enumerated()), id: \.element.name) { idx, s in
                        Button { add(s.name) } label: {
                            HStack {
                                Text("#\(s.name)").font(.system(size: 17)).foregroundStyle(Palette.label)
                                Spacer()
                                Text(useCount(s.count)).font(.system(size: 15)).foregroundStyle(Palette.secondaryLabel)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < result.rows.count - 1 || canCreate { Divider().padding(.leading, 16) }
                    }
                    if canCreate {
                        Button { add(qn) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill").font(.system(size: 19)).foregroundStyle(Palette.tint)
                                Text("Create “#\(qn)”").font(.system(size: 17)).foregroundStyle(Palette.tint)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .contentCard(cornerRadius: 14)
                Text("Lowercase, spaces become hyphens.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.leading, 4)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT").font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                .padding(.leading, 4)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(recent, id: \.self) { tag in
                    Button { add(tag) } label: { TagPill(tag: tag, size: 15) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func useCount(_ n: Int) -> String {
        "\(n) " + (n == 1 ? String(localized: "use") : String(localized: "uses"))
    }

    private func add(_ name: String) {
        let key = Tag.normalize(name)
        query = ""
        guard !key.isEmpty, !tags.contains(key) else { return }
        tags.append(key)
    }

    private func remove(_ name: String) { tags.removeAll { $0 == name } }
}
