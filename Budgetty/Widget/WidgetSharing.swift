//
//  WidgetSharing.swift
//  Budgetty
//
//  Writes a small spending snapshot into the shared App Group container so the WidgetKit extension
//  (a separate process) can render without touching SwiftData directly. Called when the app becomes
//  active and after receipts change; reloads widget timelines.
//

import Foundation
import SwiftData
import WidgetKit

/// Mirror of the struct the widget decodes (keep the two in sync).
struct WidgetSnapshot: Codable {
    var monthLabel: String
    var monthSpent: Double
    var monthlyBudget: Double
    var currencyCode: String
    var monthReceiptCount: Int
    var rows: [Row]
    var topCategories: [TopCat]

    struct Row: Codable { var store: String; var amount: Double; var date: String }
    struct TopCat: Codable { var emoji: String; var amount: Double; var colorArgb: Int }
}

enum WidgetSharing {
    static let suite = "group.com.budgetty.Budgetty"
    static let key = "widget.snapshot"

    @MainActor
    static func update(from context: ModelContext) {
        let cal = Calendar.current
        let receipts = (try? context.fetch(
            FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        let month = receipts.filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
        let spent = month.reduce(Decimal.zero) { $0 + $1.paidTotal }

        let budgets = (try? context.fetch(FetchDescriptor<Budget>())) ?? []
        let monthlyBudget = budgets.first { $0.key == Budget.monthlyKey }?.amount ?? 0

        let df = DateFormatter(); df.dateFormat = "d MMM"
        let rows = receipts.prefix(4).map {
            WidgetSnapshot.Row(store: $0.store,
                               amount: ($0.paidTotal as NSDecimalNumber).doubleValue,
                               date: df.string(from: $0.date))
        }
        let mf = DateFormatter(); mf.dateFormat = "MMMM yyyy"

        // Top spend categories this month (rolled up to groups, like the Insights breakdown).
        var catSums: [String: Decimal] = [:]
        for item in month.flatMap(\.items) {
            catSums[Categories.groupOf(item.category), default: .zero] += item.lineTotal
        }
        let topCats = catSums.sorted { $0.value > $1.value }.prefix(3).map { (name, value) in
            WidgetSnapshot.TopCat(emoji: Categories.emoji(for: name),
                                  amount: (value as NSDecimalNumber).doubleValue,
                                  colorArgb: Categories.color(for: name))
        }

        let snapshot = WidgetSnapshot(
            monthLabel: mf.string(from: .now),
            monthSpent: (spent as NSDecimalNumber).doubleValue,
            monthlyBudget: (monthlyBudget as NSDecimalNumber).doubleValue,
            currencyCode: UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR",
            monthReceiptCount: month.count,
            rows: Array(rows),
            topCategories: Array(topCats))

        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
