//
//  HistoryFilters.swift
//  Budgetty
//
//  Sort order + the price and category filter sheets used by the History header chips.
//

import SwiftUI

enum HistorySort: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    case priceHigh = "Price: high to low"
    case priceLow = "Price: low to high"
    case tagAZ = "Tag A–Z"
    var id: String { rawValue }
    var short: String {
        switch self {
        case .newest, .oldest: "Date"
        case .priceHigh, .priceLow: "Price"
        case .tagAZ: "Tag"
        }
    }
}

/// Min/max price filter with two sliders.
struct PriceRangeSheet: View {
    @Binding var lower: Double?
    @Binding var upper: Double?
    let bound: Double
    @Environment(\.dismiss) private var dismiss

    @State private var lo: Double = 0
    @State private var hi: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    rangeCard("Minimum", value: $lo) { v in if v > hi { hi = v } }
                    rangeCard("Maximum", value: $hi) { v in if v < lo { lo = v } }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Price range").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { lower = nil; upper = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { lower = lo; upper = hi; dismiss() }
                }
            }
            .onAppear { lo = lower ?? 0; hi = upper ?? bound }
        }
    }

    /// One glass card per bound (mockup: label + amount + slider on a glass row).
    private func rangeCard(_ title: LocalizedStringKey, value: Binding<Double>,
                           clamp: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.footnote).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text(Decimal(value.wrappedValue).formatMoneyRaw())
                    .font(.headline).foregroundStyle(Palette.label)
            }
            Slider(value: value, in: 0...bound, step: 1)
                .tint(Palette.tint)
                .onChange(of: value.wrappedValue) { _, v in clamp(v) }
        }
        .padding(16)
        .contentCard(cornerRadius: 14)
    }
}

/// Multi-select tag filter with an Any / All match control (mockup 2e). Binds live, so the list
/// behind it narrows as chips toggle; the CTA just names the live result count and dismisses.
struct TagFilterSheet: View {
    @Binding var selected: Set<String>
    @Binding var matchAll: Bool
    let options: [String]
    /// Live count of results under the current selection (recomputed by the owner on each change).
    let resultCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if options.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tag").font(.system(size: 32)).foregroundStyle(Palette.tertiaryLabel)
                        Text("No tags yet. Add tags to your receipt items and they'll show up here to filter by.")
                            .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                            .multilineTextAlignment(.center).padding(.horizontal, 36)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("TAG").font(.caption2).fontWeight(.semibold)
                                .foregroundStyle(Palette.secondaryLabel)
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(options, id: \.self) { tag in
                                    chip(tag)
                                }
                            }
                            if selected.count > 1 { matchControl }
                            Button { dismiss() } label: {
                                Text("Show \(resultCount) result\(resultCount == 1 ? "" : "s")")
                                    .font(.headline).ctaPill()
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(20)
                    }
                }
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Filter by tag").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selected = []; matchAll = false; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func chip(_ tag: String) -> some View {
        let on = selected.contains(tag)
        return Button {
            if on { selected.remove(tag) } else { selected.insert(tag) }
        } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                Text("#\(tag)").font(.system(size: 15))
            }
            .foregroundStyle(on ? .white : Palette.label)
            .padding(.horizontal, 12).frame(height: 32)
            .background {
                if on { Capsule().fill(Palette.tint) }
                else { Capsule().strokeBorder(Palette.separatorStrong, lineWidth: 1) }
            }
        }
        .buttonStyle(.plain)
    }

    private var matchControl: some View {
        HStack {
            Text("Match").font(.subheadline).foregroundStyle(Palette.label)
            Spacer()
            Picker("", selection: $matchAll) {
                Text("Any").tag(false)
                Text("All").tag(true)
            }
            .pickerStyle(.segmented).fixedSize()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentCard(cornerRadius: 14)
        .overlay(alignment: .bottomLeading) {
            Text("Applies when several tags are picked.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
                .padding(.leading, 4).offset(y: 22)
        }
        .padding(.bottom, 20)
    }
}

/// Multi-select category (group) filter.
struct CategoryFilterSheet: View {
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(Categories.groups.enumerated()), id: \.element.name) { idx, g in
                        Button {
                            if selected.contains(g.name) { selected.remove(g.name) } else { selected.insert(g.name) }
                        } label: {
                            HStack(spacing: 12) {
                                CategoryTile(category: g.name, size: 28)
                                Text(Categories.displayName(g.name)).foregroundStyle(Palette.label)
                                Spacer()
                                if selected.contains(g.name) {
                                    Image(systemName: "checkmark").foregroundStyle(Palette.tint).fontWeight(.semibold)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < Categories.groups.count - 1 {
                            Rectangle().fill(Palette.separator).frame(height: 0.5).padding(.leading, 16)
                        }
                    }
                }
                .contentCard(cornerRadius: 14)
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { selected = []; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
