//
//  InsightsHybrid.swift
//  Budgetty
//
//  The "Hybrid" Insights model (Android parity, feat/insights-tab-grouping): the screen is a short set
//  of focused tabs — Overview · Spending · Money · Trends · Custom — with Wellbeing + recap promoted to
//  the toolbar and a user-curated Custom tab. This file holds the tab model and the leaf views that the
//  state-owning `InsightsView` composes: the toolbar score pip + recap button, the scrollable pill tab
//  bar, the Overview setup checklist + quick-toggle chips, per-tab invitations, and the Custom section
//  picker. All data is passed in (no ViewModel — the app's pattern); this file is pure presentation.
//
//  Matches the mockups `iOS InsightsHybrid.dc.html` / `iOS InsightsHybridStates.dc.html` (Liquid Glass),
//  with the two locked tweaks applied to both platforms: the period control is one full-width pill with
//  its step arrows inside (see `InsightsView.stepper`), and the recap button is a circular tonal button
//  with a play glyph + unread dot.
//

import SwiftUI

// MARK: - Tab model

/// Phone grouping of the Insights sections into five tabs, so the screen reads as focused pages instead
/// of one long scroll. OVERVIEW is a bespoke summary (the default landing); SPENDING/MONEY/TRENDS hold
/// the existing section cards; CUSTOM is the one user-curated tab. Android parity: `InsightsTab`.
enum InsightsTab: String, CaseIterable, Identifiable {
    case overview, spending, money, trends, custom
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .spending: "Spending"
        case .money: "Money"
        case .trends: "Trends"
        case .custom: "Custom"
        }
    }
}

extension InsightSection {
    /// Which tab a section lives in. `stats` (Summary) is folded into the Overview hero, so its
    /// standalone card isn't rendered in any fixed tab, but it stays offerable in Custom. Android
    /// parity: `InsightsSection.tab()`.
    var tab: InsightsTab {
        switch self {
        case .stats: .overview
        case .breakdown, .topCategories, .topStores, .biggestPurchases, .subscriptions: .spending
        case .income, .needsWantsSavings: .money
        case .trend, .comparison, .highlights: .trends
        }
    }
}

/// Sections offerable in the Custom picker — every section (iOS has no toolbar-only Wellbeing section).
/// Order here is the picker's stable listing order for non-members. Android parity: `customizableSections`.
let customizableSections: [InsightSection] = InsightSection.allCases

/// CSV <-> [InsightSection] for the Custom tab's membership, stored in @AppStorage. Absent (the seed) is
/// distinguished from an explicitly-cleared empty string by defaulting the @AppStorage to `seedCSV`.
/// Android parity: `SettingsStore.customInsightsSections` (seed `breakdown,top_categories`).
enum InsightsCustomStore {
    /// The default Custom membership before the user curates it — a small, useful starting pair.
    static let seed: [InsightSection] = [.breakdown, .topCategories]
    static let seedCSV = csv(seed)

    static func parse(_ raw: String) -> [InsightSection] {
        raw.split(separator: ",").compactMap { InsightSection(rawValue: String($0)) }
    }
    static func csv(_ sections: [InsightSection]) -> String { sections.map(\.rawValue).joined(separator: ",") }
}

/// One row of the Overview "things to set up" checklist. Each names a piece of one-time setup that
/// unlocks more of Insights, links to where it's done, and can be dismissed. Shown only while its setup
/// is genuinely incomplete (see `InsightsView.activeSetupItems`). Android parity: `InsightsSetupItem`.
enum InsightsSetupItem: String, CaseIterable, Identifiable {
    case savings, income, overlay, buckets
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .savings: "Choose what counts as savings"
        case .income: "Add income or a budget"
        case .overlay: "Try the planned-bills overlay"
        case .buckets: "Tag categories as needs / wants"
        }
    }
    var cta: LocalizedStringKey {
        switch self {
        case .savings: "Choose"
        case .income: "Add"
        case .overlay: "Turn on"
        case .buckets: "Tag"
        }
    }
}

// MARK: - Toolbar controls

/// The Wellbeing score's door in the toolbar: a hollow ring matching the Home wellbeing card (arc =
/// score; green ≥ 70, amber 40–69, red below) with the score in the middle. Shown only once there's a
/// score (the caller gates on a non-nil score). Android parity: `WellbeingScorePip`.
struct WellbeingScorePip: View {
    let score: Int

    private var band: Color {
        switch score {
        case 70...: Palette.good
        case 40...: Palette.warn
        default: Palette.bad
        }
    }

    var body: some View {
        SavingsRing(fraction: Double(score) / 100, color: band, lineWidth: 3.4) {
            Text("\(score)")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(band)
        }
        .frame(width: 32, height: 32)
        .accessibilityLabel("Wellbeing score \(score)")
    }
}

/// The re-open-last-recap door in the toolbar: a circular tonal button with a play glyph and an amber
/// "unread" dot. Shown only once a recap has been generated for a closed period. Android parity:
/// `RecapToolbarButton` (the locked "circular bg + play + dot" tweak).
struct RecapToolbarButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tint)
                .frame(width: 34, height: 34)
                .background(Palette.fill, in: Circle())
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(Palette.warn)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Palette.groupedBackground, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open your last recap")
    }
}

// MARK: - Scrollable pill tab bar

/// The Insights tab strip as a horizontally scrollable pill row (D9): all five groups stay reachable at
/// 390pt, 375pt and large Dynamic Type — the pills grow with the type and scroll rather than truncating,
/// so nothing hides behind an overflow menu. The selected pill takes the tint with a soft shadow; a fade
/// at the trailing edge shows more groups exist; tapping scrolls the selection into view.
struct InsightsTabBar: View {
    @Binding var selection: InsightsTab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(InsightsTab.allCases) { tab in
                        pill(tab).id(tab)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(
                    colors: [Palette.groupedBackground.opacity(0), Palette.groupedBackground],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 24)
                .allowsHitTesting(false)
            }
            .onChange(of: selection) { _, tab in
                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(tab, anchor: .center) }
            }
        }
    }

    private func pill(_ tab: InsightsTab) -> some View {
        let selected = tab == selection
        return Text(tab.title)
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : Palette.secondaryLabel)
            .lineLimit(1)
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
            .background {
                if selected {
                    Capsule().fill(Palette.tint).shadow(color: Palette.tint.opacity(0.34), radius: 8, y: 2)
                } else {
                    Capsule().fill(Palette.fill)
                }
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.snappy(duration: 0.25)) { selection = tab } }
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

// MARK: - Overview building blocks

/// The compact 50/30/20 mini split bar shown in the Overview hero (Needs · Wants · Savings, scaled to
/// fit if the three exceed income), with a labelled row beneath. Android parity: `BucketSplitBar` +
/// `CompactBucketLabel`, condensed for the hero.
struct MiniSplitBar: View {
    let split: NeedsWantsSplit

    var body: some View {
        let raw = [split.needs.fraction, split.wants.fraction, split.savings.fraction]
        let sum = raw.reduce(0, +)
        let scale = sum > 1 ? 1 / sum : 1
        let segs: [(Color, Double)] = [
            (Palette.bucketNeeds, raw[0] * scale),
            (Palette.bucketWants, raw[1] * scale),
            (Palette.bucketSavings, raw[2] * scale),
        ].filter { $0.1 > 0.001 }
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 4
                let avail = geo.size.width - gap * CGFloat(max(0, segs.count - 1))
                HStack(spacing: gap) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                        seg.0.frame(width: max(1, avail * CGFloat(seg.1)))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                miniLabel(.need, split.needs.percent)
                miniLabel(.want, split.wants.percent)
                miniLabel(.savings, split.savings.percent)
            }
        }
    }

    private func miniLabel(_ bucket: CategoryBucket, _ percent: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Palette.bucketColor(bucket)).frame(width: 7, height: 7)
            Text("\(bucketName(bucket)) \(percent)%")
                .font(.system(size: 11)).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

/// "Needs" / "Wants" / "Savings" — the display name for a bucket (matches the split card's labels).
func bucketName(_ bucket: CategoryBucket) -> String {
    switch bucket {
    case .need: String(localized: "Needs")
    case .want: String(localized: "Wants")
    case .savings: String(localized: "Savings")
    }
}

/// A card header with a title and a "<tab> ›" deep-link into the tab that holds the full detail. Android
/// parity: `OverviewLinkHeader`.
struct OverviewLinkHeader: View {
    let title: LocalizedStringKey
    let linkTab: InsightsTab
    let onGoToTab: (InsightsTab) -> Void

    var body: some View {
        HStack {
            Text(title).font(.headline).foregroundStyle(Palette.label)
            Spacer(minLength: 8)
            Button { onGoToTab(linkTab) } label: {
                HStack(spacing: 2) {
                    Text(linkTab.title)
                    Text(verbatim: "›")
                }
                .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The Overview "things to set up" card: a tonal container that starts as a one-line summary and expands
/// to a short, per-row-dismissible checklist. Renders nothing when `items` is empty, so the card is
/// simply absent once there's nothing to set up. Android parity: `OverviewSetupChecklist`.
struct OverviewSetupChecklist: View {
    let items: [InsightsSetupItem]
    let onAction: (InsightsSetupItem) -> Void
    let onDismiss: (InsightsSetupItem) -> Void
    @State private var expanded = false

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("\(items.count) things to set up")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                    Spacer(minLength: 8)
                    Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                        Text(expanded ? "Hide" : "Review")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                    dismissButton { items.forEach(onDismiss) }
                }
                if expanded {
                    ForEach(items) { item in
                        Divider().overlay(Palette.tint.opacity(0.18)).padding(.vertical, 2)
                        HStack(spacing: 10) {
                            Text(item.label)
                                .font(.subheadline).foregroundStyle(Palette.label)
                            Spacer(minLength: 8)
                            Button { onAction(item) } label: {
                                Text(item.cta).font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                            }
                            .buttonStyle(.plain)
                            dismissButton { onDismiss(item) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func dismissButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondaryLabel)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

/// One compact pill toggle-chip (planned-layers / savings mode): a mini track+knob and a label, the whole
/// chip toggling `checked`. Android parity: `OverviewToggleChip`.
struct OverviewToggleChip: View {
    let checked: Bool
    let label: String
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                ZStack(alignment: checked ? .trailing : .leading) {
                    Capsule().fill(checked ? Palette.tint : Palette.tertiaryLabel)
                        .frame(width: 26, height: 15)
                    Circle().fill(Color.white).frame(width: 11, height: 11).padding(.horizontal, 2)
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(checked ? Palette.label : Palette.secondaryLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Per-tab invitations & empties (P8)

/// A friendly per-tab invitation card: an icon, a title, one line, and a verb-first CTA — shown in place
/// of an otherwise-blank pane so a group with nothing to show reads as an intentional next step rather
/// than an empty screen. Android parity: `TabInvitationCard`.
struct TabInvitationCard: View {
    let title: LocalizedStringKey
    let body_: LocalizedStringKey
    let cta: LocalizedStringKey
    let systemImage: String
    let onCta: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Palette.tint)
                .frame(width: 56, height: 56)
                .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(title).font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text(body_)
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
            Button(action: onCta) {
                Text(cta).font(.body).fontWeight(.semibold).ctaPill(height: 48)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20).padding(.horizontal, 18)
        .contentCard(cornerRadius: 16)
    }
}

/// A period-aware empty state for Spending / Trends and the Breakdown card: distinguishes a first-run
/// account (no receipts ever) from stepping into an empty period. Android parity: `PeriodEmptyState`.
struct PeriodEmptyState: View {
    let periodLabel: String
    let hasAnyData: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: hasAnyData ? "calendar" : "chart.pie")
                .font(.system(size: 32)).foregroundStyle(Palette.tertiaryLabel)
            Text(hasAnyData ? "No spending in \(periodLabel)" : "Nothing to show yet")
                .font(.headline).foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Text(hasAnyData ? "Step to another period to see your spending." : "Scan a receipt to see your spending here.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 18)
        .contentCard(cornerRadius: 16)
    }
}

// MARK: - Custom section picker

/// The Custom section picker (a sheet — SwiftUI renders it as a centered form on iPad): toggles sections
/// in or out of the Custom tab and reorders the chosen ones with up/down arrows (no drag library, matching
/// the old Customize sheet). Chosen sections list first, in the user's order; the rest follow. Android
/// parity: `CustomSectionsSheet`.
struct CustomSectionsSheet: View {
    /// The current membership, in order (the picker mutates this via `onSet`).
    let selectedOrder: [InsightSection]
    let onSet: ([InsightSection]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let memberSet = Set(selectedOrder)
        // Chosen sections first (in order), then the remaining offerable ones; only members reorder.
        let rows = selectedOrder + customizableSections.filter { !memberSet.contains($0) }

        NavigationStack {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, section in
                        let isMember = index < selectedOrder.count
                        row(section: section, index: index, isMember: isMember)
                    }
                } footer: {
                    Text("Sections stay in their own tabs too — adding one here doesn't remove it from Spending, Money or Trends.")
                }
            }
            .navigationTitle("Sections in Custom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(section: InsightSection, index: Int, isMember: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title).foregroundStyle(Palette.label)
                Text(section.tab.title)
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            if isMember {
                Button { move(index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(index == 0)
                    .accessibilityLabel("Move up")
                Button { move(index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(index >= selectedOrder.count - 1)
                    .accessibilityLabel("Move down")
            }
            Toggle("", isOn: Binding(get: { isMember }, set: { _ in toggle(section, isMember: isMember) }))
                .labelsHidden()
                .tint(Palette.good)
        }
    }

    private func toggle(_ section: InsightSection, isMember: Bool) {
        onSet(isMember ? selectedOrder.filter { $0 != section } : selectedOrder + [section])
    }

    private func move(_ from: Int, to: Int) {
        guard selectedOrder.indices.contains(from), selectedOrder.indices.contains(to) else { return }
        var copy = selectedOrder
        copy.swapAt(from, to)
        onSet(copy)
    }
}
