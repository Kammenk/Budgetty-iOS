//
//  SpendingWidget.swift
//  BudgettyWidget
//
//  Home-screen widget: small = this month's spend + budget ring; medium = recent receipts. Reads the
//  shared snapshot written by the app.
//

import WidgetKit
import SwiftUI

private let brand = Color(red: 0x66 / 255, green: 0x50 / 255, blue: 0xA4 / 255)
private let brandGradient = LinearGradient(
    colors: [Color(red: 0x5E / 255, green: 0x4C / 255, blue: 0xAB / 255),
             Color(red: 0x9A / 255, green: 0x6F / 255, blue: 0xE0 / 255)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct SpendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry { SpendingEntry(date: .now, snapshot: .load()) }

    func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
        completion(SpendingEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
        let entry = SpendingEntry(date: .now, snapshot: .load())
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SpendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry
    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall: small
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snap.monthLabel).font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            Spacer()
            Text(snap.money(snap.monthSpent)).font(.title2).bold().foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            if snap.monthlyBudget > 0 {
                ProgressView(value: snap.budgetFraction).tint(.white)
                Text("\(Int(snap.budgetFraction * 100))% of budget")
                    .font(.caption2).foregroundStyle(.white.opacity(0.75))
            } else {
                Text("Total spent").font(.caption2).foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { brandGradient }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Budgetty · \(snap.monthLabel)").font(.caption).bold().foregroundStyle(brand).lineLimit(1)
                Spacer()
                Text(snap.money(snap.monthSpent)).font(.headline)
            }
            Divider()
            if snap.rows.isEmpty {
                Text("No receipts yet").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(snap.rows.prefix(3).enumerated()), id: \.offset) { _, r in
                    HStack {
                        Text(r.store).font(.subheadline).lineLimit(1)
                        Text("· \(r.date)").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(snap.money(r.amount)).font(.subheadline).bold()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

struct SpendingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgettySpending", provider: SpendingProvider()) { entry in
            SpendingWidgetView(entry: entry)
        }
        .configurationDisplayName("Spending")
        .description("Your month's spending and recent receipts.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
