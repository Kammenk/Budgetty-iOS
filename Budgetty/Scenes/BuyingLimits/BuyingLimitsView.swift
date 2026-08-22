//
//  BuyingLimitsView.swift
//  Budgetty
//
//  Account → Buying limits: keyword-based item purchase caps, a sibling to Category rules. Each card
//  shows a limit's keywords, timeframe, a pip progress row and a traffic-light status; tapping one
//  edits it. A free user gets one limit, then the Add row locks and routes to the paywall. Liquid
//  Glass adaptation of Android's `BuyingLimitsScreen` — the counting, gating and status logic mirror
//  the Android ViewModel exactly (see `BuyingLimitCounter`).
//

import SwiftUI
import SwiftData

/// Traffic-light state of a limit: under the cap, exactly at it, or over.
enum BuyingLimitStatus { case onTrack, atLimit, over }

struct BuyingLimitsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue

    @Query(sort: \BuyingLimit.createdAt) private var limits: [BuyingLimit]
    @Query private var lineItems: [LineItem]

    @State private var editor: EditorTarget?
    @State private var showPaywall = false

    /// Wraps the editor's subject so a nil limit (new) is distinguishable from "editor closed".
    private struct EditorTarget: Identifiable { let id = UUID(); let limit: BuyingLimit? }

    private var items: [CountableItem] {
        lineItems.map { CountableItem(name: $0.name, quantity: $0.quantity, timestamp: $0.createdAt) }
    }
    private var atCap: Bool { !premium && limits.count >= BuyingLimitQuota.freeLimit }

    private func bought(_ limit: BuyingLimit) -> Int {
        BuyingLimitCounter.count(items, keywords: limit.keywords, timeframe: limit.timeframe,
                                 startDay: monthStartDay)
    }
    private func status(_ limit: BuyingLimit) -> BuyingLimitStatus {
        let n = bought(limit)
        if n > limit.count { return .over }
        if n == limit.count { return .atLimit }
        return .onTrack
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Counted off the items on your saved receipts.")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    .padding(.horizontal, 4).padding(.bottom, 2)

                if limits.isEmpty {
                    emptyState
                } else {
                    ForEach(limits) { limit in
                        Button { editor = EditorTarget(limit: limit) } label: { card(limit) }
                            .buttonStyle(.plain)
                    }
                    if atCap { lockedSection } else { addButton }
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            .adaptiveReadableWidth()
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        .navigationTitle("Buying limits")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !limits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { countPill }
            }
        }
        .sheet(item: $editor) { target in
            BuyingLimitEditorSheet(existing: target.limit, items: items, monthStartDay: monthStartDay)
        }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    // MARK: - Count pill

    private var countPill: some View {
        Text(atCap ? "\(limits.count) / \(BuyingLimitQuota.freeLimit)" : "\(limits.count)")
            .font(.caption).fontWeight(.bold).foregroundStyle(Palette.tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Palette.tintSoft, in: Capsule())
    }

    // MARK: - Limit card

    private func card(_ limit: BuyingLimit) -> some View {
        let n = bought(limit)
        let s = status(limit)
        let band = bandColor(s)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                emojiChip(limit.emoji)
                Text(limit.displayTitle)
                    .font(.headline).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true) // wraps, never truncates
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusChip(s, band: band)
            }
            if !limit.keywords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(limit.keywords, id: \.self) { kw in keywordPill(kw) }
                }
            }
            Pips(bought: n, limit: limit.count, band: band)
            metaLine(limit, bought: n, status: s, band: band)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    /// 32pt emoji tile in the tint-soft chip colour; a tag glyph when the limit has no emoji.
    private func emojiChip(_ emoji: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Palette.tintSoft)
            .frame(width: 32, height: 32)
            .overlay {
                if emoji.isEmpty {
                    Image(systemName: "tag.fill").font(.system(size: 14)).foregroundStyle(Palette.tint)
                } else {
                    Text(emoji).font(.system(size: 17))
                }
            }
    }

    private func statusChip(_ status: BuyingLimitStatus, band: Color) -> some View {
        let (symbol, text): (String, LocalizedStringKey) = switch status {
        case .onTrack: ("checkmark", "On track")
        case .atLimit: ("exclamationmark", "At limit")
        case .over: ("exclamationmark", "Over")
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            Text(text).font(.caption2).fontWeight(.bold)
        }
        .foregroundStyle(band)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(band.opacity(0.15), in: Capsule())
        .fixedSize()
    }

    private func keywordPill(_ text: String) -> some View {
        Text(text)
            .font(.caption).foregroundStyle(Palette.secondaryLabel)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Palette.fill, in: Capsule())
    }

    /// The meta line: "{Weekly|Monthly} · {progress} · resets {date}" — progress bold in the band color.
    private func metaLine(_ limit: BuyingLimit, bought n: Int,
                          status: BuyingLimitStatus, band: Color) -> some View {
        let timeframeText = Text(limit.timeframe == .weekly ? "Weekly" : "Monthly")
        let progress = status == .over
            ? Text("Bought \(n), limit \(limit.count)")
            : Text("Bought \(n) of \(limit.count)")
        let sep = Text(verbatim: " · ")
        return (timeframeText + sep
                + progress.fontWeight(.bold).foregroundStyle(band)
                + sep + Text("resets \(resetLabel(limit))"))
            .font(.caption).foregroundStyle(Palette.secondaryLabel)
    }

    /// "Mon" for weekly, "1 Sep" for monthly — the date the current window rolls over.
    private func resetLabel(_ limit: BuyingLimit) -> String {
        let next = BuyingLimitCounter.nextReset(limit.timeframe, startDay: monthStartDay)
        if limit.timeframe == .weekly {
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: next)
        }
        return (DateFormatOption(rawValue: dateFormatRaw) ?? .system).short(next)
    }

    // MARK: - Empty / add / locked

    private var emptyState: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.tintSoft)
                    .frame(width: 46, height: 46)
                    .overlay(Image(systemName: "tag.fill").font(.system(size: 20)).foregroundStyle(Palette.tint))
                Text("Set a buying limit").font(.headline).foregroundStyle(Palette.label)
                Text("Cap how many of something you buy — we'll count it off your receipts.")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    .multilineTextAlignment(.center)
                Button { editor = EditorTarget(limit: nil) } label: {
                    Label("Add limit", systemImage: "plus").font(.subheadline).fontWeight(.bold)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .foregroundStyle(.white).background(Palette.scanCTA, in: Capsule())
                }
                .padding(.top, 4)
                Text("1 limit free · unlimited with Premium")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .contentCard(cornerRadius: 16)

            explainerBlock
        }
    }

    private var explainerBlock: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").font(.system(size: 15))
                .foregroundStyle(Palette.secondaryLabel)
            (Text("A limit is a few keywords, a week or a month, and a number.")
             + Text(verbatim: "  ")
             + Text("no more than 1 Coke a week").fontWeight(.semibold).foregroundStyle(Palette.label))
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var addButton: some View {
        Button { editor = EditorTarget(limit: nil) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("Add limit").fontWeight(.semibold)
                Spacer()
            }
            .foregroundStyle(Palette.tint)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    /// The free-cap locked state: a dimmed padlock Add row + the "unlock" upsell card + a used footnote.
    private var lockedSection: some View {
        VStack(spacing: 12) {
            Button { showPaywall = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold))
                    Text("Add limit").fontWeight(.semibold)
                    Spacer()
                    Text("Premium").font(.caption).fontWeight(.bold)
                }
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentCard(cornerRadius: 16)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Label("Unlock unlimited buying limits", systemImage: "star.fill")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                Text("The free plan includes 1 buying limit. Premium adds as many as you like — plus unlimited scans and custom categories.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
                Button { showPaywall = true } label: {
                    Text("Go Premium").font(.subheadline).fontWeight(.bold).ctaPill(height: 46)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .contentCard(cornerRadius: 16)

            Text("\(limits.count) of \(BuyingLimitQuota.freeLimit) free limits used")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                .frame(maxWidth: .infinity)
        }
    }

    private func bandColor(_ status: BuyingLimitStatus) -> Color {
        switch status {
        case .onTrack: Palette.good
        case .atLimit: Palette.warn
        case .over: Palette.bad
        }
    }
}

// MARK: - Pips

/// The pip progress row: one pip per allowed unit, filled up to `bought` in the band colour, the rest
/// muted. When over the cap, the overflow pips are set apart after a small gap. Total = max(limit,
/// bought). Mirrors Android's `Pips`.
private struct Pips: View {
    let bought: Int
    let limit: Int
    let band: Color

    var body: some View {
        let total = max(max(limit, bought), 1)
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < bought ? band : Palette.fill)
                    .frame(height: 7)
                    .frame(maxWidth: .infinity)
                    // Set the overflow pips apart from the allowed ones when over the cap.
                    .padding(.leading, (i == limit && total > limit) ? 6 : 0)
            }
        }
    }
}
