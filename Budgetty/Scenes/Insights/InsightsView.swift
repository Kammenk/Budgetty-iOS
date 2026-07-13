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
    @State private var wide = false
    @AppStorage(InsightsLayoutStore.orderKey) private var orderRaw = ""
    @AppStorage(InsightsLayoutStore.hiddenKey) private var hiddenRaw = ""
    @State private var showCustomize = false
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    insightsHeader
                        .padding(.bottom, 2)
                    Group {
                        if hSize == .regular {
                            if wide { wideStack } else { regularStack }
                        } else {
                            compactStack
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 24)
            }
            .trackWideLandscape($wide)
            .screenCanvas()
            // The mockup puts the title inside the scroll content with the customize control on the
            // SAME row, which the system large-title nav bar can't do (toolbar items sit in the small
            // bar above the large title). So draw our own header and hide the bar — the Home pattern.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $categorySel) { CategoryTransactionsSheet(category: $0.name, items: periodItems) }
            .sheet(item: $storeSel) { StoreTransactionsSheet(store: $0.name, receipts: periodReceipts) }
            .sheet(isPresented: $showCustomize) {
                InsightsCustomizeSheet(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw)
            }
            .sheet(isPresented: $showCustomSheet) { DateRangeSheet(range: $customRange) }
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

    /// Custom header: the large "Insights" title with the customize control trailing on the same
    /// baseline row. Customizing the section order/visibility applies to the iPhone layout only.
    private var insightsHeader: some View {
        HStack {
            Text("Insights")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            if hSize == .compact {
                Button { showCustomize = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.label)
                        .frame(width: 36, height: 36)
                        .background(Palette.fill, in: Circle())
                }
                .accessibilityLabel("Customize sections")
            }
        }
    }

    private var incomeCards: some View {
        IncomeInsightsCards(income: recurring.filter(\.isIncome),
                            bills: recurring.filter { !$0.isIncome },
                            monthSpent: totalSpent)
    }

    /// iPhone: one column, in the user's chosen order with hidden sections removed.
    private var compactStack: some View {
        VStack(spacing: 14) {
            stepper
            if periodReceipts.isEmpty {
                emptyState
            } else {
                ForEach(visibleSections) { sectionView($0) }
            }
        }
    }

    private var visibleSections: [InsightSection] {
        let hidden = InsightsLayoutStore.hidden(hiddenRaw)
        return InsightsLayoutStore.order(orderRaw).filter { !hidden.contains($0) }
    }

    @ViewBuilder
    private func sectionView(_ section: InsightSection) -> some View {
        switch section {
        case .trend: trendCard
        case .breakdown: breakdownCard
        case .stats: statGrid
        case .topCategories: topCategoriesCard
        case .topStores: topStoresCard
        case .income: incomeCards
        }
    }

    /// iPad portrait: two masonry columns of the same cards, capped and centered.
    private var regularStack: some View {
        VStack(spacing: Dimens.regularColumnSpacing) {
            stepper
            if periodReceipts.isEmpty {
                emptyState
            } else {
                RegularColumns {
                    trendCard
                    statGrid
                    topCategoriesCard
                } right: {
                    breakdownCard
                    topStoresCard
                    incomeCards
                }
            }
        }
        .adaptiveReadableWidth(Dimens.wideContentMaxWidth)
    }

    /// iPad landscape: three masonry columns for the extra width.
    private var wideStack: some View {
        VStack(spacing: Dimens.regularColumnSpacing) {
            stepper
            if periodReceipts.isEmpty {
                emptyState
            } else {
                ThreeColumns {
                    trendCard
                    statGrid
                } second: {
                    breakdownCard
                    topCategoriesCard
                } third: {
                    topStoresCard
                    incomeCards
                }
            }
        }
        .adaptiveReadableWidth(Dimens.landscapeContentMaxWidth)
    }

    // MARK: - Period

    /// `‹ [pill] ›` — the Android period stepper: arrows walk a calendar-aligned block one unit at
    /// a time; the centre pill shows the active unit as an eyebrow over the period value and opens
    /// a menu to switch the unit or pick a custom range (arrows disable while a custom range is
    /// active).
    private var stepper: some View {
        let steppable = !period.isCustom
        return HStack(spacing: 12) {
            stepButton("chevron.left", disabled: !steppable || !canStepBackward) { step(-1) }
            periodMenu
            stepButton("chevron.right", disabled: !steppable || !canStepForward) { step(1) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 6)
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
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        if period.isCustom {
                            Image(systemName: "calendar").font(.system(size: 9, weight: .semibold))
                        }
                        Text(period.isCustom ? "CUSTOM" : (period.steppedUnit?.eyebrow ?? ""))
                            .font(.system(size: 10, weight: .medium)).kerning(0.8)
                    }
                    .foregroundStyle(Palette.secondaryLabel)
                    Text(period.friendlyLabel)
                        .font(.headline).foregroundStyle(Palette.label).lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .frame(minWidth: 150)
            .background(Palette.matControl, in: Capsule())
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.matControlBorder, lineWidth: 0.5))
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

    private func stepButton(_ symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(disabled ? Palette.tertiaryLabel : Palette.label)
                .frame(width: 36, height: 36)
                .background(Palette.fill, in: Circle())
        }
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
    private var periodTrend: [(label: String, value: Decimal)] {
        var windows = [period]
        for _ in 0..<6 { windows.append(windows.last!.previous()) }
        return windows.reversed().map { p in
            let window = p.interval
            let total = receipts
                .filter { window.contains($0.createdAt) }
                .reduce(Decimal.zero) { $0 + $1.paidTotal }
            return (label: p.barLabel, value: total)
        }
    }

    private var trendCard: some View {
        let data = periodTrend
        let maxV = data.map { dbl($0.value) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trend").font(.headline)
                Spacer()
                trendDeltaPill
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(data.enumerated()), id: \.offset) { idx, d in
                    let isCurrent = idx == data.count - 1
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isCurrent ? Palette.tint : Palette.fill)
                            .frame(height: barHeight(dbl(d.value), max: maxV))
                        Text(d.label).font(.system(size: 10))
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundStyle(isCurrent ? Palette.tint : Palette.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 104)
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

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Breakdown").font(.headline)
            let slices = groupSlices
            let netTotal = slices.reduce(Decimal.zero) { $0 + $1.value }
            HStack(spacing: 4) {
                ZStack {
                    DonutChart(slices: slices.map { (Color(argb: Categories.color(for: $0.name)), dbl($0.value)) })
                        .frame(width: 150, height: 150)
                    VStack(spacing: 0) {
                        Text("Total").font(.caption2).foregroundStyle(Palette.secondaryLabel)
                        Text(netTotal.formatMoney()).font(.title3).fontWeight(.bold)
                        Text(period.contextNoun).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                ForEach(slices, id: \.name) { s in
                    HStack(spacing: 7) {
                        Circle().fill(Color(argb: Categories.color(for: s.name)))
                            .frame(width: 9, height: 9)
                        Text(s.name).font(.caption).foregroundStyle(Palette.label).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(s.value.formatMoney()).font(.caption).fontWeight(.semibold)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statTile("Total spent", totalSpent.formatMoney(), color: Palette.label)
            statTile("Receipts", "\(periodReceipts.count)", color: Palette.label)
            statTile("Avg / receipt", avgPerReceipt.formatMoney(), color: Palette.label)
            statTile("Saved", totalSaved.formatMoney(), color: Palette.good)
        }
    }

    private var avgPerReceipt: Decimal {
        guard !periodReceipts.isEmpty else { return .zero }
        return totalSpent / Decimal(periodReceipts.count)
    }

    private func statTile(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Palette.secondaryLabel)
            Text(value).font(.title3).fontWeight(.bold).foregroundStyle(color)
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
                            Text("\(Categories.emoji(for: s.name)) \(s.name)")
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

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.pie").font(.system(size: 34)).foregroundStyle(Palette.tertiaryLabel)
            Text("Nothing spent \(period.contextNoun)").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}
