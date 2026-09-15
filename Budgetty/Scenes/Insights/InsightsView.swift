//
//  InsightsView.swift
//  Budgetty
//
//  Insights tab from the mockup: a period stepper (week / month / quarter / half-year / custom
//  range — Android parity), a Breakdown donut (spend by category group) with legend, a stat grid,
//  Top categories bars, and Top stores. All computed from SwiftData for the selected period.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.dynamicTypeSize) private var dynamicType
    /// Switch the app's bottom tab — the "Add income or a budget" setup item jumps to Budget.
    @Environment(\.selectTab) private var selectTab
    @State private var wide = false
    /// The selected Hybrid tab (Overview · Spending · Money · Trends · Custom); Overview is the landing.
    @State private var selectedTab: InsightsTab = .overview
    /// The user-curated Custom tab's membership, as CSV of `InsightSection` raw values in order. Defaults
    /// to the seed; a present-but-empty string means the user cleared it. See `InsightsCustomStore`.
    @AppStorage(SettingsKey.insightsCustomSections) private var customSectionsRaw = InsightsCustomStore.seedCSV
    /// Dismissed Overview setup-checklist items (CSV of `InsightsSetupItem` keys). OVERLAY is not here —
    /// it reuses `overlayNudgeDismissed`.
    @AppStorage(SettingsKey.insightsDismissedSetup) private var dismissedSetupRaw = ""
    @State private var showCustomSections = false
    @State private var showManageCategories = false
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]
    @Query private var storedCategories: [Category]
    // Wellbeing entry-row inputs (the pinned door into the Wellbeing screen, above Breakdown).
    @Query private var budgets: [Budget]
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @Query private var ignoredRows: [IgnoredSubscription]
    @AppStorage("insights.breakdownAllCats") private var breakdownAllCats = false
    /// The pay-cycle start day; the money-flow snapshot and the MONTH period follow it (re-read here
    /// so the screen re-renders when "Month starts on" changes).
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    // Re-open the last recap: the door only exists once a recap has actually been shown for a closed
    // period (Android's `showRecapEntry`). Recomputed on demand by `RecapReopenView`.
    @AppStorage(SettingsKey.recapLastShownWeek) private var recapLastShownWeek = ""
    @AppStorage(SettingsKey.recapLastShownMonth) private var recapLastShownMonth = ""
    @State private var showRecapReopen = false
    /// Planned recurring-bills overlay opt-in (Customize → Layers). Off by default; when off the
    /// Breakdown / Trend sections render exactly as they ship (zero added height). See `PlannedOverlay`.
    @AppStorage(SettingsKey.insightsIncludeRecurringBills) private var includeRecurringBills = false
    /// One-time discovery nudge dismissal ("Insights and Home disagree?").
    @AppStorage(SettingsKey.insightsOverlayNudgeDismissed) private var overlayNudgeDismissed = false
    /// The 50/30/20 split's Savings-allocation choice: 0 = not asked yet (the split shows its inline
    /// ask), 1 = count everything kept, 2 = only deliberate savings. See `SavingsAllocation`.
    @AppStorage(SettingsKey.nwsSavingsAllocation) private var nwsAllocRaw = 0
    /// The section explainer sheet the "Planned" badge opens (nil = none). No Summary case: the iOS
    /// stat grid ships with no header row to hang a badge on, and nothing in it changes with the layer.
    @State private var plannedDialog: PlannedDialog?

    /// The window the whole screen is scoped to; the stepper walks it one unit at a time.
    @State private var period: InsightsPeriod = {
        #if DEBUG
        // Lets screenshot tooling exercise the non-default units (the START_TAB pattern).
        switch ProcessInfo.processInfo.environment["START_PERIOD"] {
        case "week": return .stepped(unit: .week, offset: 0)
        case "quarter": return .stepped(unit: .quarter, offset: 0)
        case "halfYear": return .stepped(unit: .halfYear, offset: 0)
        default: break
        }
        #endif
        return .stepped(unit: .month, offset: 0)
    }()
    @State private var customRange: ClosedRange<Date>?
    @State private var showCustomSheet = false

    private struct Sel: Identifiable { let id = UUID(); let name: String }
    @State private var categorySel: Sel?
    @State private var storeSel: Sel?
    /// The breakdown slice/row the user tapped — puts that category's emoji in the donut centre and
    /// dims the rest. Cleared when the Groups/All toggle flips.
    @State private var pickedCategory: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                // The Hybrid five-tab model on both idioms: iPhone full-bleed, iPad the same column
                // capped to a readable width and centred (the extra landscape room becomes side margin
                // rather than a second pane — a platform-native simplification; see PARITY.md).
                Group {
                    if hSize == .compact {
                        phoneHybrid
                    } else {
                        phoneHybrid.adaptiveReadableWidth()
                    }
                }
                .padding(.top, 6).padding(.bottom, 24)
            }
            .underFloatingDock()
            .trackWideLandscape($wide)
            .screenCanvas()
            // The mockup puts the title inside the scroll content with the toolbar controls on the
            // SAME row, which the system large-title nav bar can't do (toolbar items sit in the small
            // bar above the large title). So draw our own header and hide the bar — the Home pattern.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showManageCategories) { ManageCategoriesView() }
            .sheet(item: $categorySel) { CategoryTransactionsSheet(category: $0.name, items: periodItems) }
            .sheet(item: $storeSel) { StoreTransactionsSheet(store: $0.name, receipts: periodReceipts) }
            .sheet(isPresented: $showCustomSections) {
                CustomSectionsSheet(
                    selectedOrder: InsightsCustomStore.parse(customSectionsRaw),
                    onSet: { customSectionsRaw = InsightsCustomStore.csv($0) }
                )
            }
            .sheet(isPresented: $showCustomSheet) { DateRangeSheet(range: $customRange) }
            .fullScreenCover(isPresented: $showRecapReopen) { RecapReopenView() }
            .sheet(item: $plannedDialog) { dialog in
                // Breakdown's "Spent"/denominator is the donut's slice-sum basis (so "44% of €X"
                // reconciles with the legend); Trend's is the period's paid total (its bars' spend).
                PlannedOverlaySheet(dialog: dialog, overlay: plannedOverlay,
                                    spent: dialog == .breakdown ? breakdownSpent : totalSpent,
                                    periodLabel: dialog == .trend ? trendRangeLabel : period.friendlyLabel)
            }
            .onChange(of: customRange) { _, range in
                if let range {
                    period = .custom(start: range.lowerBound, end: range.upperBound)
                } else if period.isCustom {
                    period = .stepped(unit: .month, offset: 0)
                }
            }
        }
    }

    // MARK: - Layout

    // MARK: - Phone Hybrid (Overview · Spending · Money · Trends · Custom)

    /// The iPhone Hybrid: a stacked toolbar (title + wellbeing pip + recap button), the full-width
    /// period pill, the scrollable tab strip, then the selected tab's content.
    private var phoneHybrid: some View {
        VStack(spacing: 0) {
            insightsToolbar.padding(.horizontal, 20)
            stepper.padding(.horizontal, 20).padding(.top, 8)
            InsightsTabBar(selection: $selectedTab).padding(.top, 12)
            VStack(spacing: 14) { tabContent }
                .padding(.horizontal, 20).padding(.top, 14)
        }
    }

    /// The stacked toolbar's top row: title + the wellbeing score pip (once there's a score) + the recap
    /// button (once a recap is ready). Under accessibility Dynamic Type the recap button drops first (the
    /// one optional control) so the title and pip keep their room. D6: no Customize control.
    private var insightsToolbar: some View {
        HStack(spacing: 12) {
            Text("Insights").font(.largeTitle).fontWeight(.bold)
            Spacer(minLength: 8)
            // The two toolbar controls keep clear air between them (they read as separate affordances,
            // not one cluster).
            if let score = wellbeingSummary.score.score {
                NavigationLink { WellbeingView() } label: { WellbeingScorePip(score: score) }
                    .buttonStyle(.plain)
            }
            if showRecapEntry && dynamicType < .accessibility1 {
                RecapToolbarButton { showRecapReopen = true }
            }
        }
    }

    /// Whether the re-open-last-recap door is available (a recap has been generated for a closed period).
    private var showRecapEntry: Bool {
        !recapLastShownWeek.isEmpty || !recapLastShownMonth.isEmpty
    }

    private var incomeCards: some View {
        // Income & bills scale to the selected period via windowAmount and pair with that period's
        // actual spend (Android parity). windowAmount's createdAt-clip stops a just-added salary being
        // projected back over months it didn't exist for, so a non-month view no longer mismatches the
        // income and spend windows — the reason this was previously pinned to a "this month" snapshot.
        IncomeInsightsCards(income: recurring.filter(\.isIncome),
                            bills: recurring.filter { !$0.isIncome },
                            periodSpent: totalSpent,
                            window: period.interval)
    }

    // MARK: - Tab content dispatch

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview: overviewTab
        case .custom: customTab
        default: fixedTab(selectedTab)
        }
    }

    /// A fixed group (Spending / Money / Trends): its sections in canonical order, each self-gating. A
    /// tab with nothing to show gets a friendly stand-in — Money with no plan an invitation, Spending /
    /// Trends with no spend a period-aware empty. Android parity: `BlankTabInvitation`.
    @ViewBuilder
    private func fixedTab(_ tab: InsightsTab) -> some View {
        let hasData = !periodReceipts.isEmpty
        // The planned-bills overlay switch leads the Spending tab — next to the charts its layer reshapes.
        // Android parity: SpendingOverlayToggleCard (Spending-only; Trends honours the same global toggle).
        if tab == .spending && hasBills {
            overlayToggleCard
        }
        if tab == .money && !hasIncome && !hasBills {
            TabInvitationCard(
                title: "Your money flow needs a plan",
                body_: "Add your income or a budget to see your money flow.",
                cta: "Add income or budget",
                systemImage: "creditcard.fill",
                onCta: { selectTab?(.budget) }
            )
        } else if (tab == .spending || tab == .trends) && !hasData {
            PeriodEmptyState(periodLabel: period.friendlyLabel, hasAnyData: !receipts.isEmpty)
        } else {
            ForEach(sections(in: tab)) { sectionView($0) }
        }
    }

    /// The sections a fixed tab renders, in display order. Android parity: `InsightsSection.tab()` order.
    private func sections(in tab: InsightsTab) -> [InsightSection] {
        switch tab {
        case .spending: [.breakdown, .topCategories, .topStores, .biggestPurchases, .subscriptions]
        case .money: [.income, .needsWantsSavings]
        case .trends: [.trend, .comparison, .highlights]
        case .overview, .custom: []
        }
    }

    // MARK: - Overview tab (bespoke composite)

    private var overviewTab: some View {
        VStack(spacing: 14) {
            overviewHero
            if !groupSlices.isEmpty { overviewTopSpending }
            if !overviewHighlights.isEmpty || projectedTotal != nil { overviewWorthKnowing }
            OverviewSetupChecklist(items: activeSetupItems, onAction: onSetupAction, onDismiss: onSetupDismiss)
        }
    }

    /// Hero: total spent + period-over-period delta + the 50/30/20 mini split + headline stats.
    private var overviewHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Total spent").font(.caption).foregroundStyle(Palette.secondaryLabel)
            HStack(alignment: .bottom, spacing: 8) {
                Text(totalSpent.formatMoney())
                    .font(.system(size: 36, weight: .bold)).foregroundStyle(Palette.label)
                overviewDelta
            }
            if let split = needsWantsSplit {
                MiniSplitBar(split: split).padding(.top, 16)
            }
            HStack(spacing: 10) {
                statTile("Avg / day", avgPerDay.formatMoney(), color: Palette.label)
                statTile("Receipts", "\(periodReceipts.count)", color: Palette.label)
                statTile("Saved", totalSaved.formatMoney(), color: Palette.good)
            }
            .padding(.top, 18)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var overviewDelta: some View {
        if previousTotal > 0 {
            let pct = Int(((dbl(totalSpent) - dbl(previousTotal)) / dbl(previousTotal) * 100).rounded())
            if pct != 0 {
                let down = pct < 0
                Text("\(down ? "↓" : "↑") \(abs(pct))%")
                    .font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(down ? Palette.good : Palette.secondaryLabel)
                    .padding(.bottom, 6)
            }
        }
    }

    /// Top spending: the top-four category groups as a compact list, linking into the Spending tab.
    /// (A plain list, not the donut — the donut drags its own legend + "See all"; Android does the same.)
    private var overviewTopSpending: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverviewLinkHeader(title: "Top spending", linkTab: .spending) { selectedTab = $0 }
            ForEach(Array(groupSlices.prefix(4)), id: \.name) { slice in
                Button { categorySel = Sel(name: slice.name) } label: {
                    HStack(spacing: 10) {
                        Circle().fill(categoryColor(slice.name)).frame(width: 9, height: 9)
                        Text(Categories.displayName(slice.name))
                            .font(.subheadline).foregroundStyle(Palette.label).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(slice.value.formatMoney())
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private var overviewHighlights: [InsightHighlight] {
        InsightHighlight.compute(current: periodItems, previous: previousItems)
    }

    /// Worth knowing: the top highlights + the on-pace projection, linking into the Trends tab.
    private var overviewWorthKnowing: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverviewLinkHeader(title: "Worth knowing", linkTab: .trends) { selectedTab = $0 }
            ForEach(Array(overviewHighlights.prefix(2))) { h in
                HStack(alignment: .top, spacing: 10) {
                    Text(h.emoji).font(.system(size: 16))
                    Text(h.text(compareNoun: period.compareNoun))
                        .font(.system(size: 14)).foregroundStyle(Palette.label)
                }
            }
            if let projected = projectedTotal {
                Text("On pace for \(projected.formatMoney())")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    /// The planned-bills overlay switch, leading the Spending tab — next to the charts its "planned"
    /// layer reshapes (the Breakdown donut; the Trends bars). A visible switch so its on/off state stays
    /// glanceable; the caller shows it only when there are bills to overlay. Android parity:
    /// `SpendingOverlayToggleCard` (moved here from the retired Overview options card).
    private var overlayToggleCard: some View {
        Toggle(isOn: $includeRecurringBills) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Include recurring bills").font(.subheadline).foregroundStyle(Palette.label)
                Text("Overlay planned bills as a separate layer")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .tint(Palette.tint)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentCard(cornerRadius: 16)
    }

    // MARK: - Overview setup checklist (P3)

    /// Which setup-checklist items are live right now — each fires only while its setup is genuinely
    /// incomplete and it hasn't been dismissed. The overlay item reuses the older discovery-nudge gate
    /// (and its own dismissed flag). Android parity: `activeSetupItems`.
    private var activeSetupItems: [InsightsSetupItem] {
        let dismissed = Set(dismissedSetupRaw.split(separator: ",").map(String.init))
        var out: [InsightsSetupItem] = []
        if needsWantsSplit != nil && nwsAllocation == .unset && !dismissed.contains(InsightsSetupItem.savings.rawValue) {
            out.append(.savings)
        }
        if !hasIncome && !hasBills && !dismissed.contains(InsightsSetupItem.income.rawValue) {
            out.append(.income)
        }
        if !includeRecurringBills && !overlayNudgeDismissed && !overlayBills.isEmpty && periodBills > 0 {
            out.append(.overlay)
        }
        if needsWantsSplit != nil && !hasCustomBuckets && !dismissed.contains(InsightsSetupItem.buckets.rawValue) {
            out.append(.buckets)
        }
        return out
    }

    private func onSetupAction(_ item: InsightsSetupItem) {
        switch item {
        case .savings: withAnimation { selectedTab = .money }   // the "what counts as savings?" ask is there
        case .income: selectTab?(.budget)
        case .overlay: withAnimation { includeRecurringBills = true }
        case .buckets: showManageCategories = true
        }
    }

    private func onSetupDismiss(_ item: InsightsSetupItem) {
        if item == .overlay {
            overlayNudgeDismissed = true
        } else {
            var keys = dismissedSetupRaw.split(separator: ",").map(String.init)
            if !keys.contains(item.rawValue) { keys.append(item.rawValue) }
            dismissedSetupRaw = keys.joined(separator: ",")
        }
    }

    // MARK: - Custom tab (P4)

    private var customTab: some View {
        let chosen = InsightsCustomStore.parse(customSectionsRaw)
        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                customCountLabel(chosen)
                Spacer(minLength: 8)
                Button { showCustomSections = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        Text("Choose sections").font(.subheadline).fontWeight(.semibold)
                    }
                    .foregroundStyle(Palette.tint)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Palette.tintSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if chosen.isEmpty {
                customEmptyInvite
            } else {
                ForEach(chosen) { sectionView($0) }
                addSectionRow
            }
        }
    }

    private func customCountLabel(_ chosen: [InsightSection]) -> some View {
        // Uppercase the assembled string (the localized plural count + the period) so the plural resolves
        // via the "%lld sections" catalog entry without a deprecated Text(_:) + Text concatenation.
        let text = chosen.isEmpty
            ? String(localized: "No sections yet")
            : String(localized: "\(chosen.count) sections") + " · " + period.friendlyLabel
        return Text(text.uppercased())
            .font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
    }

    private var customEmptyInvite: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.tertiaryLabel, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(Palette.secondaryLabel))
            Text("Your own view").font(.title3).fontWeight(.semibold).foregroundStyle(Palette.label)
            Text("Pick only the sections you care about — they stay in this tab, in the order you choose, and follow the same period as everything else.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
            Button { showCustomSections = true } label: {
                Text("Add sections").font(.body).fontWeight(.semibold).ctaPill(height: 48)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22).padding(.horizontal, 18)
        .contentCard(cornerRadius: 16)
    }

    private var addSectionRow: some View {
        Button { showCustomSections = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                Text("Add another section").font(.subheadline).fontWeight(.semibold)
            }
            .foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.tertiaryLabel, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hybrid data helpers

    private var hasIncome: Bool { recurring.contains(where: \.isIncome) }
    private var hasBills: Bool { recurring.contains { !$0.isIncome } }
    private var hasCustomBuckets: Bool { storedCategories.contains { $0.bucket != nil } }

    /// The wellbeing summary behind the toolbar score pip (and its → Wellbeing link).
    private var wellbeingSummary: WellbeingSummary {
        WellbeingScan.run(receipts: receipts, budgets: budgets, recurring: recurring, goals: goals,
                          contributions: contributions, ignoredSubs: Set(ignoredRows.map(\.merchant)),
                          monthStartDay: monthStartDay)
    }

    @ViewBuilder
    private func sectionView(_ section: InsightSection) -> some View {
        switch section {
        case .trend: trendCard
        case .breakdown: breakdownCard
        case .stats: statGrid
        case .needsWantsSavings: needsWantsSplitSection
        case .highlights: highlightsSection
        case .comparison: comparisonSection
        case .topCategories: topCategoriesCard
        case .topStores: topStoresCard
        case .biggestPurchases: biggestSection
        case .income: incomeCards
        case .subscriptions: SubscriptionsCard()
        }
    }

    // MARK: - Extra analysis cards (Android parity)

    @ViewBuilder
    private var highlightsSection: some View {
        let highlights = InsightHighlight.compute(current: periodItems, previous: previousItems)
        if !highlights.isEmpty {
            HighlightsCard(highlights: highlights, compareNoun: period.compareNoun)
        }
    }

    /// Only appears once there's a previous-period total to compare against.
    @ViewBuilder
    private var comparisonSection: some View {
        if previousTotal > 0 {
            PeriodComparisonCard(
                currentTotal: totalSpent, previousTotal: previousTotal,
                currentLabel: period.contextNoun.prefix(1).capitalized + period.contextNoun.dropFirst(),
                previousLabel: previousPeriodLabel,
                compareNoun: period.compareNoun
            )
        }
    }

    @ViewBuilder
    private var biggestSection: some View {
        let purchases = biggestPurchases
        if !purchases.isEmpty {
            BiggestPurchasesCard(purchases: purchases) { categoryColor($0) }
        }
    }

    // MARK: - Period

    /// The period control: ONE full-width fully-rounded pill with the step arrows *inside* it and the
    /// active window centred (tap the centre to switch unit or pick a range). The locked cross-platform
    /// tweak — no eyebrow, no separate arrow buttons. Arrows disable while a custom range is active.
    private var stepper: some View {
        let steppable = !period.isCustom
        return HStack(spacing: 4) {
            arrowButton("chevron.left", disabled: !steppable || !canStepBackward) { step(-1) }
                .accessibilityLabel("Previous period")
                .accessibilityIdentifier(A11y.Insights.periodPrev)
            periodMenu
            arrowButton("chevron.right", disabled: !steppable || !canStepForward) { step(1) }
                .accessibilityLabel("Next period")
                .accessibilityIdentifier(A11y.Insights.periodNext)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Palette.matControl, in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.matControlBorder, lineWidth: 0.5))
    }

    private var periodMenu: some View {
        Menu {
            ForEach(PeriodUnit.allCases) { unit in
                Button {
                    period = .stepped(unit: unit, offset: 0)
                    customRange = nil
                } label: {
                    if period.steppedUnit == unit {
                        Label(unit.menuLabel, systemImage: "checkmark")
                    } else {
                        Text(unit.menuLabel)
                    }
                }
            }
            Divider()
            // "All time" reuses the custom-range window, bounded to the earliest recorded receipt so
            // the trend and averages stay meaningful (no epoch-to-today blow-up). Reuses the custom
            // path so the arrows disable and the pill reads as a span, matching Android.
            Button {
                // receipts are newest-first, so `.last` is the earliest; clamp below today so a
                // future-dated receipt can't invert the range.
                let earliest = min(receipts.last?.createdAt ?? .now, .now)
                customRange = earliest ... .now
            } label: {
                Label("All time", systemImage: "infinity")
            }
            Button {
                if case .custom(let s, let e) = period { customRange = s...e }
                showCustomSheet = true
            } label: {
                if period.isCustom {
                    Label("Custom range…", systemImage: "checkmark")
                } else {
                    Label("Custom range…", systemImage: "calendar")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(period.friendlyLabel)
                    .font(.headline).foregroundStyle(Palette.label).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Period: \(period.friendlyLabel)")
    }

    private func step(_ delta: Int) {
        if case .stepped(let unit, let offset) = period {
            period = .stepped(unit: unit, offset: offset + delta)
        }
    }

    private var canStepForward: Bool {
        if case .stepped(_, let offset) = period { offset < 0 } else { false }
    }

    /// Stop stepping back once the window reaches the earliest recorded receipt.
    private var canStepBackward: Bool {
        guard let oldest = receipts.last?.createdAt else { return false }
        return period.interval.start > oldest
    }

    /// A plain glyph step arrow that lives *inside* the period pill (no separate circular background).
    private func arrowButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? Palette.tertiaryLabel : Palette.label)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Derived data

    private var periodReceipts: [Receipt] {
        let window = period.interval
        return receipts.filter { window.contains($0.createdAt) }
    }
    private var periodItems: [LineItem] { periodReceipts.flatMap(\.items) }
    private var totalSpent: Decimal { periodReceipts.reduce(.zero) { $0 + $1.paidTotal } }
    private var totalSaved: Decimal { periodReceipts.reduce(.zero) { $0 + $1.discount } }

    // MARK: - Needs / Wants / Savings 50/30/20 split (Android parity)

    /// The split card (+ its trend beneath it) as one reorderable Insights section on iPhone.
    @ViewBuilder private var needsWantsSplitSection: some View {
        VStack(spacing: 14) {
            nwsSplitCard
            nwsTrendCard
        }
    }

    /// The split card itself — shared by the iPhone section and the iPad columns. Shows the setup
    /// state when there's no income to measure against (`needsWantsSplit == nil`).
    private var nwsSplitCard: some View {
        NeedsWantsSplitCard(split: needsWantsSplit) { keep in nwsAllocRaw = keep ? 1 : 2 }
    }

    /// The closed-month trend, only beneath a populated split with enough months. iPad shows the
    /// per-column savings %.
    @ViewBuilder private var nwsTrendCard: some View {
        if showsBucketTrend {
            BucketTrendCard(months: bucketTrend, showMonthLabels: hSize == .regular)
        }
    }

    private var nwsAllocation: SavingsAllocation { SavingsAllocation(rawValue: nwsAllocRaw) ?? .unset }

    /// This period's planned income (income recurring scaled to the window via `windowAmount`) — the
    /// 50/30/20 denominator, matching `IncomeInsightsCards.periodIncome`.
    private var periodIncome: Decimal {
        recurring.filter(\.isIncome).reduce(.zero) { $0 + $1.windowAmount(period.interval) }
    }

    /// Spend per raw category across `rs` (line totals, as the Breakdown attributes category spend).
    private func spendByCategory(_ rs: [Receipt]) -> [String: Decimal] {
        var sums: [String: Decimal] = [:]
        for item in rs.flatMap(\.items) { sums[item.category, default: .zero] += item.lineTotal }
        return sums
    }

    /// Net (signed) savings-goal contributions dated within `window` — deposits add, withdrawals net.
    private func savingsContributed(in window: DateInterval) -> Decimal {
        contributions.filter { window.contains($0.date) }.reduce(.zero) { $0 + $1.amount }
    }

    /// The split for the selected period; nil → the setup state (no income to measure against).
    private var needsWantsSplit: NeedsWantsSplit? {
        NeedsWantsSplitMath.split(
            income: periodIncome,
            spendByCategory: spendByCategory(periodReceipts),
            categories: storedCategories,
            savingsContributed: savingsContributed(in: period.interval),
            countLeftoverAsSavings: nwsAllocation.countLeftoverAsSavings
        )
    }

    /// The split across the last closed pay-cycle months (oldest first), independent of the selected
    /// period. Walks back month by month; the run stops at the first month with no income plan.
    private var bucketTrend: [BucketMonth] {
        let f = DateFormatter(); f.dateFormat = "MMM"
        let incomeRows = recurring.filter(\.isIncome)
        let months: [NeedsWantsSplitMath.MonthInput] =
            (1...NeedsWantsSplitMath.trendMonths).map { back in
                let window = InsightsPeriod.stepped(unit: .month, offset: -back).interval
                let rs = receipts.filter { window.contains($0.createdAt) }
                return NeedsWantsSplitMath.MonthInput(
                    axisLabel: f.string(from: window.start),
                    income: incomeRows.reduce(.zero) { $0 + $1.windowAmount(window) },
                    spendByCategory: spendByCategory(rs),
                    savingsContributed: savingsContributed(in: window)
                )
            }
        return NeedsWantsSplitMath.trend(recentFirst: months, categories: storedCategories)
    }

    /// The trend card renders only beneath a populated split and with enough closed months.
    private var showsBucketTrend: Bool {
        needsWantsSplit != nil && bucketTrend.count >= NeedsWantsSplitMath.minTrendMonths
    }

    // MARK: - Planned recurring-bills overlay (Android parity)

    /// The recurring bills (non-income) the overlay projects; empty for an income-only plan.
    private var overlayBills: [Recurring] { recurring.filter { !$0.isIncome } }

    /// This period's recurring bills, projected onto the window (`windowAmount`, so no back-projection)
    /// — the figure Home already shows, used to gate the discovery nudge.
    private var periodBills: Decimal {
        overlayBills.reduce(Decimal.zero) { $0 + $1.windowAmount(period.interval) }
    }

    /// The de-duplicated planned overlay for the selected period. Empty unless the user has opted in
    /// (Customize → Layers), so the OFF screen is byte-for-byte the shipped one.
    private var plannedOverlay: PlannedOverlay {
        guard includeRecurringBills, !overlayBills.isEmpty else { return .empty }
        return PlannedOverlay.build(bills: overlayBills, window: period.interval, receipts: periodReceipts)
    }

    /// Whether the planned layer is on AND has something to draw this period.
    private var overlayActive: Bool { includeRecurringBills && plannedOverlay.hasPlanned }

    /// The Breakdown donut's spend basis — the sum of line totals the category slices and their
    /// percentages are taken against. The Breakdown sheet's "Spent" and % denominator use this (not the
    /// paid total, which nets off discounts) so "44% of €X" reconciles with the legend.
    private var breakdownSpent: Decimal { periodItems.reduce(.zero) { $0 + $1.lineTotal } }

    /// "Dec 2025 – Jun 2026" — the span the 7 trend bars cover, for the Trend sheet subtitle.
    private var trendRangeLabel: String {
        var windows = [period]
        for _ in 0..<6 { windows.append(windows.last!.previous()) }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        let first = f.string(from: windows.last!.interval.start)   // oldest
        let last = f.string(from: windows.first!.interval.start)   // selected
        return first == last ? last : "\(first) – \(last)"
    }

    private var previousReceipts: [Receipt] {
        let window = period.previous().interval
        return receipts.filter { window.contains($0.createdAt) }
    }
    private var previousItems: [LineItem] { previousReceipts.flatMap(\.items) }
    private var previousTotal: Decimal { previousReceipts.reduce(.zero) { $0 + $1.paidTotal } }

    /// "Last month" / "Last week" / … — derived from the compare caption ("vs last month").
    private var previousPeriodLabel: String {
        let stripped = period.compareNoun.replacingOccurrences(of: "vs ", with: "")
        return stripped.prefix(1).capitalized + stripped.dropFirst()
    }

    /// Days of the period elapsed so far (a past period counts in full), at least 1.
    private var elapsedDays: Int {
        let cal = Calendar.current
        let interval = period.interval
        let start = cal.startOfDay(for: interval.start)
        let total = max(1, cal.dateComponents([.day], from: start, to: interval.end).day ?? 1)
        let elapsed = (cal.dateComponents([.day], from: start, to: cal.startOfDay(for: .now)).day ?? 0) + 1
        return min(max(1, elapsed), total)
    }

    /// The period's spend projected to its end at the current pace — only for the in-progress
    /// current period with at least two elapsed days (Android's rule).
    private var projectedTotal: Decimal? {
        guard case .stepped(_, 0) = period, totalSpent > 0, Date.now < period.interval.end else { return nil }
        let cal = Calendar.current
        let interval = period.interval
        let totalDays = max(1, cal.dateComponents([.day], from: cal.startOfDay(for: interval.start),
                                                  to: interval.end).day ?? 1)
        let elapsed = elapsedDays
        guard elapsed >= 2, elapsed < totalDays else { return nil }
        return totalSpent * Decimal(totalDays) / Decimal(elapsed)
    }

    /// The period's top line items by line total, paired with their receipt's store.
    private var biggestPurchases: [(item: LineItem, store: String)] {
        periodReceipts
            .flatMap { r in r.items.map { (item: $0, store: r.store) } }
            .sorted { $0.item.lineTotal > $1.item.lineTotal }
            .prefix(5)
            .map { $0 }
    }

    /// Category color: stored rows first (covers custom categories), predefined palette otherwise.
    private func categoryColor(_ name: String) -> Color {
        if let stored = storedCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return Color(argb: stored.colorArgb)
        }
        return Color(argb: Categories.color(for: name))
    }

    /// Category emoji: stored rows first (covers custom categories), the predefined glyph otherwise —
    /// mirrors `categoryColor` so a legend tile matches its slice.
    private func categoryEmoji(_ name: String) -> String {
        if let stored = storedCategories.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
           !stored.icon.isEmpty {
            return stored.icon
        }
        return Categories.emoji(for: name)
    }

    /// Whole-percent share of `total` for a legend row (rounds half away from zero, like Android).
    private func percentInt(_ value: Decimal, of total: Decimal) -> Int {
        guard total > 0 else { return 0 }
        return Int((dbl(value) / dbl(total) * 100).rounded())
    }

    /// Spend rolled up to top-level groups, descending.
    private var groupSlices: [(name: String, value: Decimal)] {
        var sums: [String: Decimal] = [:]
        for item in periodItems {
            let g = Categories.groupOf(item.category)
            sums[g, default: .zero] += item.lineTotal
        }
        return sums.map { (name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }

    private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

    // MARK: - Trend

    /// Total spend for each of the last 7 windows of the selected unit, oldest → the selected
    /// window (last bar = selected).
    /// The 7 windows the trend bars cover, oldest → the selected window (last = selected). Shared by
    /// the bars and the planned-cap projection so the two always align.
    private var trendWindows: [InsightsPeriod] {
        var windows = [period]
        for _ in 0..<6 { windows.append(windows.last!.previous()) }
        return windows.reversed()
    }

    private var periodTrend: [(label: String, value: Decimal)] {
        trendWindows.map { p in
            let window = p.interval
            let total = receipts
                .filter { window.contains($0.createdAt) }
                .reduce(Decimal.zero) { $0 + $1.paidTotal }
            return (label: p.barLabel, value: total)
        }
    }

    /// Planned recurring-bills cap for each of the 7 trend bars (Decimal), aligned to `trendWindows`.
    /// Each bar's bills projected onto its own window (`windowAmount`) — so a whole-month bar carries
    /// the flat monthly total and months before the plans were created carry none (no back-projection).
    /// All zero unless the overlay is on. Android parity: `TrendBucket.planned` / `perMonthPlanned`.
    private var trendPlanned: [Decimal] {
        guard overlayActive else { return Array(repeating: .zero, count: trendWindows.count) }
        return trendWindows.map { w in
            overlayBills.reduce(Decimal.zero) { $0 + $1.windowAmount(w.interval) }
        }
    }

    private var trendCard: some View {
        let data = periodTrend
        let planned = trendPlanned
        // When the overlay is on the axis must fit spend + bills, so the solid bars get shorter
        // (mockup "the bars got shorter"). Otherwise it's the shipped spend-only scale.
        let maxV = data.indices.map { dbl(data[$0].value) + dbl(planned[$0]) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Trend").font(.headline)
                if overlayActive { PlannedBadge { plannedDialog = .trend } }
                Spacer()
                trendDeltaPill
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, d in
                    let isCurrent = idx == data.count - 1
                    let cap = dbl(planned[idx])
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        VStack(spacing: 0) {
                            // The hatched "planned bills" cap stacked over the solid spend bar.
                            if cap > 0 {
                                let capShape = UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                                capShape.fill(Palette.plan.opacity(0.12))
                                    .overlay(HatchStripes(step: 5).stroke(Palette.plan, lineWidth: 1.2).clipShape(capShape))
                                    .overlay(capShape.strokeBorder(Palette.plan, lineWidth: 1))
                                    .frame(height: barHeight(cap, max: maxV))
                            }
                            UnevenRoundedRectangle(
                                topLeadingRadius: cap > 0 ? 0 : 5,
                                bottomLeadingRadius: 5,
                                bottomTrailingRadius: 5,
                                topTrailingRadius: cap > 0 ? 0 : 5,
                                style: .continuous
                            )
                            .fill(isCurrent ? Palette.tint : Palette.fill)
                            .frame(height: barHeight(dbl(d.value), max: maxV))
                        }
                        Text(d.label).font(.system(size: 10))
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundStyle(isCurrent ? Palette.tint : Palette.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104)

            // Spending pace: the in-progress period's projected total (mockup caption).
            if let projected = projectedTotal {
                Text("On pace for about \(projected.formatMoney())")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    @ViewBuilder
    private var trendDeltaPill: some View {
        let vals = periodTrend.map { dbl($0.value) }
        if vals.count >= 2, let current = vals.last {
            let prev = vals[vals.count - 2]
            if prev > 0 {
                let pct = Int((abs(current - prev) / prev * 100).rounded())
                let down = current <= prev
                let color = down ? Palette.good : Palette.warn
                HStack(spacing: 4) {
                    Image(systemName: down ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(pct)% \(period.compareNoun)").font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(color.opacity(0.14), in: Capsule())
            }
        }
    }

    private func barHeight(_ value: Double, max: Double) -> CGFloat {
        guard max > 0 else { return 4 }
        return Swift.max(4, CGFloat(value / max) * 84)
    }

    // MARK: - Breakdown

    /// Spend per raw category (custom categories keep their own slice), descending — the
    /// breakdown's "All" granularity.
    private var categorySlices: [(name: String, value: Decimal)] {
        var sums: [String: Decimal] = [:]
        for item in periodItems { sums[item.category, default: .zero] += item.lineTotal }
        return sums.map { (name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Breakdown").font(.headline)
                if overlayActive { PlannedBadge { plannedDialog = .breakdown } }
                Spacer()
                breakdownToggle
            }
            let slices = breakdownAllCats ? categorySlices : groupSlices
            let netTotal = slices.reduce(Decimal.zero) { $0 + $1.value }
            let selIndex = pickedCategory.flatMap { pc in slices.firstIndex { $0.name == pc } }
            let picked = selIndex.map { slices[$0] }
            let planned = plannedOverlay.plannedTotal
            // planned / (spend + planned) — the share of the ring the hatched "Bills · planned" wedge
            // takes, compressing the category arcs into the spend share (their % stay a % of spend).
            let plannedFrac: CGFloat? = (overlayActive && netTotal + planned > 0)
                ? CGFloat(dbl(planned) / dbl(netTotal + planned)) : nil
            HStack(spacing: 4) {
                ZStack {
                    DonutChart(slices: slices.map { (categoryColor($0.name), dbl($0.value)) },
                               selectedIndex: selIndex, plannedFraction: plannedFrac) { idx in
                        let name = slices[idx].name
                        pickedCategory = (pickedCategory == name) ? nil : name
                    }
                    .frame(width: 150, height: 150)
                    if let picked {
                        VStack(spacing: 1) {
                            Text(categoryEmoji(picked.name)).font(.system(size: 26))
                            Text(Categories.displayName(picked.name))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.label).lineLimit(1)
                            Text(picked.value.formatMoney()).font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
                            Text("\(percentInt(picked.value, of: netTotal))% of total")
                                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                        }
                        .frame(width: 108).multilineTextAlignment(.center)
                    } else if overlayActive {
                        // Overlay on: keep the spend hero and add the planned bills below it — the
                        // centre reads spend first, planned second (mockup "€950 / + €967 bills").
                        VStack(spacing: 0) {
                            Text("Spent").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                            Text(netTotal.formatMoney()).font(.title3).fontWeight(.bold)
                            Text("+ \(planned.formatMoney()) bills")
                                .font(.caption2).fontWeight(.medium).foregroundStyle(Palette.secondaryLabel)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Text("Total").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                            Text(netTotal.formatMoney()).font(.title3).fontWeight(.bold)
                            Text(period.contextNoun).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 9) {
                ForEach(slices, id: \.name) { s in
                    let isSel = s.name == pickedCategory
                    Button {
                        pickedCategory = isSel ? nil : s.name
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categoryColor(s.name))
                                .frame(width: 36, height: 36)
                                .overlay(Text(categoryEmoji(s.name)).font(.system(size: 18)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(Categories.displayName(s.name))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.label)
                                    .lineLimit(1)
                                HStack(alignment: .firstTextBaseline, spacing: 5) {
                                    Text("\(percentInt(s.value, of: netTotal))%")
                                        .font(.system(size: 12, weight: .heavy))
                                        .foregroundStyle(Palette.label)
                                    Text(s.value.formatMoney())
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Palette.secondaryLabel)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3).padding(.horizontal, 5)
                        .background(isSel ? Palette.tintSoft : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(pickedCategory == nil || isSel ? 1 : 0.42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: pickedCategory)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
        .onChange(of: breakdownAllCats) { pickedCategory = nil }
    }

    /// Groups ↔ all-categories granularity switch on the Breakdown card (Android parity).
    private var breakdownToggle: some View {
        HStack(spacing: 2) {
            breakdownSegment("Groups", active: !breakdownAllCats) { breakdownAllCats = false }
            breakdownSegment("All", active: breakdownAllCats) { breakdownAllCats = true }
        }
        .padding(2)
        .background(Palette.fill, in: Capsule())
    }

    private func breakdownSegment(_ title: LocalizedStringKey, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? Palette.label : Palette.secondaryLabel)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(active ? AnyShapeStyle(Palette.matControl) : AnyShapeStyle(.clear), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statTile("Total spent", totalSpent.formatMoney(), color: Palette.label)
            statTile("Receipts", "\(periodReceipts.count)", color: Palette.label)
            statTile("Avg / receipt", avgPerReceipt.formatMoney(), color: Palette.label)
            statTile("Avg / day", avgPerDay.formatMoney(), color: Palette.label)
            statTile("Saved", totalSaved.formatMoney(), color: Palette.good)
        }
    }

    private var avgPerReceipt: Decimal {
        guard !periodReceipts.isEmpty else { return .zero }
        return totalSpent / Decimal(periodReceipts.count)
    }

    private var avgPerDay: Decimal {
        guard totalSpent > 0 else { return .zero }
        return totalSpent / Decimal(elapsedDays)
    }

    private func statTile(_ title: LocalizedStringKey, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Palette.secondaryLabel)
            // Keep the amount on one line in the narrow third-width tile — shrink to fit rather than
            // wrap the currency symbol onto a second row (the iOS take on Android's marquee).
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentCard(cornerRadius: 14)
    }

    // MARK: - Top categories

    private var topCategoriesCard: some View {
        let top = Array(groupSlices.prefix(5))
        let maxV = top.map { dbl($0.value) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            Text("Top categories").font(.headline)
            ForEach(top, id: \.name) { s in
                Button { categorySel = Sel(name: s.name) } label: {
                    VStack(spacing: 5) {
                        HStack {
                            Text("\(Categories.emoji(for: s.name)) \(Categories.displayName(s.name))")
                                .font(.subheadline).foregroundStyle(Palette.label).lineLimit(1)
                            Spacer()
                            Text(s.value.formatMoney()).font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(Palette.label)
                        }
                        ProgressBarView(fraction: maxV > 0 ? dbl(s.value) / maxV : 0,
                                        color: Color(argb: Categories.color(for: s.name)))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    // MARK: - Top stores

    private var topStores: [(store: String, value: Decimal)] {
        var sums: [String: Decimal] = [:]
        for r in periodReceipts { sums[r.store, default: .zero] += r.paidTotal }
        return sums.map { (store: $0.key, value: $0.value) }.sorted { $0.value > $1.value }.prefix(5).map { $0 }
    }

    private var topStoresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Top stores").font(.headline)
            let stores = topStores
            VStack(spacing: 0) {
                ForEach(Array(stores.enumerated()), id: \.element.store) { idx, s in
                    Button { storeSel = Sel(name: s.store) } label: {
                        HStack(spacing: 12) {
                            StoreAvatar(store: s.store, size: 34)
                            Text(s.store).font(.subheadline).foregroundStyle(Palette.label)
                            Spacer()
                            Text(s.value.formatMoney()).font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(Palette.label)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if idx < stores.count - 1 { Divider() }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

}
