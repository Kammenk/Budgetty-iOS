//
//  HistoryView.swift
//  Budgetty
//
//  History tab from the iOS mockup: a segmented control over three views — Receipts (day-grouped
//  receipt cards), Items (day-grouped line items), and Budgets (per-category plan snapshot) — under
//  a search field and filter chips. All driven by SwiftData.
//

import SwiftUI
import SwiftData

enum HistoryMode: String, CaseIterable, Identifiable {
    case receipts = "Receipts", items = "Items", budgets = "Budgets"
    var id: String { rawValue }
}

struct HistoryView: View {
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]

    @State private var mode: HistoryMode = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HISTORY_TAB"],
           let m = HistoryMode(rawValue: raw.capitalized) { return m }
        #endif
        return .receipts
    }()

    @State private var search = ""
    @State private var sort: HistorySort = .newest
    @State private var dateRange: ClosedRange<Date>?
    @State private var priceLo: Double?
    @State private var priceHi: Double?
    @State private var categoryFilter: Set<String> = []
    @State private var showDate = false
    @State private var showPrice = false
    @State private var showCategory = false
    /// Selected receipt in the iPad-landscape two-pane detail view.
    @State private var selectedID: PersistentIdentifier?

    var body: some View {
        GeometryReader { geo in
            // Two-pane master–detail only when there's landscape-width room (iPad landscape / wide
            // Split View); iPhone and iPad portrait keep the single readable column with push nav.
            let twoPane = geo.size.width >= 820 && geo.size.width > geo.size.height
            Group {
                if twoPane { twoPaneLayout } else { singleColumn }
            }
            .sheet(isPresented: $showDate) { DateRangeSheet(range: $dateRange) }
            .sheet(isPresented: $showPrice) { PriceRangeSheet(lower: $priceLo, upper: $priceHi, bound: priceBound) }
            .sheet(isPresented: $showCategory) { CategoryFilterSheet(selected: $categoryFilter) }
        }
    }

    // MARK: - Single column (iPhone / iPad portrait)

    private var singleColumn: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header(showTitle: true)
                    .adaptiveReadableWidth()
                    .background { headerGlass }
                ScrollView {
                    tabContent(selecting: false)
                        .adaptiveReadableWidth()
                }
                .reportsDockScroll()
            }
            .screenCanvas()
            .navigationTitle("History")
            // The title lives INSIDE the glass header panel (with the search field, segmented
            // toggle and chips all on one material), which the system large-title bar can't do —
            // same pattern as Home's custom header row.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The fixed header's Liquid Glass panel: a `matHeader` wash over blur so the canvas's ambient
    /// glows shimmer through (the mockup's soft violet gradient), closed by a `sep2` hairline.
    private var headerGlass: some View {
        Rectangle().fill(.ultraThinMaterial)
            .overlay(Palette.matHeader)
            .overlay(Palette.headerAmbient)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.separatorStrong).frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .top)
    }

    // MARK: - Two-pane master–detail (iPad landscape)

    private var twoPaneLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(showTitle: false)
                    .overlay(Divider(), alignment: .bottom)
                ScrollView { tabContent(selecting: true) }
            }
            .frame(width: 390)

            Divider()

            Group {
                if let receipt = selectedReceipt {
                    NavigationStack { ReceiptDetailView(receipt: receipt) }
                } else {
                    detailPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .screenCanvas()
        .onAppear {
            if selectedID == nil { selectedID = filteredReceipts.first?.persistentModelID }
        }
    }

    private var detailPlaceholder: some View {
        ContentUnavailableView("Select a receipt",
                               systemImage: "doc.text",
                               description: Text("Choose a receipt to see its details."))
    }

    private var selectedReceipt: Receipt? {
        guard let id = selectedID else { return nil }
        return receipts.first { $0.persistentModelID == id }
    }

    @ViewBuilder
    private func tabContent(selecting: Bool) -> some View {
        switch mode {
        case .receipts: receiptsTab(selecting: selecting)
        case .items: itemsTab(selecting: selecting)
        case .budgets: budgetsTab
        }
    }

    // MARK: - Header (search + segmented + chips)

    private func header(showTitle: Bool) -> some View {
        VStack(spacing: 10) {
            if showTitle {
                HStack {
                    Text("History").font(.largeTitle).fontWeight(.bold)
                        .foregroundStyle(Palette.label)
                    Spacer()
                }
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondaryLabel)
                TextField("Search", text: $search).font(.subheadline)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.tertiaryLabel)
                    }
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Palette.matControl, in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.matControlBorder, lineWidth: 0.5))
            .shadow(color: Color(argb: 0x0F140A32), radius: 5, y: 2)

            GlassSegmentedControl(options: Array(HistoryMode.allCases), selection: $mode) {
                $0.rawValue
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    if hasActiveFilters {
                        Button { clearFilters() } label: { chipLabel("Clear", active: true, icon: "xmark") }
                    }
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(HistorySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: { chipLabel("Sort", active: false, trailing: "chevron.down") }
                    Button { showDate = true } label: {
                        chipLabel("Date", active: dateRange != nil, trailing: "chevron.down")
                    }
                    Button { showCategory = true } label: {
                        chipLabel(categoryFilter.isEmpty ? "Category" : "Category (\(categoryFilter.count))",
                                  active: !categoryFilter.isEmpty, trailing: "chevron.down")
                    }
                    Button { showPrice = true } label: {
                        chipLabel("Price", active: priceLo != nil || priceHi != nil, trailing: "chevron.down")
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 4)
    }

    private func chipLabel(_ title: String, active: Bool, icon: String? = nil, trailing: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(title)
            if let trailing { Image(systemName: trailing).font(.system(size: 9, weight: .semibold)) }
        }
        .font(.caption).fontWeight(active ? .semibold : .medium)
        .foregroundStyle(active ? .white : Palette.label)
        .padding(.horizontal, 13).padding(.vertical, 6)
        .background {
            if active {
                Capsule().fill(Palette.tint)
                    .overlay(Capsule().strokeBorder(
                        LinearGradient(stops: [.init(color: .white.opacity(0.55), location: 0),
                                               .init(color: .clear, location: 0.5)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
                    .shadow(color: Color(argb: 0x4D6042B4), radius: 4, y: 2)
            } else {
                Capsule().fill(Palette.matControl)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.matControlBorder, lineWidth: 0.5))
            }
        }
    }

    // MARK: - Filtering

    private var hasActiveFilters: Bool {
        dateRange != nil || priceLo != nil || priceHi != nil || !categoryFilter.isEmpty || !search.isEmpty
    }
    private func clearFilters() {
        dateRange = nil; priceLo = nil; priceHi = nil; categoryFilter = []; search = ""
    }
    private var priceBound: Double {
        max(100, (receipts.map { ($0.paidTotal as NSDecimalNumber).doubleValue }.max() ?? 100).rounded(.up))
    }

    private func inDate(_ d: Date) -> Bool {
        guard let r = dateRange else { return true }
        let day = Calendar.current.startOfDay(for: d)
        return day >= Calendar.current.startOfDay(for: r.lowerBound)
            && day <= Calendar.current.startOfDay(for: r.upperBound)
    }
    private func inPrice(_ v: Decimal) -> Bool {
        let d = (v as NSDecimalNumber).doubleValue
        if let lo = priceLo, d < lo { return false }
        if let hi = priceHi, d > hi { return false }
        return true
    }
    private func inCategory(_ cat: String) -> Bool {
        categoryFilter.isEmpty || categoryFilter.contains(Categories.groupOf(cat))
    }

    private var filteredReceipts: [Receipt] {
        let base = receipts.filter { r in
            inDate(r.createdAt) && inPrice(r.paidTotal)
            && (search.isEmpty || r.store.localizedCaseInsensitiveContains(search)
                || r.items.contains { $0.name.localizedCaseInsensitiveContains(search) })
            && (categoryFilter.isEmpty || r.items.contains { inCategory($0.category) })
        }
        switch sort {
        case .newest: return base.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return base.sorted { $0.createdAt < $1.createdAt }
        case .priceHigh: return base.sorted { $0.paidTotal > $1.paidTotal }
        case .priceLow: return base.sorted { $0.paidTotal < $1.paidTotal }
        }
    }

    private var filteredItems: [LineItem] {
        let base = allItems.filter { it in
            inDate(it.createdAt) && inPrice(it.lineTotal) && inCategory(it.category)
            && (search.isEmpty || it.name.localizedCaseInsensitiveContains(search)
                || (it.receipt?.store.localizedCaseInsensitiveContains(search) ?? false))
        }
        switch sort {
        case .newest: return base.sorted { $0.createdAt > $1.createdAt }
        case .oldest: return base.sorted { $0.createdAt < $1.createdAt }
        case .priceHigh: return base.sorted { $0.lineTotal > $1.lineTotal }
        case .priceLow: return base.sorted { $0.lineTotal < $1.lineTotal }
        }
    }

    // MARK: - Receipts tab

    private func receiptsTab(selecting: Bool) -> some View {
        Group {
            if filteredReceipts.isEmpty {
                HistoryEmpty(symbol: "receipt", text: hasActiveFilters ? "No matching receipts" : "No receipts yet")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(dayGroups(of: filteredReceipts, date: \.createdAt), id: \.date) { group in
                        sectionHeader(DayFormat.label(group.date),
                                      trailing: group.items.reduce(Decimal.zero) { $0 + $1.paidTotal }.formatMoney())
                        card {
                            ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { idx, r in
                                receiptRow(r, selecting: selecting)
                                if idx < group.items.count - 1 { Divider().padding(.leading, 64) }
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    /// A receipt row: pushes detail in single-column mode, or selects the two-pane detail (with a
    /// tint-wash highlight) in two-pane mode.
    @ViewBuilder
    private func receiptRow(_ r: Receipt, selecting: Bool) -> some View {
        if selecting {
            Button { selectedID = r.persistentModelID } label: { ReceiptRowView(receipt: r) }
                .buttonStyle(.plain)
                .background(selectedID == r.persistentModelID ? Palette.tintSoft : Color.clear)
        } else {
            NavigationLink { ReceiptDetailView(receipt: r) } label: { ReceiptRowView(receipt: r) }
                .buttonStyle(.plain)
        }
    }

    // MARK: - Items tab

    private var allItems: [LineItem] { receipts.flatMap(\.items) }

    private func itemsTab(selecting: Bool) -> some View {
        Group {
            if filteredItems.isEmpty {
                HistoryEmpty(symbol: "list.bullet", text: hasActiveFilters ? "No matching items" : "No items yet")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(dayGroups(of: filteredItems, date: \.createdAt), id: \.date) { group in
                        sectionHeader(DayFormat.label(group.date),
                                      trailing: group.items.reduce(Decimal.zero) { $0 + $1.lineTotal }.formatMoney())
                        card {
                            ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { idx, item in
                                if selecting {
                                    // Tapping an item opens its parent receipt in the detail pane.
                                    Button { selectedID = item.receipt?.persistentModelID } label: { itemRow(item) }
                                        .buttonStyle(.plain)
                                } else {
                                    itemRow(item)
                                }
                                if idx < group.items.count - 1 { Divider().padding(.leading, 58) }
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func itemRow(_ item: LineItem) -> some View {
        HStack(spacing: 12) {
            CategoryTile(category: item.category)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.subheadline).foregroundStyle(Palette.label)
                Text("\(item.category) · \(item.receipt?.store ?? "")")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.lineTotal.formatMoney()).font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Palette.label)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Budgets tab

    private var categoryBudgets: [Budget] {
        budgets.filter { $0.key.hasPrefix("CAT:") }
            .sorted { $0.key < $1.key }
    }

    private func monthSpend(forCategory cat: String) -> Decimal {
        let cal = Calendar.current
        return allItems
            .filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
            .filter { $0.category.caseInsensitiveCompare(cat) == .orderedSame
                || Categories.groupOf($0.category).caseInsensitiveCompare(cat) == .orderedSame }
            .reduce(.zero) { $0 + $1.lineTotal }
    }

    private var budgetsTab: some View {
        Group {
            if categoryBudgets.isEmpty {
                HistoryEmpty(symbol: "chart.pie", text: "No category budgets set")
            } else {
                let monthTotal = categoryBudgets.reduce(Decimal.zero) { $0 + monthSpend(forCategory: String($1.key.dropFirst(4))) }
                LazyVStack(spacing: 0) {
                    sectionHeader("\(HomeView.monthLabel(.now)) · \(monthTotal.formatMoney()) spent", trailing: nil)
                    card {
                        ForEach(Array(categoryBudgets.enumerated()), id: \.element.persistentModelID) { idx, b in
                            let cat = String(b.key.dropFirst(4))
                            budgetRow(category: cat, spent: monthSpend(forCategory: cat), limit: b.amount)
                            if idx < categoryBudgets.count - 1 { Divider().padding(.leading, 60) }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func budgetRow(category: String, spent: Decimal, limit: Decimal) -> some View {
        let frac = HomeView.fraction(spent, of: limit)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        return HStack(spacing: 12) {
            CategoryTile(category: category, size: 32, soft: true)
            VStack(spacing: 5) {
                HStack {
                    Text(category).font(.subheadline).foregroundStyle(Palette.label)
                    Spacer()
                    Text("\(spent.formatMoney()) / \(limit.formatMoney())")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
                }
                ProgressBarView(fraction: frac, color: color, height: 5)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - Shared building blocks

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            Text(title).font(.caption).fontWeight(.semibold).textCase(.uppercase)
                .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(.horizontal, 36).padding(.top, 14).padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .contentCard(cornerRadius: 14)
            .padding(.horizontal, 20)
    }

    // MARK: - Day grouping

    private struct DayGroup<T> { let date: Date; let items: [T] }

    private func dayGroups<T>(of source: [T], date: KeyPath<T, Date>) -> [DayGroup<T>] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: source) { cal.startOfDay(for: $0[keyPath: date]) }
        return grouped.keys.sorted(by: >).map { DayGroup(date: $0, items: grouped[$0]!) }
    }
}

/// Relative day-section label: "Today · 5 Jul", "Yesterday · 4 Jul", "Wed · 2 Jul".
enum DayFormat {
    static func label(_ date: Date) -> String {
        let cal = Calendar.current
        let short: String = { let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: date) }()
        if cal.isDateInToday(date) { return "Today · \(short)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(short)" }
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        return "\(wd.string(from: date)) · \(short)"
    }
}

private struct HistoryEmpty: View {
    let symbol: String
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(Palette.tertiaryLabel)
            Text(text).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.top, 80)
    }
}
