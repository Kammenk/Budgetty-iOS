//
//  RootView.swift
//  Budgetty
//
//  App shell. `TabView` + `.tabViewStyle(.sidebarAdaptable)` — Apple's adaptive tab-app pattern:
//  iPhone shows the system bottom tab bar (kept 100% native per user preference: it recedes on
//  scroll via `tabBarMinimizeBehavior`, and its glass can't be tinted — it ignores both
//  `UITabBarAppearance` and `.toolbarBackground`, pixel-diff-proven, so the mockup look comes from
//  the `screenCanvas()` bottom scrim it samples); iPad shows the floating top tab bar that expands
//  into a plain-label sidebar. Scan is a floating pill just above the iPhone tab bar (mockup's
//  10pt gap) / the tab bar's bottom accessory on iPad. Presented as a full-screen cover.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable, CaseIterable {
    case home, history, insights, budget

    var title: String {
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
    @Environment(\.horizontalSizeClass) private var hSize

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
        .fullScreenCover(isPresented: $showScan) { ScanFlowView() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_SCAN"] == "1" { showScan = true }
            #endif
        }
    }

    // MARK: - Adaptive tab bar

    /// iPhone: bottom tab bar + a floating Scan pill overlaid above it (mockup's standalone CTA).
    /// iPad: floating top tab bar / sidebar; Scan rides the tab-bar bottom accessory.
    @ViewBuilder
    private var mainTabs: some View {
        if hSize == .compact {
            styledTabView.overlay(alignment: .bottom) { scanFloating }
        } else {
            styledTabView.tabViewBottomAccessory { scanAccessory }
        }
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

    /// Floating "Scan receipt" CTA above the iPhone tab bar — a solid rich-violet capsule with a
    /// glossy top sheen and a violet drop shadow (mockup `--lg-cta` / `--lg-sheen`), not translucent
    /// glass (which washed the color out). Sits the mockup's 10pt above the expanded tab bar.
    private var scanFloating: some View {
        Button { showScan = true } label: { scanPill }
            .buttonStyle(.plain)
            // Pixel-measured: the overlay anchors 34pt above the screen bottom and the expanded
            // floating tab bar's top edge sits at 49pt, so 59 puts the pill the mockup's 10pt
            // above the bar. Revisit if the system bar's metrics change.
            .padding(.bottom, 59)
    }

    /// iPad accessory variant — same pill, no floating offset (the accessory positions it).
    private var scanAccessory: some View {
        Button { showScan = true } label: { scanPill }
            .buttonStyle(.plain)
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
        default: EmptyView().hidden()
        }
    }

    private var hasDebugPreview: Bool {
        ["account", "paywall", "receipt", "category"].contains(ProcessInfo.processInfo.environment["SHOW_SCREEN"] ?? "")
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
