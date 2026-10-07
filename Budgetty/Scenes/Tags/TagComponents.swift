//
//  TagComponents.swift
//  Budgetty
//
//  Shared tag chrome from the `iOS Tags.dc.html` mockup. The signature rule: categories are filled
//  emoji badges, tags are OUTLINED "#capsules" — the two systems must never blur together. A tag has
//  no colour of its own (only the "#" takes the accent tint), which is also why the Insights by-tag
//  bars use the shared accent rather than a per-tag hue.
//

import SwiftUI

/// An outlined "#tag" capsule. Row style by default (small, muted name); `prominent` gives the larger,
/// label-weighted variant used on the review surface and the Insights by-tag rows.
struct TagPill: View {
    let tag: String
    var size: CGFloat = 12
    var prominent = false

    var body: some View {
        HStack(spacing: 1) {
            Text(verbatim: "#").foregroundStyle(Palette.tint)
            Text(tag).foregroundStyle(prominent ? Palette.label : Palette.secondaryLabel)
                .fontWeight(prominent ? .semibold : .regular)
        }
        .font(.system(size: size))
        .lineLimit(1)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Palette.separatorStrong, lineWidth: 1))
    }
}

/// A removable "#tag ⓧ" capsule for the review surface's Tags section (mockup 2a). When `isTrip` it
/// renders as the active-trip tag does everywhere it's prominent: a filled tint capsule with ✈️
/// (mockup 3e) — still removable, so the user can leave a single expense out of the trip.
struct RemovableTagChip: View {
    let tag: String
    var isTrip = false
    let onRemove: () -> Void

    var body: some View {
        if isTrip { tripChip } else { plainChip }
    }

    private var plainChip: some View {
        HStack(spacing: 5) {
            HStack(spacing: 1) {
                Text(verbatim: "#").foregroundStyle(Palette.tint)
                Text(tag).foregroundStyle(Palette.label)
            }
            .font(.system(size: 15))
            removeButton(color: Palette.tertiaryLabel)
        }
        .padding(.leading, 12).padding(.trailing, 7).frame(height: 32)
        .overlay(Capsule().strokeBorder(Palette.separatorStrong, lineWidth: 1))
    }

    private var tripChip: some View {
        HStack(spacing: 5) {
            Text("✈️ #\(tag)").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            removeButton(color: .white.opacity(0.85))
        }
        .padding(.leading, 12).padding(.trailing, 7).frame(height: 32)
        .background(Palette.tint, in: Capsule())
    }

    private func removeButton(color: Color) -> some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove #\(tag)")
    }
}

/// The tinted "＋ Tag" affordance that opens the tag input sheet (mockup 2a).
struct AddTagButton: View {
    var label: LocalizedStringKey = "Tag"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                Text(label).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Palette.tint)
            .padding(.horizontal, 14).frame(height: 32)
            .background(Palette.tintSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A wrapping strip of small outlined tag pills for a History row (mockup 2c). Renders nothing when
/// the item carries no tags.
struct TagRowStrip: View {
    let tags: [String]

    var body: some View {
        if !tags.isEmpty {
            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(tags, id: \.self) { TagPill(tag: $0) }
            }
        }
    }
}
