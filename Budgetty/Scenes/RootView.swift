//
//  RootView.swift
//  Budgetty
//
//  App shell. `TabView` + `.tabViewStyle(.sidebarAdaptable)` — Apple's adaptive tab-app pattern:
//  iPhone shows the system bottom tab bar; iPad shows the floating top tab bar that expands into a
//  plain-label sidebar. Scan is a primary action in the tab bar's bottom accessory (not a tab).
//  Presented as a full-screen cover from anywhere.
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

    /// iPhone: bottom tab bar. iPad: floating top tab bar that expands to a plain-label sidebar.
    private var mainTabs: some View {
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
        .tabViewBottomAccessory { scanAccessory }
    }

    /// The persistent "Scan receipt" action shown above the tab bar (bottom accessory).
    private var scanAccessory: some View {
        Button { showScan = true } label: {
            Label("Scan receipt", systemImage: "camera.fill")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(Palette.tint)
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
