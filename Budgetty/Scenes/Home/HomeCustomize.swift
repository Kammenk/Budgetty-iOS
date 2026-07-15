//
//  HomeCustomize.swift
//  Budgetty
//
//  Show/hide + reorder for the Home sections (iPhone only, matching the Android "Customize
//  sections" sheet and the Insights equivalent). Order + hidden set persist as CSV in
//  UserDefaults; the iPad multi-column layouts keep their fixed arrangement.
//

import SwiftUI

enum HomeSection: String, CaseIterable, Identifiable {
    case totalSpent, weekComparison, budgets, receipts
    var id: String { rawValue }

    var title: String {
        switch self {
        case .totalSpent: "Total spent"
        case .weekComparison: "Week comparison"
        case .budgets: "Budgets"
        case .receipts: "Receipts"
        }
    }

    var icon: String {
        switch self {
        case .totalSpent: "creditcard.fill"
        case .weekComparison: "calendar"
        case .budgets: "chart.bar.fill"
        case .receipts: "receipt"
        }
    }
}

/// CSV <-> [HomeSection] helpers so the order/hidden state can live in @AppStorage strings.
enum HomeLayoutStore {
    static let orderKey = "home.order"
    static let hiddenKey = "home.hidden"
    /// Week comparison starts hidden (the mockup's default) — the other sections match the
    /// pre-customization Home.
    static let defaultHidden = HomeSection.weekComparison.rawValue

    /// Saved order, with any newly-added sections appended so the list stays complete.
    static func order(_ raw: String) -> [HomeSection] {
        let saved = raw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) }
        return saved + HomeSection.allCases.filter { !saved.contains($0) }
    }
    static func hidden(_ raw: String) -> Set<HomeSection> {
        Set(raw.split(separator: ",").compactMap { HomeSection(rawValue: String($0)) })
    }
    static func csv(_ sections: [HomeSection]) -> String { sections.map(\.rawValue).joined(separator: ",") }
    static func csv(_ sections: Set<HomeSection>) -> String { sections.map(\.rawValue).joined(separator: ",") }
}

struct HomeCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String

    @State private var order: [HomeSection] = []
    @State private var hidden: Set<HomeSection> = []

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
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save(); dismiss() }
                }
            }
        }
        .onAppear {
            order = HomeLayoutStore.order(orderRaw)
            hidden = HomeLayoutStore.hidden(hiddenRaw)
        }
    }

    private func save() {
        orderRaw = HomeLayoutStore.csv(order)
        hiddenRaw = HomeLayoutStore.csv(hidden)
    }
}
