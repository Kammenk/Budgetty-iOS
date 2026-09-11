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
    case trend, breakdown, stats, needsWantsSavings, highlights, comparison, topCategories, topStores,
         biggestPurchases, income, subscriptions
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .trend: "Trend"
        case .breakdown: "Breakdown"
        case .stats: "Stats"
        case .needsWantsSavings: "Needs · Wants · Savings"
        case .highlights: "Highlights"
        case .comparison: "Period comparison"
        case .topCategories: "Top categories"
        case .topStores: "Top stores"
        case .biggestPurchases: "Biggest purchases"
        case .income: "Income & bills"
        case .subscriptions: "Subscriptions"
        }
    }

    var icon: String {
        switch self {
        case .trend: "chart.bar.fill"
        case .breakdown: "chart.pie.fill"
        case .stats: "square.grid.2x2.fill"
        case .needsWantsSavings: "percent"
        case .highlights: "sparkles"
        case .comparison: "arrow.left.arrow.right"
        case .topCategories: "list.number"
        case .topStores: "storefront.fill"
        case .biggestPurchases: "crown.fill"
        case .income: "creditcard.fill"
        case .subscriptions: "repeat"
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

// The Hybrid redesign retired the whole-screen "Customize sections" sheet (D6): the fixed tabs are
// fixed (D1), the Custom tab (`CustomSectionsSheet`) is the curation surface, and the overlay / savings
// toggles are Overview quick-toggle chips. `InsightSection` + `InsightsLayoutStore` remain — the
// onboarding quiz (`InsightsQuizView.applySetupQuiz`) and backup still read/write the order/hidden keys,
// and the sign-out reset clears them.
