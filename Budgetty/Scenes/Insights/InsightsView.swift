//
//  InsightsView.swift
//  Budgetty
//
//  Insights tab from the mockup: a month stepper, a Breakdown donut (spend by category group) with
//  legend, a stat grid, Top categories bars, and Top stores. All computed from SwiftData for the
//  selected month.
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

    /// Months back from the current month (0 = this month).
    @State private var monthOffset = 0

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
            .sheet(item: $categorySel) { CategoryTransactionsSheet(category: $0.name, items: monthItems) }
            .sheet(item: $storeSel) { StoreTransactionsSheet(store: $0.name, receipts: monthReceipts) }
            .sheet(isPresented: $showCustomize) {
                InsightsCustomizeSheet(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw)
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
            if monthReceipts.isEmpty {
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
            if monthReceipts.isEmpty {
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
            if monthReceipts.isEmpty {
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

    private var selectedMonth: Date {
        Calendar.current.date(byAdding: .month, value: monthOffset, to: .now) ?? .now
    }

    private var stepper: some View {
        HStack(spacing: 28) {
            stepButton("chevron.left") { monthOffset -= 1 }
            Text(Self.monthLabel(selectedMonth))
                .font(.headline).frame(minWidth: 130)
            stepButton("chevron.right", disabled: monthOffset >= 0) {
                if monthOffset < 0 { monthOffset += 1 }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8).padding(.bottom, 6)
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

    private var monthReceipts: [Receipt] {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.createdAt, equalTo: selectedMonth, toGranularity: .month) }
    }
    private var monthItems: [LineItem] { monthReceipts.flatMap(\.items) }
    private var totalSpent: Decimal { monthReceipts.reduce(.zero) { $0 + $1.paidTotal } }
    private var totalSaved: Decimal { monthReceipts.reduce(.zero) { $0 + $1.discount } }

    /// Spend rolled up to top-level groups, descending.
    private var groupSlices: [(name: String, value: Decimal)] {
        var sums: [String: Decimal] = [:]
        for item in monthItems {
            let g = Categories.groupOf(item.category)
            sums[g, default: .zero] += item.lineTotal
        }
        return sums.map { (name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }

    private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

    // MARK: - Trend

    /// Total spend for each of the last 7 months, oldest → the selected month (last = current).
    private var monthlyTrend: [(label: String, value: Decimal)] {
        let cal = Calendar.current
        return (0..<7).reversed().map { back in
            let month = cal.date(byAdding: .month, value: -back, to: selectedMonth) ?? selectedMonth
            let total = receipts
                .filter { cal.isDate($0.createdAt, equalTo: month, toGranularity: .month) }
                .reduce(Decimal.zero) { $0 + $1.paidTotal }
            return (label: Self.shortMonth(month), value: total)
        }
    }

    private var trendCard: some View {
        let data = monthlyTrend
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
        let vals = monthlyTrend.map { dbl($0.value) }
        if vals.count >= 2, let current = vals.last {
            let prev = vals[vals.count - 2]
            if prev > 0 {
                let pct = Int((abs(current - prev) / prev * 100).rounded())
                let down = current <= prev
                let color = down ? Palette.good : Palette.warn
                HStack(spacing: 4) {
                    Image(systemName: down ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(pct)% vs last month").font(.caption).fontWeight(.semibold)
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

    static func shortMonth(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: date)
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
                        Text("this month").font(.caption2).foregroundStyle(Palette.secondaryLabel)
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
            statTile("Receipts", "\(monthReceipts.count)", color: Palette.label)
            statTile("Avg / receipt", avgPerReceipt.formatMoney(), color: Palette.label)
            statTile("Saved", totalSaved.formatMoney(), color: Palette.good)
        }
    }

    private var avgPerReceipt: Decimal {
        guard !monthReceipts.isEmpty else { return .zero }
        return totalSpent / Decimal(monthReceipts.count)
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
        for r in monthReceipts { sums[r.store, default: .zero] += r.paidTotal }
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
            Text("Nothing spent this month").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    static func monthLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }
}
