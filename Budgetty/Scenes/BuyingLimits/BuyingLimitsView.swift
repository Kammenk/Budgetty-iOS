//
//  BuyingLimitsView.swift
//  Budgetty
//
//  Account → Buying limits: keyword-based item purchase caps as opt-in challenges. Each card shows a
//  limit's keywords, timeframe, a pip progress row, a calm status, an under-cap streak caption (§4.2)
//  and an 8-window history strip (§4.3); tapping one edits it. Frequency-derived suggestions offer a
//  way in (§4.4). A free user gets `BuyingLimitQuota.freeLimit` limits, then the Add row locks and
//  routes to the paywall. Liquid Glass adaptation of Android's `BuyingLimitsScreen` — the counting,
//  gating, status, streak, history and suggestion logic mirror the Android ViewModel exactly.
//

import SwiftUI
import SwiftData

/// Traffic-light state of a limit: under the cap, exactly at it, or over.
enum BuyingLimitStatus { case onTrack, atLimit, over }

/// Dismissed buying-limit suggestions (§4.4), persisted as a newline-separated `@AppStorage` string of
/// normalized keyword keys (mirrors `WellbeingTipsStore`). A rejected suggestion never returns.
enum LimitSuggestionsStore {
    static func set(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
    static func csv(_ set: Set<String>) -> String { set.sorted().joined(separator: "\n") }
}

struct BuyingLimitsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue
    /// Dismissed suggestion keys (§4.4). A dismissal is a plain per-user pref, not a schema change.
    @AppStorage(SettingsKey.dismissedLimitSuggestions) private var dismissedRaw = ""

    @Query(sort: \BuyingLimit.createdAt) private var limits: [BuyingLimit]
    @Query private var lineItems: [LineItem]

    @State private var editor: EditorTarget?
    @State private var showPaywall = false

    /// How many CLOSED windows the history strip shows and the streak walks (§4.3). Android parity.
    private static let historyWindows = 8

    /// Wraps the editor's subject. `limit` is the row under edit (nil when adding); `prefill` seeds the
    /// fields for a suggestion-created NEW limit (§4.4).
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let limit: BuyingLimit?
        var prefill: BuyingLimitEditorSheet.LimitPrefill?
    }

    /// One limit's derived state, computed once per body so the history strip and the streak read the
    /// SAME 8 closed windows (§4.3) and can never disagree.
    private struct LimitCardData {
        let bought: Int
        let cap: Int
        let status: BuyingLimitStatus
        let streak: Streak
        /// The last 8 CLOSED windows, most-recent first — the single source for the strip AND the streak.
        let windows: [LimitWindow]
        /// How many over the cap (0 unless `.over`) — the N in "Over by N" (§4.1).
        var overBy: Int { max(bought - cap, 0) }
        /// Closed windows that stayed at/under the cap (only windows that held receipts count).
        var historyMet: Int { windows.filter { $0.hasData && $0.count <= cap }.count }
        /// True once at least one closed window held receipts — gates the strip so a new limit shows none.
        var hasHistory: Bool { windows.contains(where: \.hasData) }
    }

    private var items: [CountableItem] {
        lineItems.map { CountableItem(name: $0.name, quantity: $0.quantity, timestamp: $0.createdAt) }
    }
    private var atCap: Bool { BuyingLimitQuota.isAtCap(count: limits.count, isPremium: premium) }

    private var dismissedSuggestions: Set<String> { LimitSuggestionsStore.set(dismissedRaw) }

    private func suggestions(_ all: [CountableItem]) -> [LimitSuggestion] {
        BuyingLimitSuggestions.suggest(items: all, existingKeywords: limits.flatMap(\.keywords),
                                       dismissed: dismissedSuggestions)
    }

    /// One card's live count, its 8 closed windows (derived once, shared by the strip + streak, §4.3),
    /// and the streak. Mirrors Android's `BuyingLimitsViewModel.cardFor`.
    private func derive(_ limit: BuyingLimit, _ all: [CountableItem]) -> LimitCardData {
        let keywords = limit.keywords
        let bought = BuyingLimitCounter.count(all, keywords: keywords, timeframe: limit.timeframe,
                                              startDay: monthStartDay)
        let windows = BuyingLimitCounter.closedWindows(all, keywords: keywords, timeframe: limit.timeframe,
                                                       windowCount: Self.historyWindows, startDay: monthStartDay)
        let live = BuyingLimitCounter.window(limit.timeframe, startDay: monthStartDay)
        let liveWindow = LimitWindow(count: bought, hasData: all.contains { live.contains($0.timestamp) })
        let streak = StreakEngine.limitStreak(LimitStreakInput(label: limit.displayTitle, cap: limit.count,
                                                               closedWindows: windows, live: liveWindow))
        let status: BuyingLimitStatus = bought > limit.count ? .over
            : (bought == limit.count ? .atLimit : .onTrack)
        return LimitCardData(bought: bought, cap: limit.count, status: status, streak: streak, windows: windows)
    }

    var body: some View {
        let all = items
        let cards = limits.map { (limit: $0, data: derive($0, all)) }
        let suggestionList = suggestions(all)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Counted off the items on your saved receipts.")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    .padding(.horizontal, 4).padding(.bottom, 2)

                if limits.isEmpty {
                    emptyState(suggestionList)
                } else {
                    // §4.4: one dismissible suggestion above the list when they already have limits.
                    if let first = suggestionList.first { suggestionRow(first) }
                    ForEach(cards, id: \.limit.persistentModelID) { entry in
                        Button { editor = EditorTarget(limit: entry.limit, prefill: nil) } label: {
                            card(entry.limit, entry.data)
                        }
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
        // §4.2 impression analytics: fire once per unique under-cap streak caption shown (current ≥ 2).
        .task(id: streakSignature(cards)) {
            for entry in cards where entry.data.streak.current >= StreakEngine.minToSurface {
                Analytics.logStreakSurfaced(.limit, length: entry.data.streak.current)
            }
        }
        .toolbar {
            if !limits.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { countPill }
            }
        }
        .sheet(item: $editor) { target in
            BuyingLimitEditorSheet(existing: target.limit, prefill: target.prefill,
                                   items: all, monthStartDay: monthStartDay)
        }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    /// A stable signature of the surfaced streaks, so the impression event fires once per shown length.
    private func streakSignature(_ cards: [(limit: BuyingLimit, data: LimitCardData)]) -> String {
        cards.filter { $0.data.streak.current >= StreakEngine.minToSurface }
            .map { "\($0.data.streak.label):\($0.data.streak.current)" }
            .joined(separator: ",")
    }

    // MARK: - Count pill

    private var countPill: some View {
        Text(atCap ? "\(limits.count) / \(BuyingLimitQuota.freeLimit)" : "\(limits.count)")
            .font(.caption).fontWeight(.bold).foregroundStyle(Palette.tint)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Palette.tintSoft, in: Capsule())
    }

    // MARK: - Limit card

    private func card(_ limit: BuyingLimit, _ data: LimitCardData) -> some View {
        let band = bandColor(data.status)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                emojiChip(limit.emoji)
                Text(limit.displayTitle)
                    .font(.headline).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true) // wraps, never truncates
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusChip(data.status, overBy: data.overBy, band: band)
            }
            if !limit.keywords.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(limit.keywords, id: \.self) { kw in keywordPill(kw) }
                }
            }
            Pips(bought: data.bought, limit: limit.count, band: band)
            metaLine(limit, bought: data.bought, status: data.status, band: band)
            streakCaption(data.streak, timeframe: limit.timeframe)
            if data.hasHistory { historyStrip(limit, data: data) }
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

    /// The calm status chip. On-track and at-limit read ✓ (reaching a cap you set is not a failure, §4.1);
    /// over reads "Over by N" with a bang glyph — but in the WARM band, never red.
    private func statusChip(_ status: BuyingLimitStatus, overBy: Int, band: Color) -> some View {
        let (symbol, text): (String, Text) = switch status {
        case .onTrack: ("checkmark", Text("On track"))
        case .atLimit: ("checkmark", Text("At limit"))
        case .over: ("exclamationmark", Text("Over by \(overBy)"))
        }
        return HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            text.font(.caption2).fontWeight(.bold)
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

    /// §4.2 per-limit streak caption: the shared `StreakMotif` + quiet copy. Surfaces the current run
    /// ("· N weeks/months under") when ≥ 2, else a muted best-run fallback ("Best run: N …") when a past
    /// run was ≥ 2. Renders nothing otherwise — no loss framing, no flames. The motif stays the calm
    /// "good" tone even on a warm card.
    @ViewBuilder
    private func streakCaption(_ streak: Streak, timeframe: BuyingLimitTimeframe) -> some View {
        let weekly = timeframe == .weekly
        let showCurrent = streak.current >= StreakEngine.minToSurface
        let showBest = !showCurrent && streak.best >= StreakEngine.minToSurface
        if showCurrent || showBest {
            let n = showCurrent ? streak.current : streak.best
            HStack(spacing: 6) {
                StreakMotif(filledCount: n, showLive: showCurrent && streak.liveOnTrack,
                            muted: showBest, maxSegments: 6)
                streakCaptionText(current: showCurrent, weekly: weekly, n: n)
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
        }
    }

    private func streakCaptionText(current: Bool, weekly: Bool, n: Int) -> Text {
        switch (current, weekly) {
        case (true, true): Text("· \(n) weeks under")
        case (true, false): Text("· \(n) months under")
        case (false, true): Text("Best run: \(n) weeks")
        case (false, false): Text("Best run: \(n) months")
        }
    }

    /// §4.3 history strip: under a top-border separator, the last 8 closed windows as small squares —
    /// met (good), not-met (warm) or no-data (outline) — oldest on the left, plus "N of the last 8 …" so
    /// a 6-of-8 user sees real progress where a bare streak shows 0.
    private func historyStrip(_ limit: BuyingLimit, data: LimitCardData) -> some View {
        let weekly = limit.timeframe == .weekly
        return VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(Palette.separator).frame(height: 0.5)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    // Most-recent first from the counter → reversed so time reads left (old) → right (new).
                    ForEach(Array(data.windows.reversed().enumerated()), id: \.offset) { _, w in
                        historySquare(w, cap: limit.count)
                    }
                }
                Text(weekly
                     ? "\(data.historyMet) of the last \(data.windows.count) weeks met"
                     : "\(data.historyMet) of the last \(data.windows.count) months met")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(.top, 2)
    }

    private func historySquare(_ w: LimitWindow, cap: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let met = w.hasData && w.count <= cap
        return Group {
            if !w.hasData {
                shape.strokeBorder(Palette.plan, lineWidth: 1.4)
            } else {
                shape.fill(met ? Palette.good : Palette.warn)
            }
        }
        .frame(width: 11, height: 11)
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

    // MARK: - Suggestions (§4.4)

    /// A quiet informational row — "You bought <name> N× last month — cap it?" with the item name
    /// emphasised — that opens the editor pre-filled on tap, plus a dismiss ✕ that remembers the
    /// rejection for good.
    private func suggestionRow(_ s: LimitSuggestion) -> some View {
        Button {
            editor = EditorTarget(limit: nil,
                                  prefill: .init(keyword: s.keyword, count: s.suggestedCap, timeframe: s.timeframe))
        } label: {
            HStack(spacing: 12) {
                emojiChip("")
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestionPrompt(s))
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Suggest \(s.suggestedCap)")
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.tint)
                }
                Spacer(minLength: 8)
                Button { dismissSuggestion(s.keyword) } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.secondaryLabel)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The prompt with the item name bolded, keeping the locale's word order (mirrors Android's
    /// `emphasizeName` over the already-formatted string).
    private func suggestionPrompt(_ s: LimitSuggestion) -> AttributedString {
        var full = AttributedString(String(localized: "You bought \(s.name) \(s.monthCount)× last month — cap it?"))
        if let range = full.range(of: s.name) {
            full[range].inlinePresentationIntent = .stronglyEmphasized
            full[range].foregroundColor = Palette.label
        }
        return full
    }

    private func dismissSuggestion(_ keyword: String) {
        let key = BuyingLimitCounter.normalize(keyword)
        guard !key.isEmpty else { return }
        var set = dismissedSuggestions
        set.insert(key)
        dismissedRaw = LimitSuggestionsStore.csv(set)
    }

    /// §4.4 discovery block on the empty state: "Most bought lately · last 60 days" + up to 3 rows.
    private func suggestionsSection(_ list: [LimitSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("Most bought lately").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                Text("last 60 days").font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            ForEach(list) { suggestionRow($0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty / add / locked

    private func emptyState(_ list: [LimitSuggestion]) -> some View {
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
                // §4.4: with suggestions present, the blank-add CTA steps back to secondary so the
                // suggestions become the primary way in.
                if list.isEmpty {
                    Button { editor = EditorTarget(limit: nil, prefill: nil) } label: {
                        Label("Add limit", systemImage: "plus").font(.subheadline).fontWeight(.bold)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .foregroundStyle(.white).background(Palette.scanCTA, in: Capsule())
                    }
                    .padding(.top, 4)
                } else {
                    Button { editor = EditorTarget(limit: nil, prefill: nil) } label: {
                        Label("Add limit", systemImage: "plus").font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Palette.tint)
                            .padding(.horizontal, 20).padding(.vertical, 11)
                            .overlay(Capsule().strokeBorder(Palette.separatorStrong, lineWidth: 1))
                    }
                    .padding(.top, 4)
                }
                Text("\(BuyingLimitQuota.freeLimit) limits free · unlimited with Premium")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .contentCard(cornerRadius: 16)

            if !list.isEmpty { suggestionsSection(list) }
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
        Button { editor = EditorTarget(limit: nil, prefill: nil) } label: {
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
                Text("The free plan includes \(BuyingLimitQuota.freeLimit) buying limits. Premium adds as many as you like — plus unlimited scans and custom categories.")
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

    /// §4.1: on-track reads good; at-cap AND over both read WARM (amber) — reaching a cap you set is not
    /// a failure, and over-cap is a nudge, never a red loss state.
    private func bandColor(_ status: BuyingLimitStatus) -> Color {
        switch status {
        case .onTrack: Palette.good
        case .atLimit, .over: Palette.warn
        }
    }
}

// MARK: - Pips

/// The pip progress row: one pip per allowed unit, filled up to `bought` in the band colour, the rest
/// muted. Over the cap the overflow (bought) pips are set apart after a small gap and drawn TRANSPARENT
/// with an inset warm ring (§4.1) — over reads warm and distinct, never red. Total = max(limit, bought).
/// Mirrors Android's `Pips`.
private struct Pips: View {
    let bought: Int
    let limit: Int
    let band: Color

    var body: some View {
        let total = max(max(limit, bought), 1)
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                let overCap = i >= limit
                Capsule()
                    .fill(overCap ? Color.clear : (i < bought ? band : Palette.fill))
                    .frame(height: 7)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if overCap { Capsule().strokeBorder(Palette.warn, lineWidth: 1.6) }
                    }
                    // Set the overflow pips apart from the allowed ones when over the cap.
                    .padding(.leading, (i == limit && total > limit) ? 6 : 0)
            }
        }
    }
}
