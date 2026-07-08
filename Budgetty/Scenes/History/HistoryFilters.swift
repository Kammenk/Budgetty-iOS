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
            Form {
                Section("Minimum") {
                    HStack { Text(Decimal(lo).formatMoney()); Spacer() }
                    Slider(value: $lo, in: 0...bound, step: 1)
                        .onChange(of: lo) { _, v in if v > hi { hi = v } }
                }
                Section("Maximum") {
                    HStack { Text(Decimal(hi).formatMoney()); Spacer() }
                    Slider(value: $hi, in: 0...bound, step: 1)
                        .onChange(of: hi) { _, v in if v < lo { lo = v } }
                }
            }
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
}

/// Multi-select category (group) filter.
struct CategoryFilterSheet: View {
    @Binding var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Categories.groups, id: \.name) { g in
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
                    }
                }
            }
            .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear") { selected = []; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
