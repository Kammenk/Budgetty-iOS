//
//  ThisWeekWidget.swift
//  BudgettyWidget
//
//  Home-screen widget: this week's spend vs last week (Mon–Sun). Android's "This Week" face. Reads
//  the shared snapshot written by the app.
//

import WidgetKit
import SwiftUI

private let weekGradient = LinearGradient(
    colors: [Color(red: 0x5E / 255, green: 0x4C / 255, blue: 0xAB / 255),
             Color(red: 0x9A / 255, green: 0x6F / 255, blue: 0xE0 / 255)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct ThisWeekEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var locked = false
}

struct ThisWeekProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThisWeekEntry { ThisWeekEntry(date: .now, snapshot: .load()) }

    func getSnapshot(in context: Context, completion: @escaping (ThisWeekEntry) -> Void) {
        completion(ThisWeekEntry(date: .now, snapshot: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ThisWeekEntry>) -> Void) {
        Task {
            let locked = await WidgetQuota.isLocked(kind: ThisWeekWidget.kind, family: context.family)
            let entry = ThisWeekEntry(date: .now, snapshot: .load(), locked: locked)
            let next = Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now.addingTimeInterval(7200)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct ThisWeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ThisWeekEntry
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

    /// "▲/▼ N% vs last week" when there's a prior week to compare, otherwise a plain caption.
    @ViewBuilder private var deltaLabel: some View {
        if let d = snap.weekDeltaFraction {
            HStack(spacing: 3) {
                Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                Text("\(abs(Int((d * 100).rounded())))% vs last week").font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        } else {
            Text("vs last week").font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week").font(.caption2).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            Spacer()
            Text(snap.money(snap.weekThis)).font(.title2).bold().foregroundStyle(.white)
                .minimumScaleFactor(0.6).lineLimit(1)
            deltaLabel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { weekGradient }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                    Text("This week").font(.caption2).bold().foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text(snap.money(snap.weekThis)).font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                deltaLabel
            }
            .frame(width: 140, alignment: .leading)

            Rectangle().fill(.white.opacity(0.2)).frame(width: 0.5)

            VStack(alignment: .leading, spacing: 12) {
                let maxV = max(snap.weekThis, snap.weekLast, 1)
                weekBar("This week", snap.weekThis, maxV, .white.opacity(0.85))
                weekBar("Last week", snap.weekLast, maxV, .white.opacity(0.4))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { weekGradient }
    }

    private func weekBar(_ label: LocalizedStringKey, _ value: Double, _ maxV: Double, _ fill: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(snap.money(value)).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            GeometryReader { geo in
                Capsule().fill(.white.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(fill).frame(width: geo.size.width * (maxV > 0 ? value / maxV : 0))
                    }
            }
            .frame(height: 5)
        }
    }
}

struct ThisWeekWidget: Widget {
    /// Also listed in `WidgetQuota.kindOrder` — the cap ranks faces by it.
    static let kind = "BudgettyThisWeek"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: ThisWeekProvider()) { entry in
            ThisWeekWidgetView(entry: entry)
        }
        .configurationDisplayName("This Week")
        .description("This week's spending compared with last week.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
