//
//  RootView.swift
//  Budgetty
//
//  App shell. Compact width (iPhone) → custom bottom tab bar with a raised center Scan button.
//  Regular width (iPad) → NavigationSplitView sidebar. Scan is presented as a sheet from either.
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
    @Environment(\.horizontalSizeClass) private var hSize
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
            } else if hSize == .regular {
                splitLayout
            } else {
                compactLayout
            }
            #else
            if hSize == .regular { splitLayout } else { compactLayout }
            #endif
        }
        .fullScreenCover(isPresented: $showScan) { ScanFlowView() }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_SCAN"] == "1" { showScan = true }
            #endif
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        screen(for: tab)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BudgettyTabBar(tab: $tab, onScan: { showScan = true })
            }
    }

    // MARK: - iPad

    private var splitLayout: some View {
        NavigationSplitView {
            List {
                Section {
                    ForEach(AppTab.allCases, id: \.self) { t in
                        Button { tab = t } label: {
                            Label(t.title, systemImage: t.symbol)
                                .foregroundStyle(tab == t ? Palette.tint : Palette.label)
                                .fontWeight(tab == t ? .semibold : .regular)
                        }
                        .listRowBackground(tab == t ? Palette.tintSoft : Color.clear)
                    }
                    Button { showScan = true } label: {
                        Label("Scan", systemImage: "camera.fill")
                    }
                }
                Section {
                    SidebarSummary()
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Budgetty")
        } detail: {
            screen(for: tab)
        }
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

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .history: HistoryView()
        case .insights: InsightsView()
        case .budget: BudgetView()
        }
    }
}

/// iPad sidebar spending summary (matches the Home iPad mockup): month total + Monthly/Weekly budget.
private struct SidebarSummary: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]

    private var monthSpent: Decimal {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }
    private var weekSpent: Decimal {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }
    private func budget(_ key: String) -> Decimal? { budgets.first { $0.key == key }?.amount }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(HomeView.monthLabel(.now)).font(.caption).foregroundStyle(.white.opacity(0.75))
                Text(monthSpent.formatMoney()).font(.title2).fontWeight(.bold).foregroundStyle(.white)
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let m = budget(Budget.monthlyKey) {
                    let frac = HomeView.fraction(monthSpent, of: m)
                    ProgressBarView(fraction: frac, color: .white.opacity(0.85), height: 5, track: .white.opacity(0.25))
                        .padding(.top, 6)
                    Text("\(Int(frac * 100))% of monthly").font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if budget(Budget.monthlyKey) != nil || budget(Budget.weeklyKey) != nil {
                VStack(spacing: 10) {
                    if let m = budget(Budget.monthlyKey) { miniRow("Monthly", monthSpent, m) }
                    if let w = budget(Budget.weeklyKey) { miniRow("Weekly", weekSpent, w) }
                }
                .padding(12)
                .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func miniRow(_ title: String, _ spent: Decimal, _ limit: Decimal) -> some View {
        let frac = HomeView.fraction(spent, of: limit)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        return VStack(spacing: 5) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text("\(Int(frac * 100))%").font(.caption2).fontWeight(.semibold).foregroundStyle(color)
            }
            ProgressBarView(fraction: frac, color: color, height: 5)
        }
    }
}

/// The custom bottom tab bar with a raised, tinted center Scan button.
struct BudgettyTabBar: View {
    @Binding var tab: AppTab
    var onScan: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.history)
            scanButton
            item(.insights)
            item(.budget)
        }
        .padding(.top, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Divider(), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func item(_ t: AppTab) -> some View {
        Button {
            tab = t
        } label: {
            VStack(spacing: 2) {
                Image(systemName: t.symbol).font(.system(size: 20))
                Text(t.title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tab == t ? Palette.tint : Palette.secondaryLabel)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var scanButton: some View {
        Button(action: onScan) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Palette.tint)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 19)).foregroundStyle(.white)
                    )
                    .shadow(color: Palette.tint.opacity(0.45), radius: 6, y: 3)
                    .offset(y: -12)
                Text("Scan").font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.secondaryLabel)
                    .offset(y: -8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
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

