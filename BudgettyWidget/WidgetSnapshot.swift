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
    var monthReceiptCount: Int
    var rows: [Row]
    var topCategories: [TopCat]
    // Optional so a snapshot written by a pre-week-widget build still decodes (→ nil → 0) rather than
    // failing the whole decode and blanking every widget until the app rewrites it.
    var thisWeekSpent: Double?
    var lastWeekSpent: Double?

    struct Row: Codable { var store: String; var amount: Double; var date: String }
    struct TopCat: Codable { var emoji: String; var amount: Double; var colorArgb: Int }

    static let suite = "group.com.budgetty.Budgetty"
    static let key = "widget.snapshot"

    static func load() -> WidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: suite),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return WidgetSnapshot(monthLabel: "This month", monthSpent: 0, monthlyBudget: 0,
                                  currencyCode: "EUR", monthReceiptCount: 0, rows: [], topCategories: [],
                                  thisWeekSpent: 0, lastWeekSpent: 0)
        }
        return snapshot
    }

    var budgetLeft: Double { max(0, monthlyBudget - monthSpent) }

    var budgetFraction: Double { monthlyBudget > 0 ? min(monthSpent / monthlyBudget, 1) : 0 }

    var weekThis: Double { thisWeekSpent ?? 0 }
    var weekLast: Double { lastWeekSpent ?? 0 }
    /// Signed change this week vs last (nil when there's no prior week to compare).
    var weekDeltaFraction: Double? {
        guard weekLast > 0 else { return nil }
        return (weekThis - weekLast) / weekLast
    }

    func money(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currencyCode
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

import SwiftUI

extension Color {
    /// Unpack a 0xAARRGGBB Int (matches the app's category colors).
    init(argb: Int) {
        self.init(.sRGB,
                  red: Double((argb >> 16) & 0xFF) / 255,
                  green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255,
                  opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}
