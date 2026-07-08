//
//  CategoryMemorySheet.swift
//  Budgetty
//
//  Shown after the user re-categorizes an item: offer to remember the change (name → category) so
//  it auto-applies to past & future items with the same name (persisted as a `CategoryRule`).
//

import SwiftUI

enum MemoryScope { case itemOnly, all }

struct CategoryMemorySheet: View {
    let itemName: String
    let oldCategory: String
    let newCategory: String
    var onApply: (MemoryScope) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scope: MemoryScope = .itemOnly

    var body: some View {
        VStack(spacing: 0) {
            changeVisual
            VStack(spacing: 5) {
                Text("Remember this change?").font(.title3).fontWeight(.bold)
                Text("Apply to other “\(itemName)” items?")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.top, 8).padding(.bottom, 16)

            VStack(spacing: 0) {
                option("This item only", "Just this one on the current receipt", .itemOnly)
                Divider().padding(.leading, 16)
                option("All “\(itemName)”", "Applies to all past & future matches", .all)
            }
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            Button {
                onApply(scope); dismiss()
            } label: {
                Text("Apply").font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Palette.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.horizontal, 20).padding(.top, 16)

            Button("Cancel") { dismiss() }
                .foregroundStyle(Palette.tint).padding(.vertical, 14)
        }
        .padding(.top, 12).padding(.bottom, 8)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
    }

    private var changeVisual: some View {
        HStack(spacing: 16) {
            miniTile(oldCategory)
            VStack(spacing: 4) {
                Image(systemName: "arrow.right").foregroundStyle(Palette.tint)
                Text(itemName).font(.caption2).foregroundStyle(Palette.tertiaryLabel).lineLimit(1)
            }
            miniTile(newCategory)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func miniTile(_ category: String) -> some View {
        VStack(spacing: 4) {
            CategoryTile(category: category, size: 44)
            Text(category).font(.caption2).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func option(_ title: String, _ subtitle: String, _ value: MemoryScope) -> some View {
        Button {
            scope = value
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(Palette.label)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                Image(systemName: isSelected(value) ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isSelected(value) ? Palette.tint : Palette.tertiaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func isSelected(_ v: MemoryScope) -> Bool {
        switch (scope, v) {
        case (.itemOnly, .itemOnly), (.all, .all): true
        default: false
        }
    }
}
