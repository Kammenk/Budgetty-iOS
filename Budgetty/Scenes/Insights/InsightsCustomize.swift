//
//  InsightsCustomize.swift
//  Budgetty
//
//  Show/hide + reorder for the Insights cards (iPhone only, matching the Android "Customize
//  sections" sheet). Order + hidden set persist as CSV in UserDefaults; the iPad multi-column
//  layouts keep their fixed arrangement.
//

import SwiftUI

enum InsightSection: String, CaseIterable, Identifiable {
    case trend, breakdown, stats, highlights, comparison, budget, topCategories, topStores,
         biggestPurchases, income
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .trend: "Trend"
        case .breakdown: "Breakdown"
        case .stats: "Stats"
        case .highlights: "Highlights"
        case .comparison: "Period comparison"
        case .budget: "Budget"
        case .topCategories: "Top categories"
        case .topStores: "Top stores"
        case .biggestPurchases: "Biggest purchases"
        case .income: "Income & bills"
        }
    }

    var icon: String {
        switch self {
        case .trend: "chart.bar.fill"
        case .breakdown: "chart.pie.fill"
        case .stats: "square.grid.2x2.fill"
        case .highlights: "sparkles"
        case .comparison: "arrow.left.arrow.right"
        case .budget: "target"
        case .topCategories: "list.number"
        case .topStores: "storefront.fill"
        case .biggestPurchases: "crown.fill"
        case .income: "creditcard.fill"
        }
    }
}

/// CSV <-> [InsightSection] helpers so the order/hidden state can live in @AppStorage strings.
enum InsightsLayoutStore {
    static let orderKey = "insights.order"
    static let hiddenKey = "insights.hidden"

    /// Saved order, with any newly-added sections appended so the list stays complete.
    static func order(_ raw: String) -> [InsightSection] {
        let saved = raw.split(separator: ",").compactMap { InsightSection(rawValue: String($0)) }
        return saved + InsightSection.allCases.filter { !saved.contains($0) }
    }
    static func hidden(_ raw: String) -> Set<InsightSection> {
        Set(raw.split(separator: ",").compactMap { InsightSection(rawValue: String($0)) })
    }
    static func csv(_ sections: [InsightSection]) -> String { sections.map(\.rawValue).joined(separator: ",") }
    static func csv(_ sections: Set<InsightSection>) -> String { sections.map(\.rawValue).joined(separator: ",") }
}

struct InsightsCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String

    @State private var order: [InsightSection] = []
    @State private var hidden: Set<InsightSection> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { section in
                        HStack(spacing: 12) {
                            Button {
                                if hidden.contains(section) { hidden.remove(section) }
                                else { hidden.insert(section) }
                            } label: {
                                Image(systemName: hidden.contains(section) ? "eye.slash.circle.fill" : "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(hidden.contains(section) ? Palette.tertiaryLabel : Palette.good)
                            }
                            .buttonStyle(.borderless)
                            Image(systemName: section.icon).foregroundStyle(Palette.tint).frame(width: 24)
                            Text(section.title).foregroundStyle(Palette.label)
                            Spacer()
                        }
                    }
                    .onMove { order.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Tap to show or hide a section. Use Edit to drag and reorder. Applies on iPhone.")
                }
            }
            .navigationTitle("Customize Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
        .onAppear {
            order = InsightsLayoutStore.order(orderRaw)
            hidden = InsightsLayoutStore.hidden(hiddenRaw)
        }
    }

    private func save() {
        orderRaw = InsightsLayoutStore.csv(order)
        hiddenRaw = InsightsLayoutStore.csv(hidden)
    }
}
