//
//  RecapStoryView.swift
//  Budgetty
//
//  The full-screen Wrapped-style recap story — the Swift port of Android's `RecapStoryScreen`. A
//  swipeable sequence of one-figure cards on tonal band backdrops, with a segmented progress bar, a ✕
//  that exits any time, and — only on the final card — the Done / See details actions. Tap the right
//  two-thirds to advance, the left third to go back (swipe does the same). No auto-advance: a recap is
//  read, not watched.
//
//  Stateless: it renders a prebuilt `RecapStory` and calls back on exit. Used both as the on-open
//  interstitial (via the gate in `RootView`) and re-opened from Insights (`RecapReopenView`).
//

import SwiftUI

struct RecapStoryView: View {
    let story: RecapStory
    var onClose: () -> Void
    var onSeeDetails: () -> Void

    @State private var index: Int = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["RECAP_START"], let i = Int(raw) { return i }
        #endif
        return 0
    }()
    @State private var forward = true

    private var cards: [RecapCard] { story.cards }
    private var currentIndex: Int { min(index, max(0, cards.count - 1)) }

    var body: some View {
        ZStack {
            cardLayer
            interactionLayer
            chrome
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
    }

    // MARK: - Card layer (per-card backdrop + centred content)

    private var cardLayer: some View {
        let card = cards[currentIndex]
        return ZStack {
            recapBandColor(card.band).ignoresSafeArea()
            RecapCardBody(story: story, card: card)
                .frame(maxWidth: RecapMetrics.contentMaxWidth)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 104)
                .padding(.bottom, 128)
        }
        .id(currentIndex)
        .transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
    }

    // MARK: - Interaction (tap left/right, swipe)

    private var interactionLayer: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(coordinateSpace: .local).onEnded { value in
                        if value.location.x < geo.size.width / 3 { goBack() } else { goForward() }
                    })
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24).onEnded { value in
                        if value.translation.width < -40 { goForward() }
                        else if value.translation.width > 40 { goBack() }
                    })
        }
    }

    private func goForward() {
        guard currentIndex < cards.count - 1 else { return }
        forward = true
        withAnimation(.easeInOut(duration: 0.28)) { index = currentIndex + 1 }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        forward = false
        withAnimation(.easeInOut(duration: 0.28)) { index = currentIndex - 1 }
    }

    // MARK: - Chrome (progress + header + actions)

    private var chrome: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                progressBar.allowsHitTesting(false)
                header
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
            if currentIndex == cards.count - 1 { actions }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<cards.count, id: \.self) { i in
                Capsule()
                    .fill(i <= currentIndex ? Palette.label : Palette.label.opacity(0.22))
                    .frame(height: 3)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            VStack(alignment: .leading, spacing: 1) {
                Text(barTitle).font(.headline).foregroundStyle(Palette.label)
                Text(tagKey).font(.caption2).fontWeight(.semibold).kerning(1)
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .allowsHitTesting(false)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: onClose) {
                Text("Done").font(.headline).ctaPill()
            }
            .buttonStyle(.plain)
            Button(action: onSeeDetails) {
                HStack(spacing: 3) {
                    Text("See details")
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                }
                .font(.subheadline).foregroundStyle(Palette.tint)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: RecapMetrics.contentMaxWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    private var barTitle: String {
        story.kind == .monthly ? RecapFormat.monthName(story.monthStart) : String(localized: "This week")
    }

    private var tagKey: LocalizedStringKey {
        story.kind == .monthly ? "MONTHLY RECAP" : "WEEKLY RECAP"
    }
}

// MARK: - Card body

private struct RecapCardBody: View {
    let story: RecapStory
    let card: RecapCard

    var body: some View {
        VStack(spacing: 0) {
            switch card {
            case .cover: CoverBody(story: story)
            case let .total(_, spent, deltaPercent, prevMonthStart, prevTotal, improved):
                TotalBody(story: story, spent: spent, deltaPercent: deltaPercent,
                          prevMonthStart: prevMonthStart, prevTotal: prevTotal, improved: improved)
            case let .score(_, score, scoreBand, delta, prevMonthStart):
                ScoreBody(score: score, scoreBand: scoreBand, delta: delta, prevMonthStart: prevMonthStart)
            case let .mover(_, category, dotColorArgb, delta, previousAmount, currentAmount, second):
                MoverBody(category: category, dotColorArgb: dotColorArgb, delta: delta,
                          previousAmount: previousAmount, currentAmount: currentAmount, second: second)
            case let .budgetStreak(_, streakMonths, underCount, scopeCount, segments, safeToSpend):
                BudgetStreakBody(streakMonths: streakMonths, underCount: underCount, scopeCount: scopeCount,
                                 segments: segments, safeToSpend: safeToSpend)
            case let .limits(_, underCount, totalCount, chips):
                LimitsBody(underCount: underCount, totalCount: totalCount, chips: chips)
            case let .pace(_, spent, weeklyBudget, fractionUsed, _, remaining, deltaPercent):
                PaceBody(spent: spent, weeklyBudget: weeklyBudget, fractionUsed: fractionUsed,
                         remaining: remaining, deltaPercent: deltaPercent)
            case let .focus(_, focus, isWeekly):
                FocusBody(story: story, focus: focus, isWeekly: isWeekly)
            }
        }
    }
}

// MARK: - Cover

private struct CoverBody: View {
    let story: RecapStory
    var body: some View {
        VStack(spacing: 0) {
            RecapKicker(story.kind == .monthly ? "MONTHLY RECAP" : "WEEKLY RECAP")
            Spacer().frame(height: 16)
            title
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            subtitle
                .font(.title3)
                .foregroundStyle(Palette.label.opacity(0.8))
                .multilineTextAlignment(.center)
            Spacer().frame(height: 28)
            Text("Tap to start")
                .font(.footnote).foregroundStyle(Palette.label.opacity(0.6))
        }
    }

    private var title: Text {
        story.kind == .monthly
            ? Text("Your \(RecapFormat.monthName(story.monthStart)), in review")
            : Text("Your week, in review")
    }

    private var subtitle: Text {
        story.kind == .monthly
            ? Text("Tap to move forward, tap the left edge to go back.")
            : Text(verbatim: "\(RecapFormat.dayMonth(story.weekStart)) – \(RecapFormat.dayMonth(story.weekEnd))")
    }
}

// MARK: - Total

private struct TotalBody: View {
    let story: RecapStory
    let spent: Decimal
    let deltaPercent: Int?
    let prevMonthStart: Date?
    let prevTotal: Decimal?
    let improved: Bool

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("YOU SPENT IN \(RecapFormat.monthNameUpper(story.monthStart))")
            Spacer().frame(height: 12)
            RecapBigFigure(spent.formatMoney())
            if let pct = deltaPercent {
                Spacer().frame(height: 16)
                let less = pct <= 0
                RecapPill(tone: less ? .good : .warn) {
                    Text(verbatim: (less ? "↓ " : "↑ ") + "\(abs(pct))% ")
                        + Text("vs \(RecapFormat.monthName(prevMonthStart ?? story.monthStart))")
                }
            }
            Spacer().frame(height: 16)
            subtitle
                .font(.title3).foregroundStyle(Palette.label.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var subtitle: Text {
        guard let pct = deltaPercent, let prevMonthStart, let prevTotal else {
            return Text("Your total spending for \(RecapFormat.monthName(story.monthStart)).")
        }
        let diff = abs(spent - prevTotal).formatMoney()
        let prevName = RecapFormat.monthName(prevMonthStart)
        return pct <= 0
            ? Text("\(diff) less than \(prevName) (\(prevTotal.formatMoney())).")
            : Text("\(diff) more than \(prevName) (\(prevTotal.formatMoney())).")
    }
}

// MARK: - Score

private struct ScoreBody: View {
    let score: Int
    let scoreBand: WellbeingBand
    let delta: Int?
    let prevMonthStart: Date?

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("WELLBEING SCORE")
            Spacer().frame(height: 20)
            SavingsRing(fraction: Double(score) / 100, color: wbBandColor(scoreBand), lineWidth: 12) {
                VStack(spacing: 2) {
                    Text("\(score)").font(.system(size: 46, weight: .heavy)).foregroundStyle(Palette.label)
                    Text(wbBandWord(scoreBand)).font(.headline).fontWeight(.bold)
                        .foregroundStyle(wbBandColor(scoreBand))
                }
            }
            .frame(width: 168, height: 168)
            if let d = delta {
                Spacer().frame(height: 16)
                RecapPill(tone: d >= 0 ? .good : .warn) {
                    Text(verbatim: (d >= 0 ? "↑ " : "↓ ") + "\(abs(d)) ")
                        + Text("vs \(RecapFormat.monthName(prevMonthStart ?? story0))")
                }
            }
            Spacer().frame(height: 16)
            Text("Built from savings, budget, goals, trend and subscriptions. Updates monthly.")
                .font(.subheadline).foregroundStyle(Palette.label.opacity(0.8))
                .multilineTextAlignment(.center)
        }
    }

    /// Fallback month reference when there's no prior month (never rendered — delta is nil then).
    private var story0: Date { prevMonthStart ?? .now }
}

// MARK: - Mover

private struct MoverBody: View {
    let category: String
    let dotColorArgb: Int
    let delta: Decimal
    let previousAmount: Decimal
    let currentAmount: Decimal
    let second: RecapSecondMover?

    private var drop: Bool { delta < 0 }
    private var accent: Color { drop ? Palette.good : Palette.warn }

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("YOUR BIGGEST MOVE")
            Spacer().frame(height: 16)
            HStack(spacing: 8) {
                Circle().fill(Color(argb: dotColorArgb)).frame(width: 12, height: 12)
                Text(Categories.displayName(category))
                    .font(.system(size: 22, weight: .bold)).foregroundStyle(Palette.label)
            }
            Spacer().frame(height: 12)
            RecapBigFigure((drop ? "−" : "+") + abs(delta).formatMoney(), color: accent)
            Spacer().frame(height: 16)
            subtitle
                .font(.title3).foregroundStyle(Palette.label.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var subtitle: Text {
        let name = Categories.displayName(category)
        let prev = previousAmount.formatMoney()
        let curr = currentAmount.formatMoney()
        let primary = drop
            ? Text("\(name) dropped from \(prev) to \(curr).")
            : Text("\(name) rose from \(prev) to \(curr).")
        guard let second else { return primary }
        let secondName = Categories.displayName(second.category)
        let amt = abs(second.delta).formatMoney()
        let clause = second.delta < 0
            ? Text("\(secondName) went down \(amt).")
            : Text("\(secondName) went up \(amt).")
        return primary + Text(verbatim: " ") + clause
    }
}

// MARK: - Budget & streak

private struct BudgetStreakBody: View {
    let streakMonths: Int
    let underCount: Int
    let scopeCount: Int
    let segments: [RecapSegStatus]
    let safeToSpend: Decimal

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("BUDGET")
            Spacer().frame(height: 12)
            title
                .font(.system(size: 28, weight: .heavy)).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text("Under budget in \(underCount) of \(scopeCount) categories")
                    .font(.subheadline).foregroundStyle(Palette.label)
                Spacer().frame(height: 8)
                RecapSegmentBar(segments: segments)
                Spacer().frame(height: 16)
                Text("Safe to spend, at the close")
                    .font(.footnote).foregroundStyle(Palette.label.opacity(0.7))
                let positive = safeToSpend >= 0
                Text(verbatim: (positive ? "+" : "−") + abs(safeToSpend).formatMoney())
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(positive ? Palette.good : Palette.warn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var title: Text {
        streakMonths > 1
            ? Text("\(streakMonths) months under budget in a row") + Text(verbatim: " 🔥")
            : Text("Under budget this month")
    }
}

// MARK: - Limits

private struct LimitsBody: View {
    let underCount: Int
    let totalCount: Int
    let chips: [RecapLimitChip]

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("BUYING LIMITS")
            Spacer().frame(height: 12)
            RecapBigFigure("\(underCount) of \(totalCount)")
            Spacer().frame(height: 16)
            Text("You stayed under \(underCount) of \(totalCount) limits.")
                .font(.title3).foregroundStyle(Palette.label.opacity(0.85))
                .multilineTextAlignment(.center)
            Spacer().frame(height: 16)
            VStack(spacing: 8) {
                ForEach(chips) { chip in chipRow(chip) }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func chipRow(_ chip: RecapLimitChip) -> some View {
        HStack(spacing: 8) {
            Text(chip.emoji).font(.title3)
            Text(verbatim: "\(chip.label) \(chip.bought)/\(chip.cap)")
                .font(.subheadline).fontWeight(.medium).foregroundStyle(Palette.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((chip.under ? Palette.good : Palette.bad).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Pace (weekly)

private struct PaceBody: View {
    let spent: Decimal
    let weeklyBudget: Decimal?
    let fractionUsed: Double
    let remaining: Decimal
    let deltaPercent: Int?

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker("YOU SPENT THIS WEEK")
            Spacer().frame(height: 12)
            RecapBigFigure(spent.formatMoney())
            if let pct = deltaPercent {
                Spacer().frame(height: 16)
                let less = pct <= 0
                RecapPill(tone: less ? .good : .warn) {
                    Text(verbatim: (less ? "↓ " : "↑ ") + "\(abs(pct))% ") + Text("vs last week")
                }
            }
            Spacer().frame(height: 20)
            VStack(alignment: .leading, spacing: 0) {
                if let budget = weeklyBudget, budget > 0 {
                    let over = spent > budget
                    Text("\(spent.formatMoney()) of your \(budget.formatMoney()) weekly budget")
                        .font(.subheadline).foregroundStyle(Palette.label)
                    Spacer().frame(height: 8)
                    ProgressBarView(fraction: fractionUsed, color: over ? Palette.warn : Palette.good,
                                    height: 8, track: Palette.label.opacity(0.18))
                    Spacer().frame(height: 8)
                    (over ? Text("\((spent - budget).formatMoney()) over budget")
                          : Text("\(remaining.formatMoney()) left"))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(over ? Palette.warn : Palette.good)
                } else {
                    Text("No weekly budget set")
                        .font(.subheadline).foregroundStyle(Palette.label.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

// MARK: - Focus (closing)

private struct FocusBody: View {
    let story: RecapStory
    let focus: RecapFocus
    let isWeekly: Bool

    var body: some View {
        VStack(spacing: 0) {
            RecapKicker(kicker)
            Spacer().frame(height: 16)
            title
                .font(.system(size: 26, weight: .heavy)).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            if isWeekly {
                Spacer().frame(height: 16)
                Text("Your score is unchanged — it updates monthly.")
                    .font(.subheadline).foregroundStyle(Palette.label.opacity(0.75))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var kicker: LocalizedStringKey {
        isWeekly ? "FOCUS THIS WEEK" : "FOCUS FOR \(RecapFormat.monthNameUpper(story.nextMonthStart))"
    }

    private var title: Text {
        switch focus {
        case let .capCategory(category, amount):
            return Text("Keep \(Categories.displayName(category)) under \(amount.formatMoney()).")
        case let .watchCategory(category):
            return Text("Keep an eye on \(Categories.displayName(category)).")
        case let .setBudget(category):
            return Text("Set a budget for \(Categories.displayName(category)).")
        case .keepItUp:
            return Text("Keep it up — you are trending the right way.")
        }
    }
}

// MARK: - Shared bits

private struct RecapKicker: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }
    var body: some View {
        Text(key)
            .font(.caption).fontWeight(.bold).kerning(1.5)
            .foregroundStyle(Palette.label.opacity(0.65))
            .multilineTextAlignment(.center)
    }
}

private struct RecapBigFigure: View {
    let text: String
    var color: Color = Palette.label
    init(_ text: String, color: Color = Palette.label) { self.text = text; self.color = color }
    var body: some View {
        Text(text)
            .font(.system(size: 54, weight: .heavy))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }
}

private struct RecapPill<Content: View>: View {
    let tone: RecapPillTone
    @ViewBuilder let content: () -> Content

    private var accent: Color {
        switch tone {
        case .good: Palette.good
        case .warn: Palette.warn
        case .neutral: Palette.label
        }
    }

    var body: some View {
        content()
            .font(.subheadline).fontWeight(.bold).foregroundStyle(accent)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct RecapSegmentBar: View {
    let segments: [RecapSegStatus]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Capsule().fill(color(seg)).frame(height: 8)
            }
        }
    }
    private func color(_ status: RecapSegStatus) -> Color {
        switch status {
        case .good: Palette.good
        case .warn: Palette.warn
        case .bad: Palette.bad
        }
    }
}

/// The full-screen tonal band backdrop for a card — the recap mockup's container tints, theme-aware.
func recapBandColor(_ band: RecapBand) -> Color {
    switch band {
    case .primary: Palette.recapPrimary
    case .good: Palette.recapGood
    case .warn: Palette.recapWarn
    case .great: Palette.recapGreat
    case .secondary: Palette.recapSecondary
    case .neutral: Palette.recapNeutral
    }
}

// MARK: - Formatting helpers

enum RecapMetrics {
    /// Caps the story content column so it stays a comfortable reading width, centred on iPad.
    static let contentMaxWidth: CGFloat = 460
}

enum RecapFormat {
    static func monthName(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMM")
        return f.string(from: date)
    }
    static func monthNameUpper(_ date: Date) -> String {
        monthName(date).uppercased(with: .current)
    }
    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date)
    }
}

// MARK: - Preview / debug sample

#if DEBUG
extension RecapStory {
    /// A fully-populated monthly sample matching the mockup's July numbers — used by the Xcode preview
    /// and the `SHOW_SCREEN=recap` screenshot hook.
    static func debugMonthlySample() -> RecapStory {
        RecapStory(
            kind: .monthly,
            monthStart: Date(timeIntervalSince1970: 1_751_328_000), // 1 Jul 2025
            nextMonthStart: Date(timeIntervalSince1970: 1_754_006_400),
            weekStart: Date(timeIntervalSince1970: 1_751_328_000),
            weekEnd: Date(timeIntervalSince1970: 1_753_920_000),
            cards: [
                .cover(band: .primary),
                .total(band: .good, spent: 1240, deltaPercent: -12,
                       prevMonthStart: Date(timeIntervalSince1970: 1_748_736_000),
                       prevTotal: 1409, improved: true),
                .score(band: .secondary, score: 72, scoreBand: .healthy, delta: 4,
                       prevMonthStart: Date(timeIntervalSince1970: 1_748_736_000)),
                .mover(band: .neutral, category: "Restaurant & Dining", dotColorArgb: 0xFFE0795B,
                       delta: -40, previousAmount: 120, currentAmount: 80,
                       second: RecapSecondMover(category: "Groceries", delta: 25)),
                .budgetStreak(band: .great, streakMonths: 3, underCount: 5, scopeCount: 6,
                              segments: [.good, .good, .warn, .good, .good, .bad], safeToSpend: 60),
                .limits(band: .warn, underCount: 3, totalCount: 4, chips: [
                    RecapLimitChip(emoji: "🥤", label: "Coke", bought: 2, cap: 4),
                    RecapLimitChip(emoji: "🍫", label: "Chocolate", bought: 5, cap: 3),
                ]),
                .focus(band: .primary, focus: .capCategory(category: "Restaurant & Dining", amount: 150),
                       isWeekly: false),
            ])
    }
}

#Preview("Recap · Monthly") {
    RecapStoryView(story: .debugMonthlySample(), onClose: {}, onSeeDetails: {})
}
#endif
