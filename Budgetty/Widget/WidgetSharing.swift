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
    var thisWeekSpent: Double?
    var lastWeekSpent: Double?

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
        // Honor the user's pay-cycle "Month starts on" setting so the widgets agree with the app.
        let startDay = PayCycle.startDay
        let monthWindow = PayCycle.monthInterval(startDay: startDay, calendar: cal)
        let month = receipts.filter { monthWindow.contains($0.createdAt) }
        let spent = month.reduce(Decimal.zero) { $0 + $1.paidTotal }

        // This week vs last (Mon–Sun, matching Android) for the This Week widget face.
        var weekCal = cal
        weekCal.firstWeekday = 2 // Monday
        let thisWeekStart = weekCal.dateInterval(of: .weekOfYear, for: .now)?.start ?? cal.startOfDay(for: .now)
        let nextWeekStart = weekCal.date(byAdding: .day, value: 7, to: thisWeekStart) ?? .now
        let lastWeekStart = weekCal.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        let weekThis = receipts.filter { $0.createdAt >= thisWeekStart && $0.createdAt < nextWeekStart }
            .reduce(Decimal.zero) { $0 + $1.paidTotal }
        let weekLast = receipts.filter { $0.createdAt >= lastWeekStart && $0.createdAt < thisWeekStart }
            .reduce(Decimal.zero) { $0 + $1.paidTotal }

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
            monthLabel: mf.string(from: PayCycle.month(startDay: startDay, calendar: cal).start),
            monthSpent: (spent as NSDecimalNumber).doubleValue,
            monthlyBudget: (monthlyBudget as NSDecimalNumber).doubleValue,
            currencyCode: UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR",
            monthReceiptCount: month.count,
            rows: Array(rows),
            topCategories: Array(topCats),
            thisWeekSpent: (weekThis as NSDecimalNumber).doubleValue,
            lastWeekSpent: (weekLast as NSDecimalNumber).doubleValue)

        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: suite) else { return }
        defaults.set(data, forKey: key)
        publishPremium()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Mirror the Premium flag into the App Group so the extension can enforce `WidgetQuota` on its
    /// own — widgets render when the app isn't running, and the standard-suite `pref.premium` the
    /// rest of the app reads isn't visible from another process.
    ///
    /// Its own key rather than a snapshot field, so entitlement changes can publish without a
    /// ModelContext (see `StoreManager`) and so a snapshot written by a pre-cap build can't decode
    /// into "not premium" and lock someone's widgets.
    static func publishPremium() {
        UserDefaults(suiteName: suite)?
            .set(UserDefaults.standard.bool(forKey: SettingsKey.premium), forKey: WidgetQuota.premiumKey)
    }

    /// Entitlement changed: republish and re-render. Without this a purchase wouldn't unlock a
    /// locked widget until its next scheduled refresh, hours later.
    static func premiumDidChange() {
        publishPremium()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
