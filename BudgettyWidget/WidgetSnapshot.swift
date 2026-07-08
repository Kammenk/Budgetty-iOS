//
//  WidgetSnapshot.swift
//  BudgettyWidget
//
//  The snapshot the app writes into the shared App Group container. Mirrors the app-side struct in
//  Budgetty/Widget/WidgetSharing.swift — keep the two in sync.
//

import Foundation

struct WidgetSnapshot: Codable {
    var monthLabel: String
    var monthSpent: Double
    var monthlyBudget: Double
    var currencyCode: String
    var rows: [Row]

    struct Row: Codable { var store: String; var amount: Double; var date: String }

    static let suite = "group.com.budgetty.Budgetty"
    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: suite),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(monthLabel: "This month", monthSpent: 0, monthlyBudget: 0,
                                  currencyCode: "EUR", rows: [])
        }
        return snapshot
    }

    var budgetFraction: Double { monthlyBudget > 0 ? min(monthSpent / monthlyBudget, 1) : 0 }

    func money(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
