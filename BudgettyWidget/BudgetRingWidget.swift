//
//  BudgetRingWidget.swift
//  BudgettyWidget
//
//  "Budget Ring" widget from the iOS Widgets mockup: small = a progress ring with the % used;
//  medium = the ring plus spent/left figures and the top category bars. Reads the shared snapshot.
//

import WidgetKit
import SwiftUI

struct BudgetRingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct BudgetRingProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetRingEntry { BudgetRingEntry(date: .now, snapshot: .load()) }
    func getSnapshot(in context: Context, completion: @escaping (BudgetRingEntry) -> Void) {
        completion(BudgetRingEntry(date: .now, snapshot: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetRingEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        completion(Timeline(entries: [BudgetRingEntry(date: .now, snapshot: .load())], policy: .after(next)))
    }
}

private func ringColor(_ frac: Double) -> Color {
    frac >= 1 ? .red : (frac >= 0.85 ? .orange : .green)
}

/// The circular budget gauge shared by both sizes.
private struct BudgetRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 10
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(ringColor(fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((fraction * 100).rounded()))%").font(.system(size: 22, weight: .bold))
                Text("of budget").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }
}

struct BudgetRingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BudgetRingEntry
    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        if snap.monthlyBudget <= 0 {
            noBudget
        } else {
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
    }

    private var noBudget: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie").font(.title2).foregroundStyle(.secondary)
            Text("Set a budget").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var small: some View {
        VStack(spacing: 6) {
            BudgetRing(fraction: snap.budgetFraction).padding(4)
            Text("\(snap.money(snap.budgetLeft)) left")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            BudgetRing(fraction: snap.budgetFraction, lineWidth: 11).frame(width: 112)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monthly Budget").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(snap.monthLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    figure("Spent", snap.money(snap.monthSpent), color: ringColor(snap.budgetFraction))
                    Spacer()
                    figure("Left", snap.money(snap.budgetLeft), color: .green, trailing: true)
                }
                VStack(spacing: 6) {
                    let maxV = snap.topCategories.map(\.amount).max() ?? 1
                    ForEach(Array(snap.topCategories.prefix(2).enumerated()), id: \.offset) { _, c in
                        HStack(spacing: 7) {
                            Text(c.emoji).font(.system(size: 12))
                            GeometryReader { geo in
                                Capsule().fill(Color.gray.opacity(0.2))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(Color(argb: c.colorArgb))
                                            .frame(width: geo.size.width * (maxV > 0 ? c.amount / maxV : 0))
                                    }
                            }
                            .frame(height: 5)
                            Text(snap.money(c.amount)).font(.system(size: 10))
                                .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func figure(_ label: String, _ value: String, color: Color, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(color).lineLimit(1)
        }
    }
}

struct BudgetRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgettyBudgetRing", provider: BudgetRingProvider()) { entry in
            BudgetRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Budget Ring")
        .description("How much of your monthly budget remains.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
