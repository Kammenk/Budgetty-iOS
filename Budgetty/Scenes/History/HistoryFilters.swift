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
    var id: String { rawValue }
    var short: String {
        switch self {
        case .newest, .oldest: "Date"
        case .priceHigh, .priceLow: "Price"
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
    private func rangeCard(_ title: String, value: Binding<Double>,
                           clamp: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.footnote).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text(Decimal(value.wrappedValue).formatMoney())
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
                                Text(g.name).foregroundStyle(Palette.label)
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
