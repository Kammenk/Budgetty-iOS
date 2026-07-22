//
//  BudgetView.swift
//  Budgetty
//
//  Budget tab from the mockup: a Monthly/Weekly period toggle, the overall budget card, Income and
//  Recurring lists (add/edit), and a per-category budget grid. Single budget period model, mirroring
//  Android (one Monthly + one Weekly amount).
//

import SwiftUI
import SwiftData

private enum BudgetPeriod: String, CaseIterable, Identifiable {
    case monthly = "Monthly", weekly = "Weekly"
    var id: String { rawValue }
    /// Localized period word, for interpolating into the "%@ budget" strings.
    var localized: String {
        switch self {
        case .monthly: String(localized: "Monthly")
        case .weekly: String(localized: "Weekly")
        }
    }
}

struct BudgetView: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]

    @AppStorage(SettingsKey.premium) private var premium = false

    @State private var period: BudgetPeriod = .monthly
    @State private var showPaywall = false

    // Sheet routing
    private struct RecurringEditor: Identifiable { let id = UUID(); let isIncome: Bool; let existing: Recurring? }
    private struct BudgetEditor: Identifiable { let id: String; let title: String; let key: String; let existing: Budget? }
    private struct CategoryRoute: Identifiable { let id: String }
    @State private var recurringEditor: RecurringEditor?
    @State private var budgetEditor: BudgetEditor?
    @State private var categoryRoute: CategoryRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    budgetHeader
                        .padding(.bottom, 10)
                    compactStack
                }
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 24)
                // Single centered column on iPad (like Account): cap the whole column — title row
                // included — to a readable width rather than stretching edge-to-edge.
                .adaptiveReadableWidth(Dimens.contentMaxWidth)
            }
            .underFloatingDock()
            .screenCanvas()
            // The mockup puts the title at the very top of the scroll content (no nav-bar row above
            // it), so draw our own header and hide the bar — the Home pattern.
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $recurringEditor) { ed in
                RecurringSheet(isIncome: ed.isIncome, existing: ed.existing)
            }
            .sheet(item: $budgetEditor) { ed in
                BudgetAmountSheet(title: ed.title, budgetKey: ed.key, existing: ed.existing)
            }
            .sheet(item: $categoryRoute) { CategoryBudgetSheet(group: $0.id) }
            .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
        }
    }

    // MARK: - Layout

    /// Custom header: the large "Budget" title, mirroring the mockup's in-content title row.
    private var budgetHeader: some View {
        HStack {
            Text("Budget")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
        }
    }

    private var periodPicker: some View {
        GlassSegmentedControl(options: Array(BudgetPeriod.allCases), selection: $period) {
            LocalizedStringKey($0.rawValue)
        }
        .accessibilityIdentifier(A11y.Budget.periodToggle)
    }

    /// One column on every size class. Capped/centered on iPad by the caller.
    private var compactStack: some View {
        VStack(spacing: 16) {
            periodPicker
            overallCard
            incomeSection
            recurringSection
            activeSubBudgetsSection
            categorySection
        }
    }

    // MARK: - Derived data

    private var isWeekly: Bool { period == .weekly }
    private var overallKey: String { isWeekly ? Budget.weeklyKey : Budget.monthlyKey }
    private var overallBudget: Budget? { budgets.first { $0.key == overallKey } }

    private var allItems: [LineItem] { receipts.flatMap(\.items) }

    private var spent: Decimal {
        let cal = Calendar.current
        let granularity: Calendar.Component = isWeekly ? .weekOfYear : .month
        return receipts
            .filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: granularity) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }

    private func categorySpent(_ group: String) -> Decimal {
        let cal = Calendar.current
        return allItems
            .filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
            .filter { Categories.groupOf($0.category).caseInsensitiveCompare(group) == .orderedSame
                || $0.category.caseInsensitiveCompare(group) == .orderedSame }
            .reduce(.zero) { $0 + $1.lineTotal }
    }

    private var income: [Recurring] { recurring.filter(\.isIncome) }
    private var bills: [Recurring] { recurring.filter { !$0.isIncome } }

    // MARK: - Overall card

    private var overallCard: some View {
        Button {
            budgetEditor = BudgetEditor(id: overallKey, title: "\(period.localized) \(String(localized: "Budget"))",
                                        key: overallKey, existing: overallBudget)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey("\(period.localized) budget"))
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    .padding(.bottom, 8)
                if let b = overallBudget {
                    let frac = HomeView.fraction(spent, of: b.amount)
                    let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(b.amount.formatMoney())
                            .font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.label)
                        Text(isWeekly ? "/ week" : "/ month")
                            .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    }
                    .padding(.bottom, 14)
                    ProgressBarView(fraction: frac, color: color, height: 8)
                    HStack {
                        Text("\(spent.formatMoney()) spent · \(Int(frac * 100))%")
                        Spacer()
                        Text("\((b.amount - spent).formatMoney()) left").fontWeight(.semibold)
                            .foregroundStyle(color)
                    }
                    .font(.footnote).foregroundStyle(Palette.secondaryLabel)
                    .padding(.top, 8)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text(LocalizedStringKey("Set a \(period.localized) budget"))
                    }
                    .font(.headline).foregroundStyle(Palette.tint)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.Budget.overall)
    }

    // MARK: - Income

    private var incomeSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Income")
            VStack(spacing: 0) {
                ForEach(income) { r in
                    moneyRow(r)
                    Divider().padding(.leading, 60)
                }
                addRow("Add income source") {
                    recurringEditor = RecurringEditor(isIncome: true, existing: nil)
                }
            }
            .contentCard(cornerRadius: 14)
        }
    }

    /// Free tier caps bills at `RecurringQuota.freeLimit`; income is never capped.
    private var billLimitReached: Bool { !premium && bills.count >= RecurringQuota.freeLimit }

    private var recurringSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Recurring", badge: billLimitReached ? "\(bills.count) / \(RecurringQuota.freeLimit)" : nil)
            VStack(spacing: 0) {
                ForEach(bills) { r in
                    moneyRow(r)
                    Divider().padding(.leading, 60)
                }
                // At the cap the Add row becomes the upsell rather than a button that fails — the
                // existing bills keep working, and deleting one frees the slot again.
                if billLimitReached {
                    upgradeRow
                } else {
                    addRow("Add recurring payment") {
                        recurringEditor = RecurringEditor(isIncome: false, existing: nil)
                    }
                }
            }
            .contentCard(cornerRadius: 14)
        }
    }

    private var upgradeRow: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fill)
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondaryLabel))
                Text("Upgrade to add more").foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11y.Budget.recurringUpgrade)
    }

    private func moneyRow(_ r: Recurring) -> some View {
        Button {
            recurringEditor = RecurringEditor(isIncome: r.isIncome, existing: r)
        } label: {
            HStack(spacing: 12) {
                iconTile(for: r)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.label).font(.body).foregroundStyle(Palette.label)
                    Text(Self.cadenceSubtitle(r)).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 8)
                Text("\(r.isIncome ? "+" : "−")\(r.amount.formatMoney())")
                    .font(.body).fontWeight(.semibold)
                    .foregroundStyle(r.isIncome ? Palette.good : Palette.bad)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func iconTile(for r: Recurring) -> some View {
        if r.isIncome {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.good)
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "dollarsign").font(.system(size: 15, weight: .bold)).foregroundStyle(.white))
        } else {
            CategoryTile(category: r.category.isEmpty ? Categories.defaultName : r.category, size: 32)
        }
    }

    private func addRow(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fill)
                    .frame(width: 32, height: 32)
                    .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.tint))
                Text(title).foregroundStyle(Palette.tint)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Active sub-budgets

    /// Every sub-category (a category that rolls up into a different group) that has a budget set.
    private var activeSubBudgets: [(sub: String, parent: String, amount: Decimal)] {
        budgets.compactMap { b -> (sub: String, parent: String, amount: Decimal)? in
            guard b.key.hasPrefix("CAT:"), b.amount > 0 else { return nil }
            let name = String(b.key.dropFirst(4))
            let parent = Categories.groupOf(name)
            guard parent.caseInsensitiveCompare(name) != .orderedSame else { return nil }
            return (sub: name, parent: parent, amount: b.amount)
        }
        .sorted { $0.parent == $1.parent ? $0.sub < $1.sub : $0.parent < $1.parent }
    }

    private func subBudgetCount(_ group: String) -> Int {
        Categories.children(of: group).filter { child in
            budgets.contains { $0.key == Budget.categoryKey(child.name) && $0.amount > 0 }
        }.count
    }

    @ViewBuilder
    private var activeSubBudgetsSection: some View {
        let subs = activeSubBudgets
        if !subs.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("Active sub-budgets").font(.caption).fontWeight(.semibold).textCase(.uppercase)
                        .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
                    Text("\(subs.count)").font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Palette.tint, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
                VStack(spacing: 0) {
                    ForEach(Array(subs.enumerated()), id: \.element.sub) { idx, s in
                        subBudgetRow(s)
                        if idx < subs.count - 1 { Divider().padding(.leading, 54) }
                    }
                }
                .contentCard(cornerRadius: 14)
            }
        }
    }

    private func subBudgetRow(_ s: (sub: String, parent: String, amount: Decimal)) -> some View {
        let sp = categorySpent(s.sub)
        let frac = HomeView.fraction(sp, of: s.amount)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        return Button {
            categoryRoute = CategoryRoute(id: s.parent)
        } label: {
            HStack(spacing: 10) {
                CategoryTile(category: s.sub, size: 28)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text(s.sub).font(.subheadline).foregroundStyle(Palette.label)
                        Text("· \(s.parent)").font(.caption).foregroundStyle(Palette.secondaryLabel)
                        Spacer(minLength: 4)
                        Text("\(sp.formatMoney()) / \(s.amount.formatMoney())")
                            .font(.caption).fontWeight(.semibold).foregroundStyle(color)
                    }
                    ProgressBarView(fraction: frac, color: color, height: 4)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Category budgets

    private var categorySection: some View {
        VStack(spacing: 0) {
            sectionHeader("Category Budgets")
            // 2 columns on iPhone; 3 within the readable single column on iPad.
            LazyVGrid(columns: adaptiveGridColumns(compact: 2, regular: 3,
                                                   isRegular: hSize == .regular, spacing: 10),
                      spacing: 10) {
                ForEach(Categories.groups.filter { $0.name != Categories.other }, id: \.name) { g in
                    categoryCard(g.name)
                }
            }
        }
    }

    private func categoryCard(_ group: String) -> some View {
        let key = Budget.categoryKey(group)
        let budget = budgets.first { $0.key == key }
        let spent = categorySpent(group)
        let subCount = subBudgetCount(group)
        return Button {
            categoryRoute = CategoryRoute(id: group)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Categories.emoji(for: group)).font(.system(size: 22))
                Text(Categories.displayName(group)).font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                    .lineLimit(1)
                if let b = budget {
                    let frac = HomeView.fraction(spent, of: b.amount)
                    let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
                    Text("\(spent.formatMoney()) / \(b.amount.formatMoney())")
                        .font(.caption).foregroundStyle(color)
                    ProgressBarView(fraction: frac, color: Color(argb: Categories.color(for: group)), height: 4)
                } else {
                    Text("Set a budget").font(.caption).foregroundStyle(Palette.tint)
                    ProgressBarView(fraction: 0, color: .clear, height: 4)
                }
                if subCount > 0 {
                    Text("\(subCount) sub-budget\(subCount == 1 ? "" : "s")")
                        .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .contentCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bits

    /// `badge` carries the free-tier counter ("3 / 3") when a section is at its cap.
    private func sectionHeader(_ title: LocalizedStringKey, badge: String? = nil) -> some View {
        HStack {
            Text(title).font(.caption).fontWeight(.semibold).textCase(.uppercase)
                .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(Palette.secondaryLabel)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Palette.fill, in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 6)
    }

    static func cadenceSubtitle(_ r: Recurring) -> String {
        switch r.cadence {
        case .monthly: "\(String(localized: "Monthly")) · \(RecurringSheet.ordinal(r.dueDay))"
        case .weekly: "\(String(localized: "Weekly")) · \(RecurringSheet.weekdayName(r.dueDay))s"
        case .yearly: "\(String(localized: "Yearly")) · \(RecurringSheet.ordinal(r.dueDay))"
        case .once: String(localized: "One-time")
        }
    }
}
