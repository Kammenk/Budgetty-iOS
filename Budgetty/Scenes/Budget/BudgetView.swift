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
    @Environment(\.modelContext) private var context
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query(sort: \Recurring.createdAt) private var recurring: [Recurring]
    @Query private var rollovers: [BudgetRollover]

    @AppStorage(SettingsKey.premium) private var premium = false
    /// The pay day the financial month starts on (1 = calendar month); the monthly budget and the
    /// per-category bars scope to it. Re-read here so the bars recompute when the setting changes.
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    /// Opt-in unspent-budget carry-over (default off). Drives the "+X carried over" lines and the
    /// effective (budget + carried) progress; toggling it reconciles the stored carry rows.
    @AppStorage(SettingsKey.budgetRolloverEnabled) private var rolloverEnabled = false

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
            // Bring carry-over up to date on open and whenever rollover is toggled (the mirror of
            // Android's BudgetViewModel.rollForwardIfNeeded).
            .task { reconcileRollover() }
            .onChange(of: rolloverEnabled) { reconcileRollover() }
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
            rolloverToggle
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
        if isWeekly {
            let cal = Calendar.current
            return receipts
                .filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear) }
                .reduce(.zero) { $0 + $1.paidTotal }
        }
        // The monthly budget resets on the user's pay day (see PayCycle); weekly stays calendar-aligned.
        let window = PayCycle.monthInterval(startDay: monthStartDay)
        return receipts
            .filter { window.contains($0.createdAt) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }

    private func categorySpent(_ group: String) -> Decimal {
        let window = PayCycle.monthInterval(startDay: monthStartDay)
        return allItems
            .filter { window.contains($0.createdAt) }
            .filter { Categories.groupOf($0.category).caseInsensitiveCompare(group) == .orderedSame
                || $0.category.caseInsensitiveCompare(group) == .orderedSame }
            .reduce(.zero) { $0 + $1.lineTotal }
    }

    private var income: [Recurring] { recurring.filter(\.isIncome) }
    private var bills: [Recurring] { recurring.filter { !$0.isIncome } }

    // MARK: - Rollover

    /// Carried-over amount for a budget key (0 unless rollover is on and the key has accrued some). A
    /// weekly overall budget never carries — no row is ever written for the WEEKLY key.
    private func carriedFor(_ key: String) -> Decimal {
        guard rolloverEnabled else { return 0 }
        return rollovers.first { $0.key == key }?.carried ?? 0
    }

    /// True once any budget has accrued carry-over — gates the "starts next period" first-run caption.
    private var anyCarried: Bool { rolloverEnabled && rollovers.contains { $0.carried > 0 } }

    /// Reconciles the stored carry rows with the current period (rolling each elapsed period's unspent
    /// leftover forward), or clears them when rollover is off. Mirrors Android's rollForwardIfNeeded.
    private func reconcileRollover() {
        BudgetRolloverRunner.reconcile(
            context: context, budgets: budgets, items: allItems,
            enabled: rolloverEnabled, startDay: monthStartDay
        )
    }

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
                    // Carry-over (monthly only — the WEEKLY key never accrues) lifts the effective
                    // limit; the bar, percentage and "left" all read against budget + carried.
                    let carried = carriedFor(overallKey)
                    let effective = b.amount + carried
                    let frac = HomeView.fraction(spent, of: effective)
                    let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(b.amount.formatMoney())
                            .font(.system(size: 40, weight: .bold)).foregroundStyle(Palette.label)
                        Text(isWeekly ? "/ week" : "/ month")
                            .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    }
                    .padding(.bottom, carried > 0 ? 4 : 14)
                    if carried > 0 {
                        Text("+\(carried.formatMoney()) carried over")
                            .font(.footnote).fontWeight(.semibold).foregroundStyle(Palette.good)
                            .padding(.bottom, 12)
                    }
                    ProgressBarView(fraction: frac, color: color, height: 8)
                    HStack {
                        Text("\(spent.formatMoney()) spent · \(Int(frac * 100))%")
                        Spacer()
                        Text("\((effective - spent).formatMoney()) left").fontWeight(.semibold)
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

    // MARK: - Rollover toggle

    /// Opt-in "carry over unused budget" row (off by default). When on with nothing accrued yet, a
    /// tiny caption notes that carry-over begins next period.
    private var rolloverToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $rolloverEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Carry over unused budget")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                    Text("Unspent budget rolls into next period")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .tint(Palette.tint)
            if rolloverEnabled && !anyCarried {
                Text("Carry-over starts next period.")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 14)
        .accessibilityIdentifier(A11y.Budget.rolloverToggle)
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

    /// Header badge: "N of M paid" once bills exist (the free-tier cap is already signalled by the
    /// upgrade row replacing the Add row), mirroring Android's Payments section counter.
    private var recurringBadge: String? {
        guard !bills.isEmpty else { return nil }
        let paid = bills.filter { $0.isPaidThisCycle() }.count
        return String(localized: "\(paid) of \(bills.count) paid")
    }

    /// True when at least one bill is paid this cycle — greens the section's "N of M paid" counter.
    private var anyBillPaid: Bool { bills.contains { $0.isPaidThisCycle() } }

    private var recurringSection: some View {
        VStack(spacing: 0) {
            sectionHeader("Recurring", badge: recurringBadge,
                          badgeTint: anyBillPaid ? Palette.good : Palette.secondaryLabel)
            VStack(spacing: 0) {
                ForEach(bills) { r in
                    billRow(r)
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

    /// A bill row: a leading paid toggle (tap to mark this occurrence paid — dims and strikes the
    /// amount) plus the same tap-to-edit body as an income row. Paid-state is derived, so it clears
    /// itself when the next occurrence begins.
    private func billRow(_ r: Recurring) -> some View {
        let paid = r.isPaidThisCycle()
        return HStack(spacing: 12) {
            Button {
                recurringEditor = RecurringEditor(isIncome: false, existing: r)
            } label: {
                HStack(spacing: 12) {
                    iconTile(for: r)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(.body).foregroundStyle(Palette.label)
                        Text(Self.cadenceSubtitle(r)).font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer(minLength: 8)
                    // Paid rows dim their amount (~40% alpha) rather than striking it.
                    Text("−\(r.amount.formatMoney())")
                        .font(.body).fontWeight(.semibold)
                        .foregroundStyle(Palette.bad)
                        .opacity(paid ? 0.4 : 1)
                }
            }
            .buttonStyle(.plain)
            // Trailing paid toggle: hollow circle → filled green check for the current cycle.
            Button {
                setPaid(r, !paid)
            } label: {
                Image(systemName: paid ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(paid ? Palette.good : Palette.tertiaryLabel)
                    .frame(width: 30, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(paid ? Text("Paid") : Text("Mark as paid"))
            .accessibilityAddTraits(paid ? [.isSelected] : [])
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    /// Marks a bill paid (or not) for its current cycle by stamping `lastPosted` — reused as the paid
    /// marker so it auto-resets when the next occurrence begins. No transaction is posted (recurring
    /// stays planning-only), so it never double-counts a scanned receipt.
    private func setPaid(_ bill: Recurring, _ paid: Bool) {
        bill.lastPosted = paid ? .now : nil
        try? context.save()
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
        let key = Budget.categoryKey(s.sub)
        let sp = categorySpent(s.sub)
        let carried = carriedFor(key)
        let effective = s.amount + carried
        let frac = HomeView.fraction(sp, of: effective)
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
                        if carried > 0 {
                            Text("+\(carried.formatMoney())")
                                .font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.good)
                        }
                        Text("\(sp.formatMoney()) / \(effective.formatMoney())")
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
                    let carried = carriedFor(key)
                    let effective = b.amount + carried
                    let frac = HomeView.fraction(spent, of: effective)
                    let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
                    Text("\(spent.formatMoney()) / \(effective.formatMoney())")
                        .font(.caption).foregroundStyle(color)
                    if carried > 0 {
                        Text("+\(carried.formatMoney())")
                            .font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.good)
                    }
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

    /// `badge` carries a trailing counter (the free-tier cap, or "N of M paid"); `badgeTint` colours
    /// its text — green once any bill is paid, the muted default otherwise.
    private func sectionHeader(_ title: LocalizedStringKey, badge: String? = nil,
                               badgeTint: Color = Palette.secondaryLabel) -> some View {
        HStack {
            Text(title).font(.caption).fontWeight(.semibold).textCase(.uppercase)
                .foregroundStyle(Palette.secondaryLabel).tracking(0.5)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(badgeTint)
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
