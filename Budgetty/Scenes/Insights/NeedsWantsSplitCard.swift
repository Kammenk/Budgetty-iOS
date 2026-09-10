//
//  NeedsWantsSplitCard.swift
//  Budgetty
//
//  The Insights Needs / Wants / Savings (50/30/20) split card, its closed-month trend, the one-time
//  "what counts as Savings?" inline ask, and the change-later settings group. iOS parity for Android's
//  `NeedsWantsSplitContent` / `BucketTrendContent`, matched to the Liquid Glass mockups
//  (`iOS NeedsWantsSplit.dc.html` / `iOS SavingsAllocationAsk.dc.html`): glass cards, the three shared
//  bucket accents, fixed 50/80 target ticks, delta pills on system semantic colours, and Savings on
//  top of every trend column against the dashed 20% line. All state is derived in `InsightsView`; this
//  file is pure presentation.
//

import SwiftUI

// MARK: - Split card (populated 50/30/20 view, or the setup state)

struct NeedsWantsSplitCard: View {
    let split: NeedsWantsSplit?
    /// The user's answer to the one-time ask (true = count everything kept as Savings).
    let onChoose: (Bool) -> Void
    @Environment(\.selectTab) private var selectTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let split {
                populated(split)
            } else {
                setup
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    // MARK: Populated

    @ViewBuilder
    private func populated(_ split: NeedsWantsSplit) -> some View {
        let unset = split.allocation == .unset
        VStack(alignment: .leading, spacing: 0) {
            header(split.income)
            BucketSplitBar(split: split).padding(.top, 18)
            Text(caption(split)).font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 7)

            // The one-time ask sits between the bar and the rows, until the user answers it.
            if unset {
                SavingsAllocationAsk(split: split, onChoose: onChoose).padding(.top, 14)
            }

            BucketRow(share: split.needs, showPill: !unset).padding(.top, 16)
            BucketRow(share: split.wants, showPill: !unset).padding(.top, 14)
            if unset {
                SavingsWaitingRow(split: split).padding(.top, 14)
            } else {
                BucketRow(share: split.savings).padding(.top, 14)
                if split.allocation == .setAside, split.leftover > 0 {
                    LeftoverRow(split: split).padding(.top, 14)
                }
            }

            // Summary + goal nudge + footer note only once the definition is chosen.
            if !unset {
                Divider().padding(.top, 16)
                Text(summary(split)).font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 12)
                SavingsGoalCta(allocation: split.allocation) { selectTab?(.budget) }.padding(.top, 12)
                Text(footer(split)).font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 12)
            }
        }
    }

    private func header(_ income: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Needs · Wants · Savings").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text("Share of \(income.formatMoney()) income").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
    }

    /// The caption under the bar, worded for whichever Savings definition is in force.
    private func caption(_ split: NeedsWantsSplit) -> String {
        switch split.allocation {
        case .unset: String(localized: "\(split.leftover.formatMoney()) of your income is not spent yet")
        case .countKept: String(localized: "Marks show the 50 / 30 / 20 targets")
        case .setAside: String(localized: "Grey is income you have not spent or set aside")
        }
    }

    /// One sentence under the divider: states the gap and one concrete move, never a scolding.
    private func summary(_ split: NeedsWantsSplit) -> String {
        if split.allocation == .countKept {
            return String(localized: "You kept \(split.savings.amount.formatMoney()) of your \(split.income.formatMoney()) income this month.")
        }
        switch split.tone {
        case .balanced:
            return String(localized: "Nicely balanced — all three within a point of the rule.")
        case .wantsOver:
            return String(localized: "Wants ran \(split.wants.deltaPoints) points over this month, and Savings took the difference.")
        case .needsOver:
            return String(localized: "Needs ran \(split.needs.deltaPoints) points over this month — often rent or utilities landing in one period.")
        case .underSaving:
            let gapPoints = split.savings.targetPercent - split.savings.percent
            let gapAmount = max(split.income * Decimal(split.savings.targetPercent) / 100 - split.savings.amount, 0)
            return String(localized: "Savings is \(gapPoints) points under 20% this month. Around \(gapAmount.formatMoney()) of Wants would close the gap.")
        }
    }

    private func footer(_ split: NeedsWantsSplit) -> LocalizedStringKey {
        split.allocation == .countKept
            ? "Counting everything you keep. Change in Customize sections."
            : "Counting money you set aside. Change in Customize sections."
    }

    // MARK: Setup (no income yet)

    private var setup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Needs · Wants · Savings").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text("The 50/30/20 rule, from your own categories")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 3)

            GeometryReader { geo in
                let gap: CGFloat = 4
                let avail = geo.size.width - gap * 2
                HStack(spacing: gap) {
                    setupTile(.need, 50, "Needs", leading: true, trailing: false).frame(width: avail * 0.5)
                    setupTile(.want, 30, "Wants", leading: false, trailing: false).frame(width: avail * 0.3)
                    setupTile(.savings, 20, "Saved", leading: false, trailing: true).frame(width: avail * 0.2)
                }
            }
            .frame(height: 64).padding(.top, 20)

            Text("See your 50/30/20 split").font(.headline).foregroundStyle(Palette.label).padding(.top, 20)
            Text("Add your income and Budgetty sorts your spending into Needs, Wants and Savings — your built-in categories come pre-tagged.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 6)

            Button { selectTab?(.budget) } label: {
                Text("Set up income").font(.body).fontWeight(.semibold).ctaPill(height: 50)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .accessibilityIdentifier(A11y.Insights.nwsSetupCTA)

            Text("Worked out on your device — nothing is sent anywhere.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 10)
        }
    }

    private func setupTile(_ bucket: CategoryBucket, _ value: Int, _ label: LocalizedStringKey,
                           leading: Bool, trailing: Bool) -> some View {
        let accent = Palette.bucketColor(bucket)
        return VStack(spacing: 2) {
            Text("\(value)").font(.title3).fontWeight(.bold).foregroundStyle(accent)
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Palette.bucketSoft(bucket),
            in: UnevenRoundedRectangle(
                topLeadingRadius: leading ? 14 : 4, bottomLeadingRadius: leading ? 14 : 4,
                bottomTrailingRadius: trailing ? 14 : 4, topTrailingRadius: trailing ? 14 : 4,
                style: .continuous)
        )
    }
}

// MARK: - Split bar (three shares + leftover, with fixed 50/80 target ticks)

/// The stacked bar carrying the three shares, with target ticks fixed at the cumulative 50% and 80%
/// marks (a segment ending past its tick reads as over target without a number). If the buckets
/// exceed income (overspend) they're scaled to fit; the row numbers still report true percentages.
private struct BucketSplitBar: View {
    let split: NeedsWantsSplit

    var body: some View {
        let raw = [split.needs.fraction, split.wants.fraction, split.savings.fraction]
        let sum = raw.reduce(0, +)
        let scale = sum > 1 ? 1 / sum : 1
        let n = raw[0] * scale, w = raw[1] * scale, s = raw[2] * scale
        let leftover = max(1 - n - w - s, 0)
        VStack(spacing: 3) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    tick.offset(x: width * 0.5 - 1)
                    tick.offset(x: width * 0.8 - 1)
                }
            }
            .frame(height: 8)
            GeometryReader { geo in
                let gap: CGFloat = 2
                let segs: [(Color, Double)] = [
                    (Palette.bucketNeeds, n), (Palette.bucketWants, w),
                    (Palette.bucketSavings, s), (Palette.bucketLeftover, leftover),
                ].filter { $0.1 > 0.001 }
                let avail = geo.size.width - gap * CGFloat(max(0, segs.count - 1))
                HStack(spacing: gap) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                        seg.0.frame(width: max(1, avail * CGFloat(seg.1)))
                    }
                }
            }
            .frame(height: 20)
            .clipShape(Capsule())
        }
    }

    private var tick: some View {
        RoundedRectangle(cornerRadius: 1).fill(Palette.tertiaryLabel).frame(width: 2, height: 8)
    }
}

// MARK: - Bucket rows

/// One bucket's legend row: colour swatch, name + "amount · target", the big percent, and a delta
/// pill (suppressed under the one-time ask, where no definition is chosen yet).
private struct BucketRow: View {
    let share: BucketShare
    var showPill: Bool = true

    var body: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.bucketColor(share.bucket)).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text(bucketLabel(share.bucket)).font(.body).foregroundStyle(Palette.label)
                Text("\(share.amount.formatMoney()) · target \(share.targetPercent)%")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text("\(share.percent)%").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            if showPill { BucketDeltaPill(share: share) }
        }
    }
}

private struct BucketDeltaPill: View {
    let share: BucketShare

    var body: some View {
        Text(text).font(.caption2).fontWeight(.semibold).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }

    private var text: String {
        switch share.status {
        case .onTarget: String(localized: "on target")
        case .overGood, .overWarn, .underWarn: signedPoints(share.deltaPoints)
        case .underNeutral: String(localized: "\(-share.deltaPoints) under")
        }
    }
    private var fg: Color {
        switch share.status {
        case .onTarget, .overGood: Palette.good
        case .overWarn, .underWarn: Palette.warn
        case .underNeutral: Palette.secondaryLabel
        }
    }
    private var bg: Color {
        switch share.status {
        case .onTarget, .overGood: Palette.good.opacity(0.16)
        case .overWarn, .underWarn: Palette.warn.opacity(0.14)
        case .underNeutral: Palette.fill
        }
    }
}

/// The Savings row before the user has chosen — no percent, no pill, a "waiting" sub-line.
private struct SavingsWaitingRow: View {
    let split: NeedsWantsSplit

    var body: some View {
        let kept = split.leftover + split.savings.amount
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.bucketSavings).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text("Savings").font(.body).foregroundStyle(Palette.label)
                Text("\(kept.formatMoney()) left · waiting on your answer")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text(verbatim: "—").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

/// The 4th "Left over" row (only under "only money I set aside"): income counted as no bucket.
private struct LeftoverRow: View {
    let split: NeedsWantsSplit

    var body: some View {
        let pct = NeedsWantsSplitMath.pctOf(split.leftover, split.income)
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.bucketLeftover).frame(width: 11, height: 11)
            VStack(alignment: .leading, spacing: 2) {
                Text("Left over").font(.body).foregroundStyle(Palette.secondaryLabel)
                Text("\(split.leftover.formatMoney()) · not counted as Savings")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text("\(pct)%").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

/// The "give it a goal" nudge under the chosen split; taps through to Budget, where goals live.
private struct SavingsGoalCta: View {
    let allocation: SavingsAllocation
    let onTap: () -> Void

    var body: some View {
        let keep = allocation == .countKept
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.bucketSavings)
                    .frame(width: 34, height: 34)
                    .background(Palette.bucketSavingsSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(keep ? "Give it a goal" : "Set a savings goal").font(.body).fontWeight(.semibold)
                        .foregroundStyle(Palette.label)
                    Text(keep ? "Name what you are keeping it for" : "A goal transfer counts toward Savings")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The one-time ask (inset group inside the split card)

/// Two choice cards, each with a live mini-bar of what it does to this month. iOS-native: an inset
/// `--fill` group with tappable option cards and a chevron, not the Material outlined container.
private struct SavingsAllocationAsk: View {
    let split: NeedsWantsSplit
    let onChoose: (Bool) -> Void

    var body: some View {
        let keptAmount = max(split.income - split.needs.amount - split.wants.amount, 0)
        let keptPct = NeedsWantsSplitMath.pctOf(keptAmount, split.income)
        VStack(alignment: .leading, spacing: 6) {
            Text("Does money you simply keep count as Savings?").font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Palette.label)
            Text("Pick the one that matches how you think. Changeable later.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            AllocationChoiceCard(
                title: "Count what I keep", percent: "\(keptPct)%", percentColor: Palette.bucketSavings,
                desc: "Anything left after Needs and Wants is money you saved.",
                needs: split.needs.fraction, wants: split.wants.fraction, tail: Palette.bucketSavings
            ) { onChoose(true) }
                .accessibilityIdentifier(A11y.Insights.nwsAskKeep)
            AllocationChoiceCard(
                title: "Only money I set aside", percent: "\(split.savings.percent)%", percentColor: Palette.secondaryLabel,
                desc: "Goal transfers and Savings categories only. The rest stays unspent.",
                needs: split.needs.fraction, wants: split.wants.fraction, tail: Palette.bucketLeftover
            ) { onChoose(false) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AllocationChoiceCard: View {
    let title: LocalizedStringKey
    let percent: String
    let percentColor: Color
    let desc: LocalizedStringKey
    let needs: Double
    let wants: Double
    let tail: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.body).fontWeight(.semibold).foregroundStyle(Palette.label)
                    Spacer(minLength: 8)
                    Text(percent).font(.subheadline).fontWeight(.semibold).foregroundStyle(percentColor)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.tertiaryLabel)
                }
                Text(desc).font(.caption).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.leading)
                miniBar.padding(.top, 5)
            }
            .padding(.horizontal, 11).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var miniBar: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let n = min(max(needs, 0), 1)
            let w = min(max(wants, 0), 1)
            let rest = max(1 - n - w, 0)
            let avail = geo.size.width - gap * 2
            HStack(spacing: gap) {
                Palette.bucketNeeds.frame(width: max(0, avail * CGFloat(n)))
                Palette.bucketWants.frame(width: max(0, avail * CGFloat(w)))
                tail.frame(width: max(1, avail * CGFloat(rest)))
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }
}

// MARK: - Trend card (closed-month split over time)

/// Savings on top of every column so its share grows against the dashed 20% line; closed months
/// only. `showMonthLabels` (iPad) adds a per-column savings %. iOS parity for `BucketTrendContent`.
struct BucketTrendCard: View {
    let months: [BucketMonth]
    var showMonthLabels = false

    private let chartHeight: CGFloat = 150

    var body: some View {
        let first = months.first?.savingsPercent ?? 0
        let last = months.last?.savingsPercent ?? 0
        let delta = last - first
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your split over time").font(.headline).foregroundStyle(Palette.label)
                    Text(months.count == 1 ? "\(months.count) closed month" : "\(months.count) closed months")
                        .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 8)
                let positive = delta >= 0
                Text("\(signedPoints(delta)) pts").font(.caption).fontWeight(.semibold)
                    .foregroundStyle(positive ? Palette.good : Palette.secondaryLabel)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(positive ? Palette.good.opacity(0.16) : Palette.fill, in: Capsule())
            }

            chart.padding(.top, 16)

            HStack(spacing: 7) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                    VStack(spacing: 2) {
                        if showMonthLabels {
                            Text("\(m.savingsPercent)%").font(.caption2).fontWeight(.bold)
                                .foregroundStyle(Palette.bucketSavings)
                        }
                        Text(m.axisLabel).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 12) {
                legendDot(.need); legendDot(.want); legendDot(.savings)
            }
            .padding(.top, 12)

            Divider().padding(.top, 12)
            Text("Your savings share went from \(first)% to \(last)% over the last \(months.count) months.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private var chart: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 7) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in column(m) }
            }
            // The dashed savings-target line sits 20% down from the top of the chart.
            GeometryReader { geo in
                Path { p in
                    let y = geo.size.height * 0.20
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(Palette.label.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
        }
        .frame(height: chartHeight)
    }

    /// One month's column: Savings caps the top (so it grows toward the 20% line), then Wants, Needs,
    /// and the unallocated remainder as the track. Weights normalise when the three exceed 100%.
    private func column(_ m: BucketMonth) -> some View {
        let total = CGFloat(max(100, m.needsPercent + m.wantsPercent + m.savingsPercent))
        return VStack(spacing: 0) {
            Palette.bucketSavings.frame(height: chartHeight * CGFloat(m.savingsPercent) / total)
            Palette.bucketWants.frame(height: chartHeight * CGFloat(m.wantsPercent) / total)
            Palette.bucketNeeds.frame(height: chartHeight * CGFloat(m.needsPercent) / total)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.tertiaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func legendDot(_ bucket: CategoryBucket) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(Palette.bucketColor(bucket)).frame(width: 9, height: 9)
            Text(bucketLabel(bucket)).font(.caption2).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

// MARK: - "How Savings is counted" settings group (the change-later counterpart to the ask)

/// A grouped-list section for the Insights Customize sheet — a tinted checkmark on the current choice
/// and a footer, the iOS idiom for a setting with two named states (never a switch). iOS parity for
/// Android's `SavingsAllocationCustomize`.
struct SavingsAllocationSettingsSection: View {
    @AppStorage(SettingsKey.nwsSavingsAllocation) private var allocRaw = 0

    var body: some View {
        Section {
            row(title: "Count what I keep", desc: "Income minus Needs and Wants counts as saved.",
                selected: allocRaw == 1) { allocRaw = 1 }
            row(title: "Only money I set aside", desc: "Goal transfers and Savings categories only.",
                selected: allocRaw != 1) { allocRaw = 2 }
        } header: {
            Text("How Savings is counted")
        } footer: {
            Text("Applies to past months too, so your trend stays consistent.")
        }
    }

    private func row(title: LocalizedStringKey, desc: LocalizedStringKey, selected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(Palette.label)
                    Text(desc).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared helpers

/// A signed whole-point label using a true minus sign, e.g. "+10" / "−5".
private func signedPoints(_ points: Int) -> String { points >= 0 ? "+\(points)" : "−\(-points)" }

private func bucketLabel(_ bucket: CategoryBucket) -> LocalizedStringKey {
    switch bucket {
    case .need: "Needs"
    case .want: "Wants"
    case .savings: "Savings"
    }
}
