//
//  RecentReceiptsWidget.swift
//  BudgettyWidget
//
//  "Recent Receipts" widget from the iOS Widgets mockup: small = the latest receipt with a
//  "+N earlier · total" footer; medium = the last 3 receipts as rows. Reads the shared snapshot.
//

import WidgetKit
import SwiftUI

private let brandGradient = LinearGradient(
    colors: [Color(red: 0x5E / 255, green: 0x4C / 255, blue: 0xAB / 255),
             Color(red: 0x9A / 255, green: 0x6F / 255, blue: 0xE0 / 255)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct RecentReceiptsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct RecentReceiptsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentReceiptsEntry { RecentReceiptsEntry(date: .now, snapshot: .load()) }
    func getSnapshot(in context: Context, completion: @escaping (RecentReceiptsEntry) -> Void) {
        completion(RecentReceiptsEntry(date: .now, snapshot: .load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentReceiptsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
        completion(Timeline(entries: [RecentReceiptsEntry(date: .now, snapshot: .load())], policy: .after(next)))
    }
}

/// A store's monogram tile (first letter), colored from the store name hash — mirrors the app avatar.
private struct StoreMono: View {
    let store: String
    var size: CGFloat = 26
    private var color: Color {
        let palette: [Color] = [.red, .blue, .orange, .green, .purple, .pink, .teal, .indigo]
        return palette[abs(store.hashValue) % palette.count]
    }
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Text(store.prefix(1).uppercased())
                .font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(.white))
    }
}

struct RecentReceiptsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentReceiptsEntry
    private var snap: WidgetSnapshot { entry.snapshot }

    var body: some View {
        if snap.rows.isEmpty {
            empty
        } else {
            switch family {
            case .systemSmall: small
            default: medium
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "receipt").font(.title2).foregroundStyle(.secondary)
            Text("No receipts yet").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var small: some View {
        let latest = snap.rows[0]
        let earlier = max(0, snap.monthReceiptCount - 1)
        let total = snap.rows.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(snap.monthReceiptCount) new").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 9) {
                StoreMono(store: latest.store, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(latest.store).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(latest.date).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(snap.money(latest.amount)).font(.system(size: 22, weight: .bold)).lineLimit(1)
            if earlier > 0 {
                Text("+\(earlier) earlier · \(snap.money(total))")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(brandGradient)
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: "doc.text.fill").font(.system(size: 11)).foregroundStyle(.white))
                Text("Recent Receipts").font(.system(size: 13, weight: .semibold))
            }
            VStack(spacing: 0) {
                let shown = Array(snap.rows.prefix(3).enumerated())
                ForEach(shown, id: \.offset) { idx, r in
                    HStack(spacing: 8) {
                        StoreMono(store: r.store, size: 26)
                        Text(r.store).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text(snap.money(r.amount)).font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.vertical, 6)
                    if idx < shown.count - 1 { Divider() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

struct RecentReceiptsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BudgettyRecentReceipts", provider: RecentReceiptsProvider()) { entry in
            RecentReceiptsWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Receipts")
        .description("Your latest receipts at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
