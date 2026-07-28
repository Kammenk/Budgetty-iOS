//
//  TopCategoriesWidget.swift
//  BudgettyWidget
//
//  Home-screen widget: this month's spending broken down by top category groups. Android's "Top
//  Categories" face. Reads the shared snapshot written by the app.
//

import WidgetKit
import SwiftUI

private let topCatGradient = LinearGradient(
    colors: [Color(red: 0x5E / 255, green: 0x4C / 255, blue: 0xAB / 255),
             Color(red: 0x9A / 255, green: 0x6F / 255, blue: 0xE0 / 255)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct TopCategoriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var locked = false
}

struct TopCategoriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopCategoriesEntry { TopCategoriesEntry(date: .now, snapshot: .load()) }

    func getSnapshot(in context: Context, completion: @escaping (TopCategoriesEntry) -> Void) {
        completion(TopCategoriesEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopCategoriesEntry>) -> Void) {
        Task {
            let locked = await WidgetQuota.isLocked(kind: TopCategoriesWidget.kind, family: context.family)
            let entry = TopCategoriesEntry(date: .now, snapshot: .load(), locked: locked)
            let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct TopCategoriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TopCategoriesEntry
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

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.pie.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            Text("Top categories").font(.caption2).bold().foregroundStyle(.white.opacity(0.8))
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No spending yet").font(.caption2).foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if snap.topCategories.isEmpty {
                emptyState
            } else {
                Spacer(minLength: 2)
                ForEach(Array(snap.topCategories.prefix(3).enumerated()), id: \.offset) { _, c in
                    HStack(spacing: 6) {
                        Text(c.emoji).font(.system(size: 14))
                        Text(snap.money(c.amount)).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white).minimumScaleFactor(0.7).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { topCatGradient }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if snap.topCategories.isEmpty {
                emptyState
            } else {
                let maxV = snap.topCategories.map(\.amount).max() ?? 1
                ForEach(Array(snap.topCategories.enumerated()), id: \.offset) { _, c in
                    HStack(spacing: 8) {
                        Text(c.emoji).font(.system(size: 15))
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.22))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white.opacity(0.75))
                                        .frame(width: geo.size.width * (maxV > 0 ? c.amount / maxV : 0))
                                }
                        }
                        .frame(height: 6)
                        Text(snap.money(c.amount)).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { topCatGradient }
    }
}

struct TopCategoriesWidget: Widget {
    /// Also listed in `WidgetQuota.kindOrder` — the cap ranks faces by it.
    static let kind = "BudgettyTopCategories"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TopCategoriesProvider()) { entry in
            TopCategoriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Top Categories")
        .description("Your month's spending by category.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
