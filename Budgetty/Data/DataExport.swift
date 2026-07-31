//
//  DataExport.swift
//  Budgetty
//
//  CSV + PDF export (Android's ExportBuilder + DataExporter). A human-readable spreadsheet (a row
//  per receipt) and a branded one-page-plus PDF statement (totals, a category summary, and the
//  transaction table), built on device with no libraries — CSV as a string, PDF via
//  UIGraphicsPDFRenderer — then handed to the system share sheet. Distinct from the JSON backup,
//  which is opaque and migration-only.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Models

struct ExportRow {
    let date: Date
    let dateLabel: String
    let store: String
    let category: String
    let colorArgb: Int
    let amount: Decimal
}

struct ExportCategory {
    let name: String
    let emoji: String
    let colorArgb: Int
    let total: Decimal
    let pct: Int
}

struct ExportData {
    let periodLabel: String
    let generatedLabel: String
    let currencySymbol: String
    let rows: [ExportRow]
    let totalSpent: Decimal
    let income: Decimal
    let net: Decimal
    let byCategory: [ExportCategory]
    let totalRowLabel: String
    var isEmpty: Bool { rows.isEmpty }
}

/// The export period options (Android's DateRangeFilter): the 5 standard ranges.
enum ExportPeriod: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3, last6, allTime
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .last3: "Last 3 months"
        case .last6: "Last 6 months"
        case .allTime: "All time"
        }
    }
    /// The date interval for the period, over the given receipts (for all-time's earliest bound).
    func interval(startDay: Int, receipts: [Receipt]) -> DateInterval {
        let cal = Calendar.current
        switch self {
        case .thisMonth: return PayCycle.monthInterval(startDay: startDay)
        case .lastMonth: return PayCycle.monthInterval(startDay: startDay, offset: -1)
        case .last3, .last6:
            let back = (self == .last3 ? 3 : 6) - 1
            let start = PayCycle.month(.now, startDay: startDay, offset: -back).start
            return DateInterval(start: start, end: PayCycle.monthInterval(startDay: startDay).end)
        case .allTime:
            let earliest = receipts.map(\.createdAt).min() ?? PayCycle.monthInterval(startDay: startDay).start
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
            return DateInterval(start: cal.startOfDay(for: earliest), end: end)
        }
    }
}

// MARK: - Aggregation + CSV

enum ExportBuilder {

    /// One row per receipt in the interval, plus totals, income and the category breakdown.
    static func buildData(receipts: [Receipt], income: [Recurring], interval: DateInterval,
                          currencySymbol: String, periodLabel: String, generatedLabel: String,
                          totalRowLabel: String) -> ExportData {
        let df = DateFormatter(); df.setLocalizedDateFormatFromTemplate("dd MMM")
        let rows: [ExportRow] = receipts
            .filter { interval.contains($0.createdAt) }
            .compactMap { r in
                let total = SubscriptionDetector.round2(r.paidTotal)
                guard total > 0 else { return nil }
                let cats = r.items.map(\.category)
                let category = mostCommon(cats) ?? cats.first ?? Categories.defaultName
                let store = StoreNormalizer.normalize(r.store)
                return ExportRow(date: r.createdAt, dateLabel: df.string(from: r.createdAt),
                                 store: store.isEmpty ? "—" : store, category: category,
                                 colorArgb: Categories.color(for: category), amount: total)
            }
            .sorted { $0.date < $1.date }

        let totalSpent = rows.reduce(Decimal.zero) { $0 + $1.amount }
        let inc = SubscriptionDetector.round2(income.reduce(Decimal.zero) { $0 + $1.windowAmount(interval) })
        let byCategory = Dictionary(grouping: rows, by: \.category)
            .map { name, catRows -> ExportCategory in
                let sum = catRows.reduce(Decimal.zero) { $0 + $1.amount }
                let pct = totalSpent > 0
                    ? Int(((sum as NSDecimalNumber).doubleValue / (totalSpent as NSDecimalNumber).doubleValue * 100).rounded())
                    : 0
                return ExportCategory(name: name, emoji: Categories.emoji(for: name),
                                      colorArgb: Categories.color(for: name), total: sum, pct: pct)
            }
            .sorted { $0.total > $1.total }

        return ExportData(periodLabel: periodLabel, generatedLabel: generatedLabel,
                          currencySymbol: currencySymbol, rows: rows, totalSpent: totalSpent,
                          income: inc, net: inc - totalSpent, byCategory: byCategory,
                          totalRowLabel: totalRowLabel)
    }

    static func toCsv(_ data: ExportData) -> String {
        var out = "Date,Store,Category,Amount,Currency\n"
        for r in data.rows {
            out += csv(r.dateLabel) + "," + csv(r.store) + "," + csv(r.category) + ","
            out += (r.amount as NSDecimalNumber).stringValue + "," + csv(data.currencySymbol) + "\n"
        }
        return out
    }

    /// "1 – 31 July 2026" / "1 May – 30 Jun 2026" / cross-year variant.
    static func periodLabel(_ interval: DateInterval) -> String {
        let cal = Calendar.current
        let s = cal.startOfDay(for: interval.start)
        let e = cal.date(byAdding: .day, value: -1, to: interval.end).map { cal.startOfDay(for: $0) } ?? interval.end
        let full = DateFormatter(); full.setLocalizedDateFormatFromTemplate("MMMM")
        let short = DateFormatter(); short.setLocalizedDateFormatFromTemplate("MMM")
        let ds = cal.component(.day, from: s), de = cal.component(.day, from: e)
        let ys = cal.component(.year, from: s), ye = cal.component(.year, from: e)
        let ms = cal.component(.month, from: s), me = cal.component(.month, from: e)
        if ys == ye && ms == me { return "\(ds) – \(de) \(full.string(from: e)) \(ye)" }
        if ys == ye { return "\(ds) \(short.string(from: s)) – \(de) \(short.string(from: e)) \(ye)" }
        return "\(ds) \(short.string(from: s)) \(ys) – \(de) \(short.string(from: e)) \(ye)"
    }

    private static func csv(_ s: String) -> String {
        s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }
    private static func mostCommon<T: Hashable>(_ xs: [T]) -> T? {
        var c: [T: Int] = [:]; for x in xs { c[x, default: 0] += 1 }
        return c.max { $0.value < $1.value }?.key
    }
}
