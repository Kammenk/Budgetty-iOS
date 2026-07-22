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
    /// Past the free tier's widget cap — draw the locked card instead of the data.
    var locked = false
}

struct SpendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry { SpendingEntry(date: .now, snapshot: .load()) }

    /// Never locked: this is what the widget *gallery* previews, and showing a lock there would
    /// advertise the cap instead of the widget.
    func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
        completion(SpendingEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
        Task {
            let locked = await WidgetQuota.isLocked(kind: SpendingWidget.kind, family: context.family)
            let entry = SpendingEntry(date: .now, snapshot: .load(), locked: locked)
            let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct SpendingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendingEntry
    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        if entry.locked {
            LockedWidgetView()
        } else {
            switch family {
            case .systemSmall: small
            default: medium
            }
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

    // Mockup: medium Spend Total = big number + budget on the left, a top-categories mini-chart
    // on the right, over the brand gradient.
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                    Text("Budgetty").font(.caption2).bold().foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text(snap.money(snap.monthSpent)).font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                Text(snap.monthlyBudget > 0
                     ? "\(snap.monthLabel) · \(Int(snap.budgetFraction * 100))% used"
                     : snap.monthLabel)
                    .font(.caption2).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)

            Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5)

            VStack(alignment: .leading, spacing: 7) {
                Text("Top categories").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                if snap.topCategories.isEmpty {
                    Text("No spending yet").font(.caption2).foregroundStyle(.white.opacity(0.6))
                } else {
                    let maxV = snap.topCategories.map(\.amount).max() ?? 1
                    ForEach(Array(snap.topCategories.enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 6) {
                            Text(c.emoji).font(.system(size: 13))
                            GeometryReader { geo in
                                Capsule().fill(.white.opacity(0.22))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(.white.opacity(0.72))
                                            .frame(width: geo.size.width * (maxV > 0 ? c.amount / maxV : 0))
                                    }
                            }
                            .frame(height: 4)
                            Text(snap.money(c.amount)).font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { brandGradient }
    }
}

struct SpendingWidget: Widget {
    /// Also listed in `WidgetQuota.kindOrder` — the cap ranks faces by it.
    static let kind = "BudgettySpending"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: SpendingProvider()) { entry in
            SpendingWidgetView(entry: entry)
        }
        .configurationDisplayName("Spend Total")
        .description("Your month's spending, budget, and top categories.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
