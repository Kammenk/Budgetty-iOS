//
//  RootView.swift
//  Budgetty
//
//  App shell. iPhone (compact) draws its own floating glass dock — the mockup's dock is denser,
//  wider and violet-selected, and the system Liquid Glass tab bar can't be restyled (it ignores
//  `UITabBarAppearance` — pixel-diff-proven), so a custom bottom chrome is the only way to match.
//  The Scan pill floats exactly 10pt above the dock (mockup spacing). iPad (regular) keeps the
//  system `TabView` + `.sidebarAdaptable` — the floating top tab bar matches the iPad mockup —
//  with Scan in the tab bar's bottom accessory. Scan is presented as a full-screen cover.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable, CaseIterable {
    case home, history, insights, budget

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"; case .history: "History"
        case .insights: "Insights"; case .budget: "Budget"
        }
    }

    /// SF Symbol for the tab.
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock.arrow.circlepath"
        case .insights: "chart.bar.fill"
        case .budget: "dollarsign.circle.fill"
        }
    }

    /// Stable UI-automation id (matches Android's tab test tags — see A11y.Tab).
    var a11yIdentifier: String {
        switch self {
        case .home: A11y.Tab.home
        case .history: A11y.Tab.history
        case .insights: A11y.Tab.insights
        case .budget: A11y.Tab.budget
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["START_TAB"] {
        case "history": return .history
        case "insights": return .insights
        case "budget": return .budget
        default: break
        }
        #endif
        return .home
    }()
    @State private var showScan = false
    @State private var dockHidden = false
    @State private var lastScrollY: CGFloat?
    /// Measured height of `bottomChrome`, handed to the tab roots so their scroll content clears it.
    @State private var chromeHeight: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appLocked) private var appLocked
    @Environment(BuyingLimitNudgeCenter.self) private var buyingLimitNudge
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @State private var showBuyingLimits = false
    @Namespace private var dockNS

    // End-of-period recap interstitial (see `RecapScheduler` / `RecapBuilder`). The cheap due-check runs
    // on app open once the lock (if any) has cleared; the story loads only when a boundary is due, and
    // is hosted as a full-screen cover over the live shell (the dock stays untouched).
    @AppStorage(SettingsKey.recapEnabled) private var recapEnabled = true
    @AppStorage(SettingsKey.recapFrequency) private var recapFrequencyRaw = RecapFrequency.monthly.rawValue
    @AppStorage(SettingsKey.recapLastShownWeek) private var recapLastShownWeek = ""
    @AppStorage(SettingsKey.recapLastShownMonth) private var recapLastShownMonth = ""
    @State private var recapStory: RecapStory?
    @State private var recapDue: RecapDue?
    @State private var showRecap = false
    @State private var recapChecked = false

    var body: some View {
        Group {
            #if DEBUG
            if hasDebugPreview {
                debugPreviewScreen
            } else {
                mainTabs
            }
            #else
            mainTabs
            #endif
        }
        .fullScreenCover(isPresented: $showScan) { ScanFlowView().coversFloatingDock() }
        .fullScreenCover(isPresented: $showRecap) {
            if let story = recapStory {
                RecapStoryView(story: story, onClose: closeRecap, onSeeDetails: openRecapDetails)
            }
        }
        .task { await maybeShowRecap() }
        .onChange(of: appLocked) { _, locked in
            // Once the lock clears, run the deferred due-check (it was skipped while locked).
            if !locked { Task { await maybeShowRecap() } }
        }
        // The save-time buying-limit nudge floats over the live shell (no scrim) just above the dock —
        // shown wherever the user lands after the scan cover dismisses, so it's never missed. "View
        // limits" opens the Buying limits screen; the receipt is already saved either way.
        .overlay(alignment: .bottom) { nudgeOverlay }
        .sheet(isPresented: $showBuyingLimits) { NavigationStack { BuyingLimitsView().coversFloatingDock() } }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_SCAN"] == "1" { showScan = true }
            if ProcessInfo.processInfo.environment["BL_NUDGE"] == "1", buyingLimitNudge.pending == nil {
                buyingLimitNudge.post(BuyingLimitNudge(title: "Fizzy drinks", emoji: "🥤",
                    countAfter: 4, limitCount: 3, timeframe: .monthly))
            }
            #endif
        }
    }

    /// The floating nudge card, lifted clear of the dock chrome. Padding is tuned so it clears the
    /// custom dock (compact) / tab-bar accessory (regular) without covering it.
    @ViewBuilder
    private var nudgeOverlay: some View {
        if let nudge = buyingLimitNudge.pending {
            BuyingLimitNudgeCard(
                nudge: nudge,
                monthStartDay: monthStartDay,
                onDismiss: { withAnimation(.spring(duration: 0.3)) { buyingLimitNudge.clear() } },
                onView: {
                    buyingLimitNudge.clear()
                    showBuyingLimits = true
                }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, hSize == .compact ? chromeHeight + Dimens.spaceS : 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - End-of-period recap

    /// The cheap due-check (settings + clock, no store) short-circuits the common "nothing due" open;
    /// only when a boundary is due does it load the story off the just-closed period. Runs at most once
    /// per session, and only once the app-lock (if any) has cleared. On a guard-skip (first-run / no
    /// data) it stamps the period(s) shown and shows nothing, so no empty recap appears. Android parity:
    /// `RecapGate` + `RecapViewModel`.
    @MainActor
    private func maybeShowRecap() async {
        #if DEBUG
        // Don't stack the interstitial over a SHOW_SCREEN debug/screenshot screen.
        if hasDebugPreview { return }
        #endif
        guard !recapChecked, !appLocked else { return }
        let ctx = modelContext
        let receipts = (try? ctx.fetch(FetchDescriptor<Receipt>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
        // A store with no receipts at all is a brand-new user (nothing to recap) — or, in DEBUG, sample
        // seeding that hasn't committed yet. Either way don't stamp: a later cold launch re-checks once
        // there's data, so the boundary is never spuriously consumed. With ANY receipts we proceed and
        // stamp-on-skip exactly like Android.
        guard !receipts.isEmpty else { return }
        recapChecked = true
        let frequency = RecapFrequency(rawValue: recapFrequencyRaw) ?? .monthly
        guard let due = RecapScheduler.due(
            enabled: recapEnabled, frequency: frequency,
            lastShownWeek: recapLastShownWeek, lastShownMonth: recapLastShownMonth,
            today: .now, startDay: monthStartDay, firstWeekday: BuyingLimitCounter.localeFirstWeekday()
        ) else { return }

        if let story = buildRecapStory(due.show, receipts: receipts, context: ctx) {
            recapStory = story
            recapDue = due
            showRecap = true
        } else {
            // Guard skipped (under the receipt floor / no period spend): stamp so it isn't re-checked.
            stampRecapShown(due)
        }
    }

    @MainActor
    private func buildRecapStory(_ kind: RecapKind, receipts: [Receipt], context ctx: ModelContext) -> RecapStory? {
        let budgets = (try? ctx.fetch(FetchDescriptor<Budget>())) ?? []
        let recurring = (try? ctx.fetch(FetchDescriptor<Recurring>())) ?? []
        let goals = (try? ctx.fetch(FetchDescriptor<SavingsGoal>())) ?? []
        let contributions = (try? ctx.fetch(FetchDescriptor<SavingsContribution>())) ?? []
        let ignored = (try? ctx.fetch(FetchDescriptor<IgnoredSubscription>())) ?? []
        let limits = (try? ctx.fetch(FetchDescriptor<BuyingLimit>())) ?? []
        return RecapBuilder.build(kind: kind, offset: -1, receipts: receipts, budgets: budgets,
                                  recurring: recurring, goals: goals, contributions: contributions,
                                  ignoredSubs: Set(ignored.map(\.merchant)), limits: limits,
                                  monthStartDay: monthStartDay)
    }

    /// Stamps the due period(s) as shown so a period's recap fires at most once. Android: `setRecapShown`.
    private func stampRecapShown(_ due: RecapDue) {
        if let week = due.markWeek { recapLastShownWeek = week }
        if let month = due.markMonth { recapLastShownMonth = month }
    }

    private func closeRecap() {
        if let due = recapDue { stampRecapShown(due) }
        showRecap = false
    }

    /// "See details" on the last card exits to Insights; the recap is stamped either way.
    private func openRecapDetails() {
        if let due = recapDue { stampRecapShown(due) }
        showRecap = false
        tab = .insights
    }

    // MARK: - Adaptive tab bar

    /// iPhone: custom glass dock + the Scan pill floating 10pt above it (mockup bottom chrome).
    /// iPad: floating top tab bar / sidebar; Scan rides the tab-bar bottom accessory.
    @ViewBuilder
    private var mainTabs: some View {
        Group {
            if hSize == .compact {
                compactShell
            } else {
                styledTabView.tabViewBottomAccessory { scanAccessory }
            }
        }
        // Let tab-root views (Home's "See All" links) switch tabs, matching Android's card navigation.
        .environment(\.selectTab) { tab = $0 }
    }

    private var styledTabView: some View {
        TabView(selection: $tab) {
            Tab(AppTab.home.title, systemImage: AppTab.home.symbol, value: AppTab.home) {
                HomeView()
            }
            Tab(AppTab.history.title, systemImage: AppTab.history.symbol, value: AppTab.history) {
                HistoryView()
            }
            Tab(AppTab.insights.title, systemImage: AppTab.insights.symbol, value: AppTab.insights) {
                InsightsView()
            }
            Tab(AppTab.budget.title, systemImage: AppTab.budget.symbol, value: AppTab.budget) {
                BudgetView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown) // Liquid Glass: chrome recedes as content scrolls up
    }

    // MARK: - iPhone custom bottom chrome

    /// All four screens stay alive in a ZStack (so each keeps its scroll position and state, like
    /// `TabView` would) with only the selected one visible; the glass dock rides a bottom
    /// safe-area inset so content scrolls under it.
    private var compactShell: some View {
        ZStack {
            tabScreen(.home) { HomeView() }
            tabScreen(.history) { HistoryView() }
            tabScreen(.insights) { InsightsView() }
            tabScreen(.budget) { BudgetView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomChrome }
        .environment(\.dockScrollReporter, handleDockScroll)
        .environment(\.dockChromeHeight, chromeHeight)
        .onChange(of: tab) {
            lastScrollY = nil // the new tab's offset is unrelated — don't read it as a scroll
            setDock(hidden: false)
        }
    }

    // MARK: Scroll-driven hide (custom-chrome stand-in for tabBarMinimizeBehavior)

    /// Direction detection over the active tab's scroll offset: hide on a downward scroll, reveal
    /// on an upward one, and always reveal near the top (covers rubber-band overshoot too).
    private func handleDockScroll(_ y: CGFloat) {
        defer { lastScrollY = y }
        guard let last = lastScrollY else { return }
        let delta = y - last
        if y <= 8 {
            setDock(hidden: false)
        } else if delta > 3 {
            setDock(hidden: true)
        } else if delta < -3 {
            setDock(hidden: false)
        }
    }

    private func setDock(hidden: Bool) {
        guard dockHidden != hidden else { return }
        withAnimation(.spring(duration: 0.35)) { dockHidden = hidden }
    }

    private func tabScreen<Content: View>(_ t: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .opacity(tab == t ? 1 : 0)
            .allowsHitTesting(tab == t)
            .accessibilityHidden(tab != t)
    }

    /// The dock, with the Scan pill stacked 10pt above it (mockup spacing). Both sit in the layout
    /// so the bottom safe-area inset covers the *whole* chrome: scrolled to the end, a page's last
    /// row clears the pill as well as the dock instead of resting under them.
    /// While scrolling down the dock slides off the bottom edge and the pill drops into its slot
    /// (the primary action stays reachable, like the system accessory during tab-bar minimize);
    /// `offset` doesn't reflow layout, so the safe-area inset — and the content under it — hold still.
    private var bottomChrome: some View {
        VStack(spacing: 10) {
            Button { showScan = true } label: { scanPill }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11y.Tab.scan)
                .offset(y: dockHidden ? 66 : 0) // down by dock height + the 10pt gap
            glassDock
                .offset(y: dockHidden ? 100 : 0) // 56pt dock + 34pt home area → fully off-screen
        }
        // Unoffset height (offsets don't reflow), so this is the space a tab root must reserve.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chromeHeight = $0 }
        .padding(.horizontal, 14)
    }

    /// The mockup's floating tab dock: a 56pt glass capsule (chrome wash over blur, white-alpha
    /// rim + top specular, deep drop shadow) holding four equal items; the selected one sits in a
    /// violet `tint-bg` pill that slides between tabs.
    private var glassDock: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases, id: \.self) { dockItem($0) }
        }
        .padding(5)
        .frame(height: 56)
        .background(Palette.matPill, in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.matPillBorder, lineWidth: 0.5))
        .overlay(Capsule().strokeBorder(
            LinearGradient(stops: [.init(color: Palette.glassSpecular, location: 0),
                                   .init(color: .clear, location: 0.35)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 1))
        .shadow(color: Palette.dropShadow, radius: 24, y: 16)
        .shadow(color: Palette.dropShadowSoft, radius: 7, y: 4)
    }

    private func dockItem(_ t: AppTab) -> some View {
        let selected = tab == t
        return Button {
            withAnimation(.snappy(duration: 0.25)) { tab = t }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: t.symbol).font(.system(size: 18, weight: .medium))
                Text(t.title).font(.system(size: 10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? Palette.tint : Palette.secondaryLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if selected {
                    let pill = RoundedRectangle(cornerRadius: 22, style: .continuous)
                    pill.fill(Palette.tintSoft)
                        // mockup: inset 0 1px 1px -.5px white .5, inset 0 0 0 .5px white .12
                        .overlay(pill.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                        .overlay(pill.strokeBorder(
                            LinearGradient(stops: [.init(color: .white.opacity(0.5), location: 0),
                                                   .init(color: .clear, location: 0.3)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1))
                        .matchedGeometryEffect(id: "dockSelection", in: dockNS)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityIdentifier(t.a11yIdentifier)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// iPad accessory variant — same pill, no floating offset (the accessory positions it).
    private var scanAccessory: some View {
        Button { showScan = true } label: { scanPill }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11y.Tab.scan)
    }

    private var scanPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "camera.fill")
            Text("Scan receipt")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 26).padding(.vertical, 14)
        .background(Palette.scanCTA, in: Capsule())
        .overlay( // glossy top sheen
            Capsule()
                .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.06), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        .shadow(color: Palette.scanCTA.opacity(0.5), radius: 16, y: 7)
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    #if DEBUG
    /// Lets screenshot tooling jump straight to a pushed screen (Account/Paywall) via launch env.
    @ViewBuilder
    private var debugPreviewScreen: some View {
        switch ProcessInfo.processInfo.environment["SHOW_SCREEN"] {
        case "account": NavigationStack { AccountView() }
        case "paywall": NavigationStack { PaywallView() }
        case "receipt": NavigationStack { DebugFirstReceiptDetail() }
        case "category": DebugCategoryPicker()
        case "review": DebugReviewScreen()
        case "support": NavigationStack { SupportAboutView() }
        case "widgets": NavigationStack { WidgetsView() }
        case "lock": LockScreenView(onUnlocked: {})
        case "memory": DebugMemorySheet()
        case "buyinglimits": NavigationStack { DebugBuyingLimits() }
        case "recap": RecapStoryView(story: .debugMonthlySample(), onClose: {}, onSeeDetails: {})
        default: EmptyView().hidden()
        }
    }

    private var hasDebugPreview: Bool {
        ["account", "paywall", "receipt", "category", "review",
         "notifications", "support", "widgets", "lock", "memory", "buyinglimits", "recap"]
            .contains(ProcessInfo.processInfo.environment["SHOW_SCREEN"] ?? "")
    }
    #endif
}

#if DEBUG
/// Shows the most recent receipt's detail — used only by the SHOW_SCREEN=receipt screenshot hook.
private struct DebugFirstReceiptDetail: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    var body: some View {
        if let r = receipts.first {
            ReceiptDetailView(receipt: r)
        } else {
            Text("No receipts")
        }
    }
}

/// Shows the category picker for the SHOW_SCREEN=category screenshot hook.
private struct DebugCategoryPicker: View {
    @State private var selection = "Bakery"
    var body: some View { CategoryPickerSheet(selection: $selection) }
}

/// Seeded Review screen for the SHOW_SCREEN=review screenshot hook — the scan flow can't reach
/// Review without a real extraction, so screenshots go through this instead.
private struct DebugReviewScreen: View {
    @State private var draft: ReceiptDraft = {
        let d = ReceiptDraft()
        d.store = "Kaufland"
        d.discount = 3.20
        d.items = [
            DraftItem(name: "Bananas", quantity: 1, price: 2.10, category: "Fruits & Vegetables"),
            DraftItem(name: "Wholegrain bread", quantity: 1, price: 1.89, category: "Bakery"),
            DraftItem(name: "Gouda cheese 400g", quantity: 1, price: 3.49, category: "Dairy"),
            DraftItem(name: "Milk 1L", quantity: 1, price: 1.09, category: "Dairy"),
        ]
        return d
    }()
    var body: some View { ReviewView(draft: draft, onCancel: {}, onSave: {}) }
}
#endif

#if DEBUG
/// Hosts the Category Memory sheet for the SHOW_SCREEN=memory screenshot hook.
private struct DebugMemorySheet: View {
    @State private var shown = true
    var body: some View {
        Color.clear.sheet(isPresented: $shown) {
            CategoryMemorySheet(itemName: "Wholegrain bread", oldCategory: "Snacks & Sweets",
                                newCategory: "Bakery") { _ in }
        }
    }
}
#endif

#if DEBUG
/// Seeds three buying limits (on-track / at-limit / over) plus matching line items, for the
/// SHOW_SCREEN=buyinglimits screenshot hook — the screen derives its counts off real line items.
private struct DebugBuyingLimits: View {
    @Environment(\.modelContext) private var context
    @Query private var limits: [BuyingLimit]

    var body: some View {
        BuyingLimitsView().onAppear(perform: seed)
    }

    private func seed() {
        guard limits.isEmpty else { return }
        let now = Date()
        let receipt = Receipt(createdAt: now, store: "Debug", date: now)
        context.insert(receipt)
        for (name, qty) in [("Red Bull 250ml", 1), ("Coffee latte", 5),
                            ("Coca-Cola 1L", 2), ("Fanta Orange", 2)] {
            let li = LineItem(name: name, createdAt: now, price: 1, quantity: qty)
            li.receipt = receipt
            context.insert(li)
        }
        context.insert(BuyingLimit(emoji: "⚡", label: "Energy drinks",
                                   keywords: ["red bull", "monster"], timeframe: .weekly, count: 2))
        context.insert(BuyingLimit(emoji: "☕", label: "Takeaway coffee",
                                   keywords: ["coffee"], timeframe: .weekly, count: 5))
        context.insert(BuyingLimit(emoji: "🥤", label: "Fizzy drinks",
                                   keywords: ["coke", "cola", "fanta"], timeframe: .monthly, count: 3))
        try? context.save()
    }
}
#endif

/// Temporary stand-in for tabs not yet built.
struct PlaceholderScreen: View {
    let title: String
    let symbol: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text("Coming soon")
            }
            .navigationTitle(title)
            .background(Palette.groupedBackground)
        }
    }
}
