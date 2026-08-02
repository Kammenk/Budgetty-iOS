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
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]
    @Environment(\.selectTab) private var selectTab
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue

    private var dateFormat: DateFormatOption { DateFormatOption(rawValue: dateFormatRaw) ?? .system }

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
    // Rows tapped open in single-column mode (keyed by SwiftData id): receipts reveal their top items,
    // items reveal that product's price history.
    @State private var expandedReceipts: Set<PersistentIdentifier> = []
    @State private var expandedItems: Set<PersistentIdentifier> = []

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
                .underFloatingDock()
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
            // Search + filters apply to receipts/items only; the Budgets tab is a read-only plan
            // snapshot (not searchable or time-scoped), so both are hidden there — matching Android.
            if mode != .budgets {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondaryLabel)
                    TextField("Search", text: $search).font(.subheadline)
                        .accessibilityIdentifier(A11y.History.search)
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
            }

            GlassSegmentedControl(options: Array(HistoryMode.allCases), selection: $mode) {
                LocalizedStringKey($0.rawValue)
            }
            .accessibilityIdentifier(A11y.History.modeToggle)

            if mode != .budgets {
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
        }
        .padding(.horizontal, 20).padding(.bottom, 12).padding(.top, 4)
    }

    private func chipLabel(_ title: LocalizedStringKey, active: Bool, icon: String? = nil, trailing: String? = nil) -> some View {
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
                let maxByMonth = monthMax(filteredReceipts, date: \.createdAt) { $0.paidTotal }
                LazyVStack(spacing: 0) {
                    if let summary = monthSummary(filteredReceipts, date: \.createdAt, amount: { $0.paidTotal }) {
                        summaryStrip(summary, countText: receiptCountLabel(summary.count))
                    }
                    ForEach(dayGroups(of: filteredReceipts, date: \.createdAt), id: \.date) { group in
                        sectionHeader(DayFormat.label(group.date, dateFormat),
                                      trailing: group.items.reduce(Decimal.zero) { $0 + $1.paidTotal }.formatMoney())
                        card {
                            ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { idx, r in
                                let open = !selecting && expandedReceipts.contains(r.persistentModelID)
                                VStack(spacing: 0) {
                                    receiptRow(r, selecting: selecting, expanded: open,
                                               fraction: fraction(r.paidTotal, maxByMonth[monthKey(r.createdAt)]))
                                    if open { receiptExpansion(r) }
                                }
                                if idx < group.items.count - 1 { Divider().padding(.leading, 64) }
                            }
                        }
                    }
                }
                .accessibilityIdentifier(A11y.History.receiptsList)
                .padding(.bottom, 24)
            }
        }
    }

    /// A receipt row. Two-pane mode selects the detail pane (tint-wash highlight). Single-column mode
    /// expands the receipt's top items in place — an "Open receipt" link still pushes the full detail —
    /// with a magnitude bar underneath showing the receipt's share of the month's biggest.
    @ViewBuilder
    private func receiptRow(_ r: Receipt, selecting: Bool, expanded: Bool, fraction: Double) -> some View {
        VStack(spacing: 0) {
            if selecting {
                Button { selectedID = r.persistentModelID } label: { ReceiptRowView(receipt: r) }
                    .buttonStyle(.plain)
                    .background(selectedID == r.persistentModelID ? Palette.tintSoft : Color.clear)
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        if expandedReceipts.contains(r.persistentModelID) { expandedReceipts.remove(r.persistentModelID) }
                        else { expandedReceipts.insert(r.persistentModelID) }
                    }
                } label: { ReceiptRowView(receipt: r, expandable: true, expanded: expanded) }
                    .buttonStyle(.plain)
            }
            magnitudeBar(fraction, leading: 64)
        }
    }

    // MARK: - Items tab

    private var allItems: [LineItem] { receipts.flatMap(\.items) }

    private func itemsTab(selecting: Bool) -> some View {
        Group {
            if filteredItems.isEmpty {
                HistoryEmpty(symbol: "list.bullet", text: hasActiveFilters ? "No matching items" : "No items yet")
            } else {
                let maxByMonth = monthMax(filteredItems, date: \.createdAt) { $0.lineTotal }
                let stats = productStats
                LazyVStack(spacing: 0) {
                    if let summary = monthSummary(filteredItems, date: \.createdAt, amount: { $0.lineTotal }) {
                        summaryStrip(summary, countText: itemCountLabel(summary.count))
                    }
                    ForEach(dayGroups(of: filteredItems, date: \.createdAt), id: \.date) { group in
                        sectionHeader(DayFormat.label(group.date, dateFormat),
                                      trailing: group.items.reduce(Decimal.zero) { $0 + $1.lineTotal }.formatMoney())
                        card {
                            ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { idx, item in
                                let stat = stats[productKey(item.name)]
                                let expandable = (stat?.count ?? 0) >= 2
                                let open = !selecting && expandable && expandedItems.contains(item.persistentModelID)
                                VStack(spacing: 0) {
                                    itemRow(item, selecting: selecting, expandable: expandable, expanded: open,
                                            fraction: fraction(item.lineTotal, maxByMonth[monthKey(item.createdAt)]))
                                    if open, let stat { itemPriceHistory(stat) }
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

    /// An item row + magnitude bar. Two-pane mode selects the parent receipt; single-column mode
    /// expands the product's price history in place when it's been bought more than once.
    @ViewBuilder
    private func itemRow(_ item: LineItem, selecting: Bool, expandable: Bool, expanded: Bool, fraction: Double) -> some View {
        VStack(spacing: 0) {
            if selecting {
                Button { selectedID = item.receipt?.persistentModelID } label: { itemRowLabel(item, expandable: false, expanded: false) }
                    .buttonStyle(.plain)
            } else if expandable {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        if expandedItems.contains(item.persistentModelID) { expandedItems.remove(item.persistentModelID) }
                        else { expandedItems.insert(item.persistentModelID) }
                    }
                } label: { itemRowLabel(item, expandable: true, expanded: expanded) }
                    .buttonStyle(.plain)
            } else {
                itemRowLabel(item, expandable: false, expanded: false)
            }
            magnitudeBar(fraction, leading: 58)
        }
    }

    private func itemRowLabel(_ item: LineItem, expandable: Bool, expanded: Bool) -> some View {
        HStack(spacing: 12) {
            CategoryTile(category: item.category)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.subheadline).foregroundStyle(Palette.label)
                Text("\(Categories.displayName(item.category)) · \(item.receipt?.store ?? "")")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.lineTotal.formatMoney()).font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Palette.label)
            if expandable {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiaryLabel)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Budgets tab (money-plan snapshot: income + recurring, mirroring the Budget screen)

    private var income: [Recurring] { recurring.filter(\.isIncome) }
    private var bills: [Recurring] { recurring.filter { !$0.isIncome } }
    private var monthlyIncome: Decimal { income.reduce(.zero) { $0 + $1.monthlyEquivalent } }
    private var monthlyBills: Decimal { bills.reduce(.zero) { $0 + $1.monthlyEquivalent } }
    private var hasBudgetPlan: Bool { !income.isEmpty || !bills.isEmpty }

    /// The History date filter as a window — the current pay-cycle month when no filter is set. The
    /// "left after bills" summary scales income & bills to it via `windowAmount` (Android parity); the
    /// section cards below keep showing the per-month rate.
    private var budgetWindow: DateInterval {
        guard let r = dateRange else { return PayCycle.monthInterval() }
        let cal = Calendar.current
        let start = cal.startOfDay(for: r.lowerBound)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: r.upperBound)) ?? r.upperBound
        return DateInterval(start: start, end: end)
    }
    private var periodIncome: Decimal { income.reduce(.zero) { $0 + $1.windowAmount(budgetWindow) } }
    private var periodBills: Decimal { bills.reduce(.zero) { $0 + $1.windowAmount(budgetWindow) } }

    /// A read-only snapshot of the money plan (income + recurring payments) mirrored from the Budget
    /// screen, topped by a "left after bills" summary — the Android History Budgets tab. The summary
    /// scales to the History date filter (windowAmount); the section rows keep the per-month plan, and
    /// it links out to Budget to make changes.
    private var budgetsTab: some View {
        Group {
            if !hasBudgetPlan {
                VStack(spacing: 14) {
                    HistoryEmpty(symbol: "chart.pie", text: "No budget plan yet")
                    Button { selectTab?(.budget) } label: {
                        Text("Set up your budget  →")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                LazyVStack(spacing: 10) {
                    budgetsSummaryCard
                    if !income.isEmpty {
                        budgetsSectionCard(title: "Income", total: monthlyIncome,
                                           rows: income, isIncome: true)
                    }
                    if !bills.isEmpty {
                        budgetsSectionCard(title: "Recurring payments", total: monthlyBills,
                                           rows: bills, isIncome: false)
                    }
                    Button { selectTab?(.budget) } label: {
                        Text("Manage in Budget  →")
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.tint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 24)
            }
        }
    }

    /// income − recurring bills = what's left after fixed costs, scaled to the selected History window
    /// (the current month when no date filter is set).
    private var budgetsSummaryCard: some View {
        let left = periodIncome - periodBills
        return VStack(alignment: .leading, spacing: 0) {
            Text(dateRange == nil ? "Monthly" : "Selected period")
                .font(.caption).fontWeight(.semibold).textCase(.uppercase)
                .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
                .padding(.bottom, 8)
            summaryLine("Income", amount: "+\(periodIncome.formatMoney())", color: Palette.good)
            Divider()
            summaryLine("Recurring bills", amount: "−\(periodBills.formatMoney())",
                        color: Palette.secondaryLabel)
            Divider().padding(.bottom, 8)
            HStack {
                Text("Left after bills").font(.subheadline).fontWeight(.bold)
                    .foregroundStyle(Palette.label)
                Spacer()
                Text(left.formatMoney()).font(.title3).fontWeight(.bold)
                    .foregroundStyle(left >= 0 ? Palette.good : Palette.bad)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .contentCard(cornerRadius: 16)
    }

    private func summaryLine(_ label: LocalizedStringKey, amount: String, color: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.label)
            Spacer()
            Text(amount).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
        .padding(.vertical, 5)
    }

    /// A card with a "Title … €X / mo" header and its read-only income/bill rows.
    private func budgetsSectionCard(title: LocalizedStringKey, total: Decimal,
                                    rows: [Recurring], isIncome: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                Spacer()
                Text("\(total.formatMoney()) / mo").font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            ForEach(Array(rows.enumerated()), id: \.element.persistentModelID) { _, r in
                Divider().padding(.leading, 60)
                budgetsMoneyRow(r, isIncome: isIncome)
            }
        }
        .contentCard(cornerRadius: 16)
    }

    private func budgetsMoneyRow(_ r: Recurring, isIncome: Bool) -> some View {
        HStack(spacing: 12) {
            if isIncome {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.good.opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay(Text("💰").font(.system(size: 16)))
            } else {
                CategoryTile(category: r.category.isEmpty ? Categories.defaultName : r.category, size: 34)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline).foregroundStyle(Palette.label)
                Text(BudgetView.cadenceSubtitle(r)).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text(isIncome ? "+\(r.amount.formatMoney())" : r.amount.formatMoney())
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(isIncome ? Palette.good : Palette.label)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
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

    // MARK: - Summary strip

    /// The tab's focal point: the current month's total, its count, the change vs last month, and a
    /// six-month sparkline (last bar = current month). Replaces the plain first section header.
    @ViewBuilder
    private func summaryStrip(_ s: MonthSummary, countText: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(monthLabel(s.monthStart)).font(.caption2).fontWeight(.semibold).textCase(.uppercase)
                    .tracking(0.5).foregroundStyle(Palette.secondaryLabel)
                Text(s.total.formatMoney()).font(.title).fontWeight(.bold).foregroundStyle(Palette.label)
                Text(summaryCaption(total: s.total, prev: s.prevTotal, countText: countText))
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
            }
            Spacer(minLength: 8)
            if s.spark.contains(where: { $0 > 0 }) { sparkline(s.spark) }
        }
        .padding(14)
        .contentCard(cornerRadius: 16)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
    }

    @ViewBuilder
    private func sparkline(_ values: [Decimal]) -> some View {
        let peak = values.max() ?? .zero
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i == values.count - 1 ? Palette.tint : Palette.tertiaryLabel)
                    .frame(width: 6, height: max(4, 40 * barFraction(v, peak)))
            }
        }
        .frame(height: 40)
    }

    /// A hairline under a row: its amount as a share of the month's biggest row (1c's magnitude idea).
    @ViewBuilder
    private func magnitudeBar(_ fraction: Double, leading: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.fill)
                Capsule().fill(Palette.tint.opacity(0.55))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 3)
        .padding(.leading, leading).padding(.trailing, 16).padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: - Expansions

    /// Receipt payload: its top items inline, with an "Open receipt" link into the full detail.
    @ViewBuilder
    private func receiptExpansion(_ r: Receipt) -> some View {
        let top = Array(r.items.prefix(3))
        let more = r.items.count - top.count
        VStack(spacing: 6) {
            ForEach(top, id: \.persistentModelID) { it in
                HStack(spacing: 8) {
                    Text("\(Categories.emoji(for: it.category)) \(it.name)")
                        .font(.footnote).foregroundStyle(Palette.label).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(it.lineTotal.formatMoney()).font(.footnote).fontWeight(.semibold).foregroundStyle(Palette.label)
                }
            }
            Divider()
            HStack {
                if more > 0 {
                    Text("+\(more) more items").font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
                NavigationLink { ReceiptDetailView(receipt: r) } label: {
                    HStack(spacing: 3) {
                        Text("Open receipt").font(.caption).fontWeight(.semibold)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Palette.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.leading, 64).padding(.trailing, 16).padding(.bottom, 12)
    }

    /// Item payload: how often the product was bought, its average, a mini price chart of recent buys,
    /// and where it was cheapest — the question a flat item list can't answer.
    @ViewBuilder
    private func itemPriceHistory(_ stat: ProductStat) -> some View {
        let peak = stat.recent.map(\.unit).max() ?? .zero
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Bought this \(stat.count)×").font(.caption2).fontWeight(.semibold).textCase(.uppercase)
                    .tracking(0.4).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text("avg \(stat.avgUnit.formatMoney())").font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(Array(stat.recent.enumerated()), id: \.offset) { _, p in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(p.isCheapest ? Palette.tint : Palette.tertiaryLabel)
                            .frame(height: max(4, 30 * barFraction(p.unit, peak)))
                        Text(shortMonth(p.date)).font(.system(size: 10)).foregroundStyle(Palette.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 44).padding(.top, 10)
            Text("Cheapest at \(stat.minStore) · \(stat.minUnit.formatMoney()) on \(shortDate(stat.minDate))")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 9)
        }
        .padding(12)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 12))
        .padding(.leading, 58).padding(.trailing, 16).padding(.bottom, 12)
    }

    // MARK: - Aggregation

    /// The biggest amount in each month, so a row's magnitude bar reads as its share of that month.
    private func monthMax<T>(_ items: [T], date: KeyPath<T, Date>, _ amount: (T) -> Decimal) -> [Date: Decimal] {
        var m: [Date: Decimal] = [:]
        for it in items {
            let k = monthKey(it[keyPath: date])
            m[k] = Swift.max(m[k] ?? .zero, amount(it))
        }
        return m
    }

    /// Summary of the most recent month present (matches the top of the list), with the prior month's
    /// total and a six-month trailing sparkline.
    private func monthSummary<T>(_ items: [T], date: KeyPath<T, Date>, amount: (T) -> Decimal) -> MonthSummary? {
        guard !items.isEmpty else { return nil }
        let cal = Calendar.current
        var totalByMonth: [Date: Decimal] = [:]
        var countByMonth: [Date: Int] = [:]
        for it in items {
            let k = monthKey(it[keyPath: date])
            totalByMonth[k, default: .zero] += amount(it)
            countByMonth[k, default: 0] += 1
        }
        guard let current = totalByMonth.keys.max() else { return nil }
        let prev = cal.date(byAdding: .month, value: -1, to: current).flatMap { totalByMonth[$0] }
        var spark: [Decimal] = []
        for offset in stride(from: 5, through: 0, by: -1) {
            if let m = cal.date(byAdding: .month, value: -offset, to: current) {
                spark.append(totalByMonth[m] ?? .zero)
            }
        }
        return MonthSummary(monthStart: current, total: totalByMonth[current] ?? .zero,
                            count: countByMonth[current] ?? 0, prevTotal: prev, spark: spark)
    }

    /// Price history per product across the whole (unfiltered) ledger, keyed by normalized name.
    private var productStats: [String: ProductStat] {
        var byKey: [String: [LineItem]] = [:]
        for it in allItems {
            let key = productKey(it.name)
            guard !key.isEmpty else { continue }
            byKey[key, default: []].append(it)
        }
        var out: [String: ProductStat] = [:]
        for (key, list) in byKey {
            let sorted = list.sorted { $0.createdAt < $1.createdAt }
            let minUnit = sorted.map(\.price).min() ?? .zero
            let cheapest = sorted.first { $0.price == minUnit } ?? sorted[0]
            let sum = sorted.reduce(Decimal.zero) { $0 + $1.price }
            let avg = sum / Decimal(sorted.count)
            let recent = sorted.suffix(6).map { PurchasePoint(date: $0.createdAt, unit: $0.price, isCheapest: $0.price == minUnit) }
            out[key] = ProductStat(count: sorted.count, avgUnit: avg, minUnit: minUnit,
                                   minStore: cheapest.receipt?.store ?? "", minDate: cheapest.createdAt, recent: Array(recent))
        }
        return out
    }

    private func productKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func monthKey(_ d: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: d)?.start ?? Calendar.current.startOfDay(for: d)
    }

    private func fraction(_ v: Decimal, _ maxV: Decimal?) -> Double {
        guard let maxV, maxV > 0, v > 0 else { return 0 }
        let f = NSDecimalNumber(decimal: v).doubleValue / NSDecimalNumber(decimal: maxV).doubleValue
        return min(1, max(0.04, f))
    }

    private func barFraction(_ v: Decimal, _ peak: Decimal) -> CGFloat {
        guard peak > 0 else { return 0 }
        let f = NSDecimalNumber(decimal: v).doubleValue / NSDecimalNumber(decimal: peak).doubleValue
        return CGFloat(min(1, max(0.12, f)))
    }

    /// "18 receipts · ▲ 6% vs last month" — a "×N" multiplier past 5× so a near-empty prior month
    /// doesn't read as "+1602%". Drops the delta when there's no comparable prior month.
    private func summaryCaption(total: Decimal, prev: Decimal?, countText: String) -> String {
        guard let prev, prev > 0 else { return countText }
        let ratio = NSDecimalNumber(decimal: total).doubleValue / NSDecimalNumber(decimal: prev).doubleValue
        let magnitude: String
        if ratio >= 5 {
            magnitude = "\(Int(ratio.rounded()))×"
        } else {
            let pct = Int(((ratio - 1) * 100).rounded())
            if pct == 0 { return countText }
            magnitude = "\(abs(pct))%"
        }
        let arrow = ratio >= 1 ? "▲" : "▼"
        return "\(countText) · \(arrow) \(magnitude) \(String(localized: "vs last month"))"
    }

    private func monthLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"; return f.string(from: d)
    }
    private func shortMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: d)
    }
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f.string(from: d)
    }
}

/// Relative day-section label: "Today · 5 Jul", "Yesterday · 4 Jul", "Wed · 2 Jul".
enum DayFormat {
    static func label(_ date: Date, _ fmt: DateFormatOption = .current) -> String {
        let cal = Calendar.current
        let short = fmt.short(date)
        if cal.isDateInToday(date) { return "Today · \(short)" }
        if cal.isDateInYesterday(date) { return "Yesterday · \(short)" }
        let wd = DateFormatter(); wd.dateFormat = "EEE"
        return "\(wd.string(from: date)) · \(short)"
    }
}

/// The most-recent month's roll-up for the History summary strip.
struct MonthSummary {
    let monthStart: Date
    let total: Decimal
    let count: Int
    let prevTotal: Decimal?
    /// Up to six trailing monthly totals, oldest→newest; the last is the current month.
    let spark: [Decimal]
}

/// Aggregated price history for one product (all purchases sharing a normalized name).
struct ProductStat {
    let count: Int
    let avgUnit: Decimal
    let minUnit: Decimal
    let minStore: String
    let minDate: Date
    /// Up to the last six purchases, oldest-first, for the mini chart.
    let recent: [PurchasePoint]
}

struct PurchasePoint {
    let date: Date
    let unit: Decimal
    let isCheapest: Bool
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
