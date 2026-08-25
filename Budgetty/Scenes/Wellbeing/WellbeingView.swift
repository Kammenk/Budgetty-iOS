//
//  WellbeingView.swift
//  Budgetty
//
//  The Wellbeing screen (Android's WellbeingScreen) — a dedicated full-screen destination pushed from
//  the Home banner and the Insights row. Weekly | Monthly toggle: Monthly shows the 0–100 score ring,
//  a trend chip, the five components it's built from (tap to expand a why-line + link), the tips feed,
//  a wins strip and a focus card; Weekly shows a pace card, a small "updates monthly" score row and the
//  weekly tips. First-run (no score yet) shows a dotted-style ring, a setup checklist and two CTAs.
//  Everything derives on-device from `WellbeingScan.run`; nothing leaves the phone.
//

import SwiftUI
import SwiftData

/// The screen's Weekly | Monthly toggle.
enum WellbeingMode: String, Identifiable, CaseIterable {
    case weekly, monthly
    var id: String { rawValue }
    var title: LocalizedStringKey { self == .weekly ? "Weekly" : "Monthly" }
}

/// Tip dismissals, persisted as a newline-separated `@AppStorage` string of `"periodId|tipId"` entries
/// (mirrors `InsightsLayoutStore`). Scoping to the pay-cycle month means a tip resurfaces next month.
enum WellbeingTipsStore {
    static func entry(period: String, tip: String) -> String { "\(period)|\(tip)" }
    static func set(_ raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
    static func csv(_ set: Set<String>) -> String { set.sorted().joined(separator: "\n") }
}

// MARK: - Shared band / tier styling (used by the banner + Insights row too)

func wbBandColor(_ band: WellbeingBand?) -> Color {
    switch band {
    case .needsWork: Palette.bad
    case .gettingThere: Palette.warn
    case .healthy, .thriving: Palette.good
    case nil: Palette.secondaryLabel
    }
}

/// Soft, band-tinted chip fill (the Insights score chip / wins pills).
func wbBandFill(_ band: WellbeingBand?) -> Color {
    switch band {
    case .needsWork: Palette.bad.opacity(0.15)
    case .gettingThere: Palette.warn.opacity(0.15)
    case .healthy, .thriving: Palette.good.opacity(0.15)
    case nil: Palette.fill
    }
}

func wbBandWord(_ band: WellbeingBand?) -> LocalizedStringKey {
    switch band {
    case .needsWork: "Needs work"
    case .gettingThere: "Getting there"
    case .healthy: "Healthy"
    case .thriving: "Thriving"
    case nil: "Not scored yet"
    }
}

func wbTierColor(_ score: Int) -> Color {
    switch WellbeingEngine.tier(score) {
    case .good: Palette.good
    case .warn: Palette.warn
    case .bad: Palette.bad
    }
}

// MARK: - Screen

struct WellbeingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.selectTab) private var selectTab
    @Environment(\.modelContext) private var context

    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @Query private var ignoredRows: [IgnoredSubscription]

    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.dismissedWellbeingTips) private var dismissedRaw = ""

    @State private var mode: WellbeingMode = .monthly
    @State private var open: WellbeingComponentKey?

    private var summary: WellbeingSummary {
        WellbeingScan.run(receipts: receipts, budgets: budgets, recurring: recurring, goals: goals,
                          contributions: contributions, ignoredSubs: Set(ignoredRows.map(\.merchant)),
                          monthStartDay: monthStartDay)
    }

    var body: some View {
        let summary = self.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content(summary)
            }
            .padding(.horizontal, Dimens.screenPadding)
            .padding(.top, 6).padding(.bottom, 24)
            .adaptiveReadableWidth(Dimens.contentMaxWidth)
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        // §3.1: snapshot the just-closed month into history when this screen appears (and if the closed
        // cycle rolls over while open). Closed-month-only, idempotent, no backfill — see WellbeingScoreStore.
        .task(id: summary.closedPeriodId) {
            WellbeingScoreStore.record(closedScore: summary.closedScore,
                                       closedPeriodId: summary.closedPeriodId, into: context)
        }
        .navigationTitle("Wellbeing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if summary.hasScore {
                    Text(mode == .weekly ? summary.weekLabel : summary.monthLabel)
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ summary: WellbeingSummary) -> some View {
        let firstRun = !summary.hasScore
        if firstRun {
            firstRunCard(summary)
            tipsFeed(visible(summary.monthlyTips, summary), weekly: false, summary: summary)
        } else {
            GlassSegmentedControl(options: WellbeingMode.allCases, selection: $mode) { $0.title }
            if mode == .monthly {
                scoreCard(summary)
                tipsFeed(visible(summary.monthlyTips, summary), weekly: false, summary: summary)
                if !summary.wins.isEmpty { winsStrip(summary.wins) }
                focusCard(summary)
            } else {
                weeklyPaceCard(summary.weekly)
                secondaryScoreRow(summary)
                tipsFeed(visible(summary.weeklyTips, summary), weekly: true, summary: summary)
            }
        }
        Text("Worked out on this phone from your own receipts and budgets. Nothing leaves the device.")
            .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            .padding(.horizontal, 4).padding(.vertical, 6)
    }

    // MARK: - Score card (monthly)

    private func scoreCard(_ summary: WellbeingSummary) -> some View {
        VStack(spacing: 16) {
            scoreRingHero(summary)
            Divider().overlay(Palette.separator)
            componentsSection(summary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .contentCard(cornerRadius: 24)
    }

    private func scoreRingHero(_ summary: WellbeingSummary) -> some View {
        let score = summary.score.score ?? 0
        return VStack(spacing: 12) {
            SavingsRing(fraction: Double(score) / 100, color: wbBandColor(summary.score.band), lineWidth: 11) {
                VStack(spacing: 2) {
                    Text("\(score)").font(.system(size: 42, weight: .heavy)).foregroundStyle(Palette.label)
                    Text(wbBandWord(summary.score.band))
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(wbBandColor(summary.score.band))
                    Text("out of 100").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .frame(width: 132, height: 132)
            if let delta = summary.score.trendDeltaVsPrevious { trendChip(delta) }
        }
        .frame(maxWidth: .infinity)
    }

    private func trendChip(_ delta: Int) -> some View {
        let up = delta >= 0
        return HStack(spacing: 5) {
            Text(verbatim: (up ? "▲ " : "▼ ") + "\(abs(delta))")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(up ? Palette.good : Palette.secondaryLabel)
            Text("vs last month").font(.caption2).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Palette.fill, in: Capsule())
    }

    private func componentsSection(_ summary: WellbeingSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WHAT IT'S BUILT FROM")
                .font(.caption2).fontWeight(.bold).kerning(0.5)
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.bottom, 4)
            ForEach(summary.score.components, id: \.key) { comp in
                componentRow(comp, summary: summary)
            }
            if summary.score.hasExcludedComponent {
                Text("A component with no data yet isn't counted — your score is weighted across the rest.")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func componentRow(_ comp: WellbeingComponent, summary: WellbeingSummary) -> some View {
        let excluded = comp.score == nil
        let color = excluded ? Palette.secondaryLabel : wbTierColor(comp.score ?? 0)
        let isOpen = open == comp.key
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if !excluded { withAnimation(.easeInOut(duration: 0.16)) { open = isOpen ? nil : comp.key } }
            } label: {
                HStack {
                    Text(componentName(comp.key))
                        .font(.subheadline)
                        .foregroundStyle(excluded ? Palette.secondaryLabel : Palette.label)
                    Spacer()
                    (excluded ? Text("Not counted") : Text("\(comp.score ?? 0)"))
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(color)
                    if !excluded {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(excluded)

            ProgressBarView(fraction: Double(comp.score ?? 0) / 100, color: color, height: 5, track: Palette.fill)

            if isOpen && !excluded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(componentWhy(comp.key, summary.detail[comp.key]))
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    Button { go(componentLink(comp.key)) } label: {
                        HStack(spacing: 4) {
                            Text(componentLinkLabel(comp.key)).font(.caption).fontWeight(.bold)
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Weekly

    private func weeklyPaceCard(_ weekly: WeeklyPace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("This week").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                Spacer()
                if let d = weekly.deltaPercentVsLastWeek {
                    let down = d <= 0
                    HStack(spacing: 3) {
                        Text(verbatim: (down ? "↓" : "↑") + " \(abs(d))%")
                        Text("vs last week")
                    }
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(down ? Palette.good : Palette.secondaryLabel)
                }
            }
            Text(weekly.spent.formatMoney())
                .font(.system(size: 30, weight: .heavy)).foregroundStyle(Palette.label)
                .padding(.top, 4)
            if let wb = weekly.weeklyBudget {
                Text("of your \(wb.formatMoney()) weekly budget")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
                ProgressBarView(fraction: weekly.fractionUsed,
                                color: weekly.onTrack ? Palette.good : Palette.warn, height: 8)
                    .padding(.top, 12)
                Text("\(weekly.remaining.formatMoney()) left · \(weekly.daysLeft) days to go")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .contentCard(cornerRadius: 24)
    }

    private func secondaryScoreRow(_ summary: WellbeingSummary) -> some View {
        HStack(spacing: 12) {
            SavingsRing(fraction: Double(summary.score.score ?? 0) / 100,
                        color: wbBandColor(summary.score.band), lineWidth: 5) {
                Text("\(summary.score.score ?? 0)").font(.subheadline).fontWeight(.heavy)
                    .foregroundStyle(Palette.label)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 1) {
                Text(wbBandWord(summary.score.band))
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(wbBandColor(summary.score.band))
                Text("Wellbeing score · updates monthly")
                    .font(.caption2).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 20)
    }

    // MARK: - First run

    private func firstRunCard(_ summary: WellbeingSummary) -> some View {
        VStack(spacing: 16) {
            SavingsRing(fraction: 0.22, color: Palette.tertiaryLabel, lineWidth: 8) {
                VStack(spacing: 2) {
                    Text(verbatim: "—").font(.system(size: 34, weight: .heavy)).foregroundStyle(Palette.secondaryLabel)
                    Text("Not scored yet").font(.caption2).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .frame(width: 140, height: 140)

            Text("Log a couple of weeks of spending and set a budget to unlock your Wellbeing score.")
                .font(.subheadline).foregroundStyle(Palette.label).multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 4) {
                setupStep(done: summary.receiptsLogged > 0, Text("\(summary.receiptsLogged) receipts logged"))
                setupStep(done: summary.hasBudget, Text("Set your first budget"))
                setupStep(done: summary.receiptsLogged >= WellbeingEngine.minReceiptsToScore,
                          Text("A month of history"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                firstRunButton("Set a budget") { go(.budget) }
                firstRunButton("Add a receipt") { go(.home) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .contentCard(cornerRadius: 24)
    }

    private func setupStep(done: Bool, _ text: Text) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 16)).foregroundStyle(done ? Palette.good : Palette.tertiaryLabel)
            text.font(.caption).foregroundStyle(done ? Palette.label : Palette.secondaryLabel)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func firstRunButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Palette.tintSoft, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tips feed

    @ViewBuilder
    private func tipsFeed(_ tips: [WellbeingTip], weekly: Bool, summary: WellbeingSummary) -> some View {
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    Text(weekly ? "Focus this week" : "Focus this month").font(.headline)
                    Spacer()
                    Text("\(tips.count) tips").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                }
                .padding(.top, 4)
                ForEach(tips) { tip in tipCard(tip, summary: summary) }
            }
        }
    }

    private func tipCard(_ tip: WellbeingTip, summary: WellbeingSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(toneColor(tip.tone).opacity(0.15))
                    Image(systemName: toneIcon(tip.tone)).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(toneColor(tip.tone))
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    tipTitle(tip).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                    if let detail = tipDetail(tip) {
                        detail.font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                Spacer(minLength: 4)
                Button { dismissTip(tip, summary: summary) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 8) {
                // §0 analytics: the tip's CTA was acted on (Android parity: onTipActed before nav).
                Button { Analytics.logTipActed(tip.type); go(tipCta(tip.type)) } label: {
                    Text(tipCtaLabel(tip.type)).font(.caption).fontWeight(.bold).foregroundStyle(Palette.tint)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Palette.tintSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                Button { dismissTip(tip, summary: summary) } label: {
                    Text("Got it").font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 48)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    // MARK: - Wins + focus

    private func winsStrip(_ wins: [WellbeingWin]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wins this month").font(.headline).padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(wins.enumerated()), id: \.offset) { _, win in
                        HStack(spacing: 6) {
                            Text(win.emoji).font(.subheadline)
                            winLabel(win).font(.caption).fontWeight(.semibold).foregroundStyle(Palette.good)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Palette.good.opacity(0.15), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func focusCard(_ summary: WellbeingSummary) -> some View {
        if let lowest = summary.score.components.filter({ $0.score != nil })
            .min(by: { ($0.score ?? 0) < ($1.score ?? 0) }) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill").font(.system(size: 17)).foregroundStyle(Palette.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("FOCUS FOR NEXT MONTH")
                        .font(.caption2).fontWeight(.bold).kerning(0.5).foregroundStyle(Palette.secondaryLabel)
                    Text(focusMessage(lowest.key)).font(.subheadline).foregroundStyle(Palette.label)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Actions

    /// Pop back to the tab root, then switch tabs — so a link from this pushed screen actually lands
    /// on the target tab (the Wellbeing screen would otherwise stay on top of it).
    private func go(_ tab: AppTab) {
        dismiss()
        selectTab?(tab)
    }

    private func visible(_ tips: [WellbeingTip], _ summary: WellbeingSummary) -> [WellbeingTip] {
        let dismissed = WellbeingTipsStore.set(dismissedRaw)
        return tips.filter { !dismissed.contains(WellbeingTipsStore.entry(period: summary.periodId, tip: $0.id)) }
    }

    private func dismissTip(_ tip: WellbeingTip, summary: WellbeingSummary) {
        var set = WellbeingTipsStore.set(dismissedRaw)
        set.insert(WellbeingTipsStore.entry(period: summary.periodId, tip: tip.id))
        dismissedRaw = WellbeingTipsStore.csv(set)
    }

    // MARK: - Localised copy

    private func componentName(_ key: WellbeingComponentKey) -> LocalizedStringKey {
        switch key {
        case .savings: "Savings rate"
        case .budget: "Budget adherence"
        case .trend: "Spending trend"
        case .subscriptions: "Subscriptions"
        case .goals: "Goals"
        }
    }

    private func componentWhy(_ key: WellbeingComponentKey, _ d: ComponentDetail?) -> String {
        switch key {
        case .savings:
            return String(localized: "You kept \(d?.savingsRatePercent ?? 0)% of your income — \((d?.saved ?? .zero).formatMoney()) of \((d?.income ?? .zero).formatMoney()). Above 20% scores full marks.")
        case .budget:
            if (d?.overCount ?? 0) == 0 {
                return String(localized: "All \(d?.budgetedCount ?? 0) budgets within plan.")
            }
            return String(localized: "\(d?.overCount ?? 0) of \(d?.budgetedCount ?? 0) budgets over, \((d?.overspend ?? .zero).formatMoney()) above plan. Every category within budget scores full marks.")
        case .trend:
            guard let pct = d?.trendPercent else {
                return String(localized: "Not enough history yet to judge your trend.")
            }
            let avg = (d?.avgSpend ?? .zero).formatMoney()
            return pct >= 0
                ? String(localized: "Spending is \(abs(pct))% above your average of \(avg). Flat or falling scores full marks.")
                : String(localized: "Spending is \(abs(pct))% below your average of \(avg). Flat or falling scores full marks.")
        case .subscriptions:
            return String(localized: "\((d?.subsMonthly ?? .zero).formatMoney()) a month on subscriptions — \(d?.subsSharePercent ?? 0)% of what you spend. Under 5% scores full marks.")
        case .goals:
            return String(localized: "\(d?.goalsOnPace ?? 0) of \(d?.goalsTotal ?? 0) goals on pace.")
        }
    }

    private func componentLinkLabel(_ key: WellbeingComponentKey) -> LocalizedStringKey {
        switch key {
        case .savings: "See savings rate"
        case .budget: "View budgets"
        case .trend: "See trend"
        case .subscriptions: "Review subscriptions"
        case .goals: "View goals"
        }
    }

    private func componentLink(_ key: WellbeingComponentKey) -> AppTab {
        switch key {
        case .savings, .trend, .subscriptions: .insights
        case .budget, .goals: .budget
        }
    }

    private func focusMessage(_ key: WellbeingComponentKey) -> LocalizedStringKey {
        switch key {
        case .savings: "Set a little more aside next month to lift your score."
        case .budget: "Bring your over-budget categories back in line to lift your score."
        case .trend: "Ease spending back toward your average to lift your score."
        case .subscriptions: "Trim a subscription you don't use to lift your score."
        case .goals: "Nudge your goals back on pace to lift your score."
        }
    }

    private func toneColor(_ tone: TipTone) -> Color {
        switch tone {
        case .alert: Palette.bad
        case .caution: Palette.warn
        case .opportunity: Palette.tint
        case .win: Palette.good
        }
    }

    private func toneIcon(_ tone: TipTone) -> String {
        switch tone {
        case .alert: "exclamationmark.triangle.fill"
        case .caution: "info.circle.fill"
        case .opportunity: "plus"
        case .win: "checkmark"
        }
    }

    private func tipTitle(_ tip: WellbeingTip) -> Text {
        let amt = (tip.amount ?? .zero).formatMoney()
        let amt2 = (tip.amount2 ?? .zero).formatMoney()
        let label = tip.label ?? ""
        switch tip.type {
        case .negativeCashflow: return Text("You spent \(amt) more than you earned this month")
        case .overBudget: return Text("Over budget in \(tip.count ?? 0) categories — \(amt) above plan")
        case .categorySpike: return Text("\(label) is up \(tip.percent ?? 0)% — \(amt) vs your \(amt2) average")
        case .subscriptionCost: return Text("\(tip.count ?? 0) subscriptions — \(amt) a month")
        case .missingBudget: return Text("You spend about \(amt) a month on \(label) but have no budget")
        case .noGoal: return Text("No savings goal yet — even a little a month builds a buffer")
        case .goalOffTrack: return Text("\(label) is running behind")
        case .savingsWin: return Text("Nice — you saved \(tip.percent ?? 0)% of your income this month")
        case .categoryImproved: return Text("\(label) is down \(tip.percent ?? 0)% this month")
        case .budgetPace: return Text("You're at \(tip.percent ?? 0)% of your weekly budget")
        case .smallPurchaseLeak: return Text("\(tip.count ?? 0) small buys in \(label) this week")
        case .underPaceWin: return Text("You're under pace this week")
        }
    }

    private func tipDetail(_ tip: WellbeingTip) -> Text? {
        let amt = (tip.amount ?? .zero).formatMoney()
        switch tip.type {
        case .savingsWin: return Text("\(amt) put aside this month.")
        case .subscriptionCost: return tip.percent.map { Text("\($0)% of what you spend goes to subscriptions.") }
        case .budgetPace: return Text("\(amt) left for the rest of the week.")
        case .smallPurchaseLeak: return Text("\(amt) in total — small, but it adds up.")
        case .missingBudget: return Text("A budget makes this one scoreable.")
        case .noGoal: return Text("Even a small monthly amount gives your spare cash a job.")
        default: return nil
        }
    }

    private func tipCtaLabel(_ type: TipType) -> LocalizedStringKey {
        switch type {
        case .negativeCashflow: "See where it went"
        case .overBudget: "View budgets"
        case .categorySpike: "Set a budget"
        case .subscriptionCost: "Review subscriptions"
        case .missingBudget: "Set a budget"
        case .noGoal, .goalOffTrack: "Create a goal"
        case .savingsWin: "See savings rate"
        case .categoryImproved: "See trend"
        case .budgetPace, .underPaceWin: "View budgets"
        case .smallPurchaseLeak: "See transactions"
        }
    }

    private func tipCta(_ type: TipType) -> AppTab {
        switch type {
        case .negativeCashflow, .smallPurchaseLeak: .history
        case .overBudget, .categorySpike, .missingBudget, .budgetPace, .underPaceWin: .budget
        case .subscriptionCost: .insights
        case .noGoal, .goalOffTrack: .budget
        case .savingsWin, .categoryImproved: .insights
        }
    }

    private func winLabel(_ win: WellbeingWin) -> Text {
        switch win.type {
        case .savingsWin: return Text("Saved \(win.percent ?? 0)% of income")
        case .categoryImproved: return Text("\(win.label ?? "") down \(win.percent ?? 0)%")
        case .underPaceWin: return Text("Under pace this week")
        default: return Text("Nice work")
        }
    }
}

// MARK: - Insights entry row

/// The slim one-line Insights entry into the Wellbeing screen (Android's WellbeingInsightsRow): a
/// band-tinted score chip, "Wellbeing score", the band word, a chevron. Falls to a muted "Set up"
/// chip before there's a score. Rendered directly under the Insights period stepper.
struct WellbeingEntryRow: View {
    let summary: WellbeingSummary

    var body: some View {
        let firstRun = !summary.hasScore
        let band = summary.score.band
        HStack(spacing: 11) {
            (firstRun ? Text(verbatim: "—") : Text("\(summary.score.score ?? 0)"))
                .font(.subheadline).fontWeight(.heavy)
                .foregroundStyle(firstRun ? Palette.secondaryLabel : wbBandColor(band))
                .frame(minWidth: 32).frame(height: 24)
                .padding(.horizontal, 8)
                .background(firstRun ? Palette.fill : wbBandFill(band), in: Capsule())
            Text("Wellbeing score").font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
            Spacer(minLength: 8)
            (firstRun ? Text("Set up") : Text(wbBandWord(band)))
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(firstRun ? Palette.tint : wbBandColor(band))
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 20)
    }
}
