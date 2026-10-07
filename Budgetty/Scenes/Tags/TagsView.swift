//
//  TagsView.swift
//  Budgetty
//
//  Account → Tags (mockup 2g/2h): every tag with its transaction count and per-row Rename / Merge /
//  Delete. Rename and Merge are one repository operation — renaming into a name that already exists
//  merges — so both route through `TagOps.renameOrMerge`. Deleting a tag never deletes transactions.
//  Android parity: `TagsViewModel` + `TagsScreen`.
//

import SwiftUI
import SwiftData

struct TagsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]

    @State private var renameTarget: Tag?
    @State private var renameText = ""
    @State private var mergeTarget: Tag?
    @State private var deleteTarget: Tag?

    /// Most-used first, then A–Z — matching Android's `tagCounts` order.
    private var sortedTags: [Tag] {
        tags.sorted { a, b in
            let (ca, cb) = (a.items.count, b.items.count)
            return ca != cb ? ca > cb : a.name < b.name
        }
    }

    var body: some View {
        Group {
            if tags.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(sortedTags) { tag in row(tag) }
                    } footer: {
                        Text("Renaming or merging updates every transaction with that tag. Deleting a tag never deletes transactions.")
                    }
                }
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename tag", isPresented: renamePresented, presenting: renameTarget) { tag in
            TextField("Tag name", text: $renameText)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") { TagOps.renameOrMerge(context, from: tag.name, to: renameText) }
        } message: { _ in
            Text("Lowercase; spaces become hyphens. Using an existing name merges the two.")
        }
        .alert("Delete #\(deleteTarget?.name ?? "")?", isPresented: deletePresented, presenting: deleteTarget) { tag in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { TagOps.delete(context, name: tag.name) }
        } message: { _ in
            Text("This removes the tag everywhere. Your transactions are kept.")
        }
        .sheet(item: $mergeTarget) { tag in
            TagMergeSheet(source: tag.name,
                          options: sortedTags.map(\.name).filter { $0 != tag.name }) { into in
                TagOps.renameOrMerge(context, from: tag.name, to: into)
            }
        }
    }

    private func row(_ tag: Tag) -> some View {
        HStack {
            TagPill(tag: tag.name, size: 15, prominent: true)
            Spacer()
            Text("\(tag.items.count)").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Explicit red: the app's global accent tint otherwise overrides the destructive role's
            // default colour, so pin it to match the mockup's red Delete action.
            Button(role: .destructive) { deleteTarget = tag } label: { Label("Delete", systemImage: "trash") }
                .tint(Palette.bad)
            Button { mergeTarget = tag } label: { Label("Merge", systemImage: "arrow.triangle.merge") }
                .tint(Palette.tint)
            Button { renameTarget = tag; renameText = tag.name } label: { Label("Rename", systemImage: "pencil") }
                .tint(.gray)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tag").font(.system(size: 34)).foregroundStyle(Palette.tertiaryLabel)
            Text("No tags yet").font(.headline).foregroundStyle(Palette.label)
            Text("Add tags to a transaction while reviewing it — handy for things like #work or #reimbursable.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center).padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground)
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
}

/// Merge picker (mockup 2h's precursor): pick which existing tag to fold this one into; the actual
/// merge collapses the two and names the count in a toast-free, immediate action.
private struct TagMergeSheet: View {
    let source: String
    let options: [String]
    let onMerge: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if options.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.merge").font(.system(size: 30))
                            .foregroundStyle(Palette.tertiaryLabel)
                        Text("There are no other tags to merge into yet.")
                            .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                            .multilineTextAlignment(.center).padding(.horizontal, 36)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.groupedBackground)
                } else {
                    List {
                        Section {
                            ForEach(options, id: \.self) { into in
                                Button { onMerge(into); dismiss() } label: {
                                    HStack {
                                        TagPill(tag: into, size: 15, prominent: true)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(Palette.tertiaryLabel)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Merge #\(source) into")
                        } footer: {
                            Text("Every transaction tagged #\(source) takes the tag you pick instead, and #\(source) is removed.")
                        }
                    }
                }
            }
            .navigationTitle("Merge tag").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
