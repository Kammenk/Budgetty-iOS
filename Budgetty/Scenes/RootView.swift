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
    @Namespace private var dockNS

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
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_SCAN"] == "1" { showScan = true }
            #endif
        }
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
        case "lock": BiometricLockView(onUnlock: {})
        case "memory": DebugMemorySheet()
        default: EmptyView().hidden()
        }
    }

    private var hasDebugPreview: Bool {
        ["account", "paywall", "receipt", "category", "review",
         "notifications", "support", "widgets", "lock", "memory"]
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
