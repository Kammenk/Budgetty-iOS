//
//  HomeView.swift
//  Budgetty
//
//  Home tab — the dashboard from the iOS mockup: a large "Budgetty" title with an avatar, the
//  violet "Total spent" hero card, a Budgets progress card, and a Recent Receipts inset-grouped
//  list. Driven by SwiftData; falls back to gentle empty states when there's no data yet.
//

import SwiftUI
import SwiftData

/// Home's spending period — the pill in the hero card. Mirrors Android's Home `DateRangeFilter`.
private enum HomePeriod: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3, last6, allTime
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .last3: "Last 3 months"
        case .last6: "Last 6 months"
        case .allTime: "All time"
        }
    }
    /// The single-month periods keep Home's monthly-plan cards (budget + planned bills); the rest hide
    /// them and show a spend-focused read instead.
    var isMonth: Bool { self == .thisMonth || self == .lastMonth }
    /// Whole months back from the current cycle for the multi-month windows (nil otherwise).
    var monthsBack: Int? {
        switch self {
        case .last3: 3
        case .last6: 6
        default: nil
        }
    }
}

struct HomeView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.selectTab) private var selectTab
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query private var recurrings: [Recurring]
    @Query private var rollovers: [BudgetRollover]
    // Wellbeing banner inputs (the score derives on-device from these + receipts/budgets/recurrings).
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]
    @Query private var ignoredRows: [IgnoredSubscription]

    @AppStorage(HomeLayoutStore.orderKey) private var orderRaw = ""
    @AppStorage(HomeLayoutStore.hiddenKey) private var hiddenRaw = HomeLayoutStore.defaultHidden
    /// The pay day the financial month starts on (1 = calendar month); the hero's "this month"
    /// figures follow it. Re-read here so the card updates live when the setting changes.
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1
    @AppStorage(SettingsKey.budgetRolloverEnabled) private var rolloverEnabled = false
    @State private var showCustomize = false
    /// The Home period filter (the hero pill). Default = this month, so Home opens exactly as before.
    @State private var period: HomePeriod = .thisMonth

    private var visibleSections: [HomeSection] {
        let hidden = HomeLayoutStore.hidden(hiddenRaw)
        return HomeLayoutStore.order(orderRaw).filter { !hidden.contains($0) }
    }

    /// This month's planned recurring bills (monthly equivalents) — paired with actual spend on the
    /// hero card. Planning-only: clearly marked as not yet spent.
    private var monthBills: Decimal {
        recurrings.filter { !$0.isIncome }.reduce(.zero) { $0 + $1.monthlyEquivalent }
    }

    private var hasBudget: Bool {
        budget(Budget.monthlyKey) != nil || budget(Budget.weeklyKey) != nil
    }

    /// The Wellbeing snapshot feeding the Home banner (Android parity: the banner is a live teaser).
    private var wellbeingSummary: WellbeingSummary {
        WellbeingScan.run(receipts: receipts, budgets: budgets, recurring: recurrings, goals: goals,
                          contributions: contributions, ignoredSubs: Set(ignoredRows.map(\.merchant)),
                          monthStartDay: monthStartDay)
    }

    /// The window for the selected [period]: a pay-cycle month (this / last), the last N whole cycles,
    /// or earliest-receipt-to-now for all time.
    private func periodWindow(_ p: HomePeriod) -> DateInterval {
        let cal = Calendar.current
        switch p {
        case .thisMonth: return PayCycle.monthInterval(startDay: monthStartDay)
        case .lastMonth: return PayCycle.monthInterval(startDay: monthStartDay, offset: -1)
        case .last3, .last6:
            let back = (p.monthsBack ?? 1) - 1
            let start = PayCycle.month(.now, startDay: monthStartDay, offset: -back).start
            let end = PayCycle.monthInterval(startDay: monthStartDay).end
            return DateInterval(start: start, end: end)
        case .allTime:
            let earliest = receipts.map(\.createdAt).min() ?? PayCycle.monthInterval(startDay: monthStartDay).start
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
            return DateInterval(start: cal.startOfDay(for: earliest), end: end)
        }
    }

    private var periodReceipts: [Receipt] {
        let window = periodWindow(period)
        return receipts.filter { window.contains($0.createdAt) }
    }
    private var periodSpent: Decimal { periodReceipts.reduce(.zero) { $0 + $1.paidTotal } }

    private func budget(_ key: String) -> Decimal? {
        budgets.first { $0.key == key }.map(\.amount)
    }

    /// Carried-over amount on the overall monthly budget (0 unless rollover is on). Home shows only
    /// the current month, so no offset gating is needed. Weekly never carries.
    private var monthlyCarried: Decimal {
        guard rolloverEnabled else { return 0 }
        return rollovers.first { $0.key == Budget.monthlyKey }?.carried ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    homeHeader
                        .padding(.bottom, 14)
                    compactStack
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
                // Single centered column on iPad (like Account): cap the whole column — title row
                // included — to a readable width rather than stretching edge-to-edge.
                .adaptiveReadableWidth(Dimens.contentMaxWidth)
            }
            .underFloatingDock()
            .screenCanvas()
            .sheet(isPresented: $showCustomize) {
                HomeCustomizeSheet(orderRaw: $orderRaw, hiddenRaw: $hiddenRaw)
            }
            // The mockup puts the brand title and the avatar on ONE row, which the system large-title
            // nav bar can't do (toolbar items sit in the small bar above the large title). So Home
            // draws its own header row and hides the navigation bar.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Custom header: the large "Budgetty" brand title with the account avatar trailing on the same
    /// baseline row, exactly as in the mockup.
    private var homeHeader: some View {
        HStack(spacing: 12) {
            Text("Budgetty")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            // Mockup: quiet pill next to the avatar opens the section customize sheet.
            Button { showCustomize = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "star")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Customize").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Palette.tint)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Palette.fill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize sections")
            .accessibilityIdentifier(A11y.Home.customize)
            NavigationLink { AccountView() } label: {
                AvatarView(initials: auth.initials, size: 36, fontSize: 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")
            .accessibilityIdentifier(A11y.Home.account)
        }
    }

    // MARK: - Layout

    /// One column on every size class, in the user's customized section order (hidden sections
    /// skipped). Capped/centered on iPad by the caller.
    private var compactStack: some View {
        VStack(spacing: 14) {
            ForEach(visibleSections) { section in
                switch section {
                // Current pay-cycle month → the Safe-to-spend hero (which absorbs the spent figure);
                // every other period keeps the classic Total-spent gradient hero.
                case .totalSpent: if period == .thisMonth { safeToSpendCard } else { heroCard }
                case .weekComparison: if lastWeekSpent > 0 { weekCard }
                // The monthly budget card is a single-month concept — hidden for multi-month / all-time.
                case .budgets: if hasBudget && period.isMonth { budgetsCard }
                // Recurring bills due soon — date-based, so shown for any period once any is unpaid.
                case .upcomingBills: if hasUpcomingBills { upcomingBillsCard }
                // A live teaser into the dedicated Wellbeing screen (first-run state before there's a score).
                case .wellbeing:
                    NavigationLink { WellbeingView() } label: { WellbeingBanner(summary: wellbeingSummary) }
                        .buttonStyle(.plain)
                case .receipts: recentReceiptsSection
                }
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total spent")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                periodPill
            }
            .padding(.bottom, 6)

            // Mockup: the big figure never truncates — very large amounts scroll horizontally.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(periodSpent.formatMoney())
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)

            Text("\(String(localized: "\(periodReceipts.count) receipts")) · \(periodDescriptor)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 14)

            heroDetail
        }
        .padding(20)
        .background(Palette.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Mockup: `inset 0 1px 0 rgba(255,255,255,.18)` — the bright top edge that makes the card
        // read as lit from above (it is NOT part of the gradient). A border stroke fading out
        // downward follows the corner curve the way the CSS inset shadow does.
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.18), .clear],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .shadow(color: Color(argb: 0xFF6650A4).opacity(0.38), radius: 14, y: 8)
    }

    // MARK: - Safe to spend (this-month cash flow)
    //
    // For the current pay-cycle month the hero becomes "Safe to spend" — one glass card stating what
    // is free to spend before payday: income this cycle − spent so far − bills still owed. A port of
    // Android's HomeViewModel cash-flow derivation + SafeToSpendCard. Per the iOS mockup the three
    // figures the number is derived from read top-to-bottom as an inset grouped list (the native
    // idiom), and the status colour lives in the amount + a soft wash behind the glass, never a
    // filled card.

    private enum SafeToSpendStatus { case healthy, low, over, setup }

    /// Recurring income at its flat per-month rate — Android sums `monthlyAmount`, whose iOS twin is
    /// `monthlyEquivalent` (also what Home's planned-bills total uses, so the parts reconcile).
    private var cycleIncome: Decimal {
        recurrings.filter(\.isIncome).reduce(.zero) { $0 + $1.monthlyEquivalent }
    }
    /// Spend inside the current pay-cycle month, independent of the selected period.
    private var cycleSpent: Decimal {
        let w = PayCycle.monthInterval(startDay: monthStartDay)
        return receipts.filter { w.contains($0.createdAt) }.reduce(.zero) { $0 + $1.paidTotal }
    }
    private var cycleReceiptCount: Int {
        let w = PayCycle.monthInterval(startDay: monthStartDay)
        return receipts.filter { w.contains($0.createdAt) }.count
    }
    /// Bills already marked paid this cycle: they drop off Safe to spend (not re-subtracted) but are
    /// surfaced as context under "Bills still due".
    private var billsPaidThisCycle: Decimal {
        recurrings.filter { !$0.isIncome && $0.isPaidThisCycle(startDay: monthStartDay) }
            .reduce(.zero) { $0 + $1.monthlyEquivalent }
    }
    /// Bills not yet paid — still owed out of this cycle's income.
    private var billsStillDue: Decimal {
        recurrings.filter { !$0.isIncome && !$0.isPaidThisCycle(startDay: monthStartDay) }
            .reduce(.zero) { $0 + $1.monthlyEquivalent }
    }
    /// Income this cycle − spent so far − bills still owed.
    private var safeToSpend: Decimal { cycleIncome - cycleSpent - billsStillDue }

    /// The next pay-cycle start — the day Safe to spend resets.
    private var nextPayday: Date { PayCycle.month(.now, startDay: monthStartDay, offset: 1).start }
    /// Days from today to the next pay-cycle start (min 1), for the per-day figure.
    private var daysUntilPayday: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: .now),
                                      to: cal.startOfDay(for: nextPayday)).day ?? 1
        return max(1, days)
    }

    private var safeToSpendStatus: SafeToSpendStatus {
        if cycleIncome <= 0 { return .setup }
        if safeToSpend < 0 { return .over }
        // "Getting low" at ≤10% of the cycle's income left (Android's threshold); compare ×10 so it
        // stays exact in Decimal.
        if safeToSpend * 10 <= cycleIncome { return .low }
        return .healthy
    }
    private func safeToSpendTone(_ s: SafeToSpendStatus) -> Color {
        switch s {
        case .over: Palette.bad
        case .low: Palette.warn
        case .setup: Palette.tertiaryLabel
        case .healthy: Palette.good
        }
    }

    /// "25 Jun – 24 Jul" — the current pay-cycle month's day range (subtitle under "Spent this cycle").
    private var cycleRangeLabel: String {
        let (start, end) = PayCycle.month(.now, startDay: monthStartDay)
        let f = DateFormatter(); f.dateFormat = "d MMM"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
    /// "25 Jul" — the reset date, for the per-day caption.
    private var resetDateLabel: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f.string(from: nextPayday)
    }

    private var safeToSpendCard: some View {
        let status = safeToSpendStatus
        let tone = safeToSpendTone(status)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Safe to spend")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(Palette.secondaryLabel)
                Spacer()
                periodPillGlass
            }
            .padding(.bottom, 6)

            // The hero figure — never truncates; a muted placeholder stands in until income is set.
            if status == .setup {
                Text(verbatim: "—")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(Palette.tertiaryLabel)
                    .padding(.vertical, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(safeToSpend.formatMoney())
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(tone)
                }
                .padding(.vertical, 2)
            }

            safeToSpendCaption(status)
                .padding(.top, 4)

            safeToSpendBar(status: status, tone: tone)
                .frame(height: 6)
                .padding(.top, 16)

            safeToSpendList(status: status)
                .padding(.top, 16)

            if status == .setup {
                Button { selectTab?(.budget) } label: {
                    Label("Set up income", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .ctaPill(height: 48)
                }
                .padding(.top, 14)
                .accessibilityIdentifier(A11y.Home.setUpIncome)
            }

            safeToSpendFoot(status)
                .padding(.top, 12)
        }
        .padding(20)
        .contentCard(cornerRadius: 24)
        // The status wash: a soft colour bloom behind the neutral glass (mockup `f.glow`), plus a
        // matching lift shadow — the material itself stays system-adaptive.
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(tone)
                .opacity(status == .setup ? 0 : 0.22)
                .blur(radius: 26)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .allowsHitTesting(false)
        )
        .shadow(color: status == .setup ? Palette.cardShadow : tone.opacity(0.22), radius: 16, y: 8)
        .accessibilityIdentifier(A11y.Home.safeToSpend)
    }

    /// Per-day + reset date, or plain language for the overspent / setup states.
    @ViewBuilder
    private func safeToSpendCaption(_ status: SafeToSpendStatus) -> some View {
        switch status {
        case .over:
            Text("\(abs(safeToSpend).formatMoney()) over — spent more than you have left this cycle.")
                .font(.footnote).foregroundStyle(Palette.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        case .setup:
            Text("Add your income to see what's safe to spend before payday.")
                .font(.subheadline).foregroundStyle(Palette.label).fixedSize(horizontal: false, vertical: true)
        case .healthy, .low:
            let perDay = safeToSpend / Decimal(daysUntilPayday)
            // Both halves are already localized, so join them verbatim (no "%@ · %@" catalog key).
            Text(verbatim: "\(perDayLabel(perDay)) · \(String(localized: "resets \(resetDateLabel)"))")
                .font(.footnote).foregroundStyle(Palette.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "41 €/day for the next 15 days" — plural handled in the string catalog.
    private func perDayLabel(_ perDay: Decimal) -> String {
        String(localized: "\(perDay.formatMoney())/day for the next \(daysUntilPayday) days")
    }

    /// The cycle's income split three ways — spent (tint), bills still due (hatched), and what's left
    /// (status colour). The middle fills the gap, so the three widths always sum to the bar.
    @ViewBuilder
    private func safeToSpendBar(status: SafeToSpendStatus, tone: Color) -> some View {
        if status == .setup {
            hatchedCapsule()
        } else {
            let denom = max(cycleIncome, cycleSpent + billsStillDue)
            let spentW = HomeView.fraction(cycleSpent, of: denom)
            let tailW = HomeView.fraction(safeToSpend, of: denom)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Palette.tint.opacity(0.85))
                        .frame(width: max(0, geo.size.width * spentW))
                    hatchedCapsule().frame(maxWidth: .infinity)
                    if tailW > 0 {
                        Capsule().fill(tone).frame(width: max(6, geo.size.width * tailW))
                    }
                }
            }
        }
    }

    /// The inset grouped list under the bar: the three figures Safe to spend is derived from.
    private func safeToSpendList(status: SafeToSpendStatus) -> some View {
        VStack(spacing: 0) {
            safeToSpendRow(
                swatch: RoundedRectangle(cornerRadius: 2.5).fill(Palette.tint),
                title: "Spent this cycle",
                subtitle: "\(String(localized: "\(cycleReceiptCount) receipts")) · \(cycleRangeLabel)",
                value: cycleSpent.formatMoney())
            Divider().overlay(Palette.separator)
            safeToSpendRow(
                swatch: hatchSwatch,
                title: "Bills still due",
                subtitle: billsPaidThisCycle > 0
                    ? String(localized: "\(billsPaidThisCycle.formatMoney()) already paid") : nil,
                value: billsStillDue.formatMoney())
            Divider().overlay(Palette.separator)
            safeToSpendRow(
                swatch: Color.clear,
                title: "Income this cycle", titleBold: true,
                subtitle: nil,
                value: status == .setup ? String(localized: "Not set") : cycleIncome.formatMoney(),
                valueBold: true,
                valueColor: status == .setup ? Palette.tint : Palette.label)
        }
        .padding(.vertical, 2)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func safeToSpendRow(
        swatch: some View, title: LocalizedStringKey, titleBold: Bool = false,
        subtitle: String? = nil, value: String, valueBold: Bool = false,
        valueColor: Color = Palette.label
    ) -> some View {
        HStack(spacing: 11) {
            swatch.frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 16, weight: titleBold ? .semibold : .regular))
                    .foregroundStyle(Palette.label)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondaryLabel)
                }
            }
            Spacer(minLength: 8)
            Text(value).font(.system(size: 17, weight: valueBold ? .bold : .semibold))
                .foregroundStyle(valueColor).lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    @ViewBuilder
    private func safeToSpendFoot(_ status: SafeToSpendStatus) -> some View {
        if status == .setup {
            Text("Income lives in the Budget tab · about a minute to add.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        } else if cycleIncome > 0 {
            Text("Both come out of \(cycleIncome.formatMoney()) income this cycle.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A hatched capsule for the bar's "bills still due" segment (mockup `--label3` diagonal stripes).
    private func hatchedCapsule() -> some View {
        Capsule().fill(.clear)
            .overlay(HatchStripes().stroke(Palette.tertiaryLabel, lineWidth: 2).clipShape(Capsule()))
            .overlay(Capsule().strokeBorder(Palette.tertiaryLabel, lineWidth: 0.5))
    }
    /// The 8×8 hatched swatch keying the "Bills still due" list row to the bar segment.
    private var hatchSwatch: some View {
        RoundedRectangle(cornerRadius: 2.5).fill(.clear)
            .overlay(HatchStripes().stroke(Palette.tertiaryLabel, lineWidth: 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 2.5)))
            .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(Palette.tertiaryLabel, lineWidth: 0.5))
    }

    /// The period selector on the gradient hero card: white-on-hero chrome.
    private var periodPill: some View {
        periodMenu {
            HStack(spacing: 5) {
                Text(period.label).font(.caption).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(.white.opacity(0.22), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
        }
    }

    /// The same period selector styled for the glass Safe-to-spend card: label-coloured text on a
    /// neutral `--fill` pill (the mockup's treatment), since white-on-glass wouldn't read.
    private var periodPillGlass: some View {
        periodMenu {
            HStack(spacing: 4) {
                Text(period.label).font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Palette.fill, in: Capsule())
        }
    }

    /// The shared period menu (as Insights / History use): the single-month + multi-month options,
    /// then "All time" below a divider, mirroring the Android filter. Only the pill chrome differs
    /// between the gradient hero and the glass Safe-to-spend card.
    private func periodMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            Picker("Period", selection: $period) {
                ForEach([HomePeriod.thisMonth, .lastMonth, .last3, .last6]) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Picker("Period", selection: $period) {
                Text(HomePeriod.allTime.label).tag(HomePeriod.allTime)
            }
            .pickerStyle(.inline)
        } label: {
            label()
        }
        .accessibilityLabel("Spending period")
    }

    /// The lower half of the hero, which changes by period: the planned-bills strip / budget bar for a
    /// single month; per-month bars + a monthly average for multi-month; a monthly average for all time.
    @ViewBuilder
    private var heroDetail: some View {
        let monthlyBudget = budget(Budget.monthlyKey)
        switch period {
        case .thisMonth:
            if monthBills > 0 {
                billsBlock
            } else if let mb = monthlyBudget {
                heroBudgetBar(spent: periodSpent, budget: mb) {
                    Text("\(Int(Self.fraction(periodSpent, of: mb) * 100))% of monthly budget")
                }
            } else {
                Text("Set a budget to track your spending")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        case .lastMonth:
            if let mb = monthlyBudget {
                heroBudgetBar(spent: periodSpent, budget: mb) {
                    Text("\(Int(Self.fraction(periodSpent, of: mb) * 100))% of last month's budget")
                }
            } else {
                Text("Set a budget to track your spending")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        case .last3, .last6:
            heroMonthlyBars
            heroAverage(note: String(localized: "Monthly budget and planned bills apply to a single month."))
        case .allTime:
            heroAverage(note: allTimeNote)
        }
    }

    private func heroBudgetBar(spent: Decimal, budget: Decimal, @ViewBuilder label: () -> Text) -> some View {
        VStack(spacing: 0) {
            ProgressBarView(fraction: Self.fraction(spent, of: budget), color: .white.opacity(0.85),
                            height: 5, track: .white.opacity(0.22))
            HStack {
                label()
                Spacer()
                Text("\((budget - spent).formatMoney()) left")
            }
            .font(.caption2).foregroundStyle(.white.opacity(0.65)).padding(.top, 5)
        }
    }

    /// A bar per whole pay-cycle month in the window (last 3 / 6), scaled to the busiest month.
    private var heroMonthlyBars: some View {
        let months = period.monthsBack ?? 3
        let mf = DateFormatter(); mf.dateFormat = "MMM"
        let bars: [(label: String, value: Double)] = (0..<months).reversed().map { back in
            let w = PayCycle.monthInterval(startDay: monthStartDay, offset: -back)
            let spent = receipts.filter { w.contains($0.createdAt) }.reduce(Decimal.zero) { $0 + $1.paidTotal }
            let label = mf.string(from: PayCycle.month(.now, startDay: monthStartDay, offset: -back).start)
            return (label, (spent as NSDecimalNumber).doubleValue)
        }
        let maxV = bars.map(\.value).max() ?? 1
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, b in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.62))
                        .frame(height: CGFloat(16 + 30 * (maxV > 0 ? b.value / maxV : 0)))
                    Text(b.label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .padding(.bottom, 12)
    }

    private func heroAverage(note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(.white.opacity(0.24)).frame(height: 1).padding(.bottom, 4)
            HStack(alignment: .firstTextBaseline) {
                Text("Monthly average").font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.78))
                Spacer()
                Text(monthlyAverage.formatMoney())
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
            }
            Text(note).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Period helpers

    /// The "N receipts · …" descriptor under the hero total: a month name, a month range, or "since X".
    private var periodDescriptor: String {
        let cal = Calendar.current
        switch period {
        case .thisMonth: return Self.monthLabel(.now, startDay: monthStartDay)
        case .lastMonth:
            let d = cal.date(byAdding: .month, value: -1, to: .now) ?? .now
            return Self.monthLabel(d, startDay: monthStartDay)
        case .last3, .last6:
            let w = periodWindow(period)
            let last = cal.date(byAdding: .day, value: -1, to: w.end) ?? w.end
            let m = DateFormatter(); m.dateFormat = "MMM"
            let y = DateFormatter(); y.dateFormat = "yyyy"
            return "\(m.string(from: w.start)) – \(m.string(from: last)) \(y.string(from: last))"
        case .allTime:
            guard let earliest = receipts.map(\.createdAt).min() else { return String(localized: "all time") }
            let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
            return String(localized: "since \(f.string(from: earliest))")
        }
    }

    /// Whole months spanned by the window, for the monthly-average denominator.
    private var periodMonthCount: Int {
        if let m = period.monthsBack { return m }
        guard let earliest = receipts.map(\.createdAt).min() else { return 1 }
        let cal = Calendar.current
        let a = PayCycle.month(earliest, startDay: monthStartDay).start
        let b = PayCycle.month(.now, startDay: monthStartDay).start
        return max(1, (cal.dateComponents([.month], from: a, to: b).month ?? 0) + 1)
    }

    private var monthlyAverage: Decimal {
        let months = periodMonthCount
        return months > 0 ? periodSpent / Decimal(months) : periodSpent
    }

    private var allTimeNote: String {
        guard let earliest = receipts.map(\.createdAt).min() else {
            return String(localized: "All your spending so far.")
        }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
        return String(localized: "\(periodMonthCount) months tracked · first receipt \(f.string(from: earliest))")
    }

    // MARK: - Bills strip (mockup "1b planned strip")

    /// Actual spend paired with this month's planned recurring bills: a two-segment strip (solid
    /// spent, hatched planned), a legend, and the combined "With bills" total. The hatching keeps
    /// the planned portion visually lighter than money already spent.
    private var billsBlock: some View {
        let withBills = periodSpent + monthBills
        let spentShare = Self.fraction(periodSpent, of: withBills)

        return VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: max(0, geo.size.width * spentShare - 1))
                    hatchedFill(in: Capsule())
                }
            }
            .frame(height: 6)
            .padding(.bottom, 10)

            legendRow(swatch: AnyView(RoundedRectangle(cornerRadius: 2.5).fill(.white.opacity(0.85))),
                      label: "Spent", value: periodSpent.formatMoney())
            legendRow(swatch: AnyView(hatchedFill(in: RoundedRectangle(cornerRadius: 2.5))),
                      label: "Bills · planned", value: monthBills.formatMoney(), valueOpacity: 0.9)
                .padding(.top, 6)

            Rectangle().fill(.white.opacity(0.25)).frame(height: 1)
                .padding(.top, 10).padding(.bottom, 8)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("With bills").font(.system(size: 13, weight: .bold))
                Spacer(minLength: 0)
                Text(withBills.formatMoney())
                    .font(.system(size: 17, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(.white)

            Text("Bills are planned — not yet spent.")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                .padding(.top, 6)
        }
    }

    private func legendRow(swatch: AnyView, label: LocalizedStringKey, value: String,
                           valueOpacity: Double = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                swatch.frame(width: 8, height: 8)
                Text(label).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.78))
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(valueOpacity)).lineLimit(1)
        }
    }

    /// The mockup's hatched "planned" texture: thin 135° white stripes inside a stroked shape.
    private func hatchedFill<S: InsettableShape>(in shape: S) -> some View {
        shape.fill(.clear)
            .overlay(HatchStripes().stroke(.white.opacity(0.55), lineWidth: 2).clipShape(shape))
            .overlay(shape.strokeBorder(.white.opacity(0.4), lineWidth: 1))
    }

    /// Diagonal 135° stripe lines covering the given rect.
    private struct HatchStripes: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let step: CGFloat = 4.5
            var x = rect.minX - rect.height
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += step
            }
            return p
        }
    }

    // MARK: - Budgets

    private var budgetsCard: some View {
        // A single budget period is active — Monthly wins if both or neither is set — so Home shows
        // just the active limit (Android's BudgetProgressCard), the inverse of the Budget screen's
        // Monthly/Weekly toggle where the user picks the period.
        let monthly = budget(Budget.monthlyKey)
        let weekly = budget(Budget.weeklyKey)
        let showMonthly = monthly != nil || weekly == nil
        return VStack(spacing: 14) {
            HStack {
                Text("Budgets").font(.headline)
                Spacer()
                Button { selectTab?(.budget) } label: {
                    Text("See All").font(.subheadline).foregroundStyle(Palette.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11y.Home.seeAllBudgets)
            }
            if showMonthly, let m = monthly {
                // Period-scoped spend (period filter) + rollover carry, but carry-in only applies to
                // the current period, so it shows only for "this month".
                budgetRow(title: "Monthly", spent: periodSpent, limit: m,
                          carried: period == .thisMonth ? monthlyCarried : 0)
            } else if let w = weekly {
                budgetRow(title: "Weekly", spent: weekSpent, limit: w)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentCard(cornerRadius: 16)
    }

    // MARK: - Upcoming bills

    /// Any recurring bill not yet marked paid for its current occurrence — gates the card below.
    private var hasUpcomingBills: Bool {
        recurrings.contains { !$0.isIncome && !$0.isPaidThisCycle(startDay: monthStartDay) }
    }

    /// Recurring bills due soon (moved here from Insights): each unpaid bill, soonest due-day first,
    /// with its own amount — date-based, independent of the Home period filter. Matches Android's Home
    /// Upcoming bills section, which sits directly below the budget card.
    private var upcomingBillsCard: some View {
        let sorted = recurrings
            .filter { !$0.isIncome && !$0.isPaidThisCycle(startDay: monthStartDay) }
            .sorted { $0.dueDay < $1.dueDay }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Upcoming bills").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(sorted.enumerated()), id: \.element.persistentModelID) { idx, b in
                    HStack(spacing: 12) {
                        CategoryTile(category: b.category.isEmpty ? Categories.defaultName : b.category, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.label).font(.subheadline)
                            Text(BudgetView.cadenceSubtitle(b)).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                        }
                        Spacer()
                        Text("−\(b.amount.formatMoney())").font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Palette.bad)
                    }
                    .padding(.vertical, 8)
                    if idx < sorted.count - 1 { Divider() }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private var weekSpent: Decimal {
        let cal = Calendar.current
        return receipts
            .filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .weekOfYear) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }

    private var lastWeekSpent: Decimal {
        let cal = Calendar.current
        guard let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now) else { return 0 }
        return receipts
            .filter { cal.isDate($0.createdAt, equalTo: lastWeek, toGranularity: .weekOfYear) }
            .reduce(.zero) { $0 + $1.paidTotal }
    }

    // MARK: - Week comparison

    /// "This week" quick stat: the week's spend with a delta vs last week (Android's
    /// QuickStatsStrip). Only rendered when there was spending last week to compare against.
    private var weekCard: some View {
        let delta = Self.fraction(weekSpent - lastWeekSpent, of: lastWeekSpent)
        let up = weekSpent > lastWeekSpent
        return VStack(alignment: .leading, spacing: 6) {
            Text("This week")
                .font(.caption).textCase(.uppercase).tracking(0.6)
                .foregroundStyle(Palette.secondaryLabel)
            Text(weekSpent.formatMoney())
                .font(.title2).fontWeight(.bold).foregroundStyle(Palette.label)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .bold))
                Text("\(abs(Int((delta * 100).rounded())))% vs last week")
                    .font(.caption).fontWeight(.medium)
            }
            .foregroundStyle(up ? Palette.bad : Palette.good)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentCard(cornerRadius: 16)
    }

    private func budgetRow(title: LocalizedStringKey, spent: Decimal, limit: Decimal, carried: Decimal = 0) -> some View {
        let effective = limit + carried
        let frac = Self.fraction(spent, of: effective)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        return VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                if carried > 0 {
                    Text("+\(carried.formatMoney())")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(Palette.good)
                }
                Text("\(spent.formatMoney()) / \(effective.formatMoney())")
                    .font(.caption).fontWeight(.semibold).foregroundStyle(color)
            }
            ProgressBarView(fraction: frac, color: color)
        }
    }

    // MARK: - Recent receipts

    private var recentReceiptsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recent Receipts")
                    .font(.caption).textCase(.uppercase)
                    .foregroundStyle(Palette.secondaryLabel)
                    .tracking(0.6)
                Spacer()
                Button { selectTab?(.history) } label: {
                    Text("See All").font(.subheadline).foregroundStyle(Palette.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11y.Home.seeAllReceipts)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            if periodReceipts.isEmpty {
                emptyReceipts
            } else {
                VStack(spacing: 0) {
                    let recent = Array(periodReceipts.prefix(5))
                    ForEach(Array(recent.enumerated()), id: \.element.persistentModelID) { idx, r in
                        NavigationLink { ReceiptDetailView(receipt: r) } label: { ReceiptRowView(receipt: r) }
                            .buttonStyle(.plain)
                        if idx < recent.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .contentCard(cornerRadius: 14)
            }
        }
        .accessibilityIdentifier(A11y.Home.recentReceipts)
    }

    private var emptyReceipts: some View {
        VStack(spacing: 8) {
            Image(systemName: "receipt")
                .font(.system(size: 32)).foregroundStyle(Palette.tertiaryLabel)
            Text("No receipts yet")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Text("Tap Scan to add your first one")
                .font(.caption).foregroundStyle(Palette.tertiaryLabel)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .contentCard(cornerRadius: 14)
    }

    // MARK: - Helpers

    static func fraction(_ value: Decimal, of total: Decimal) -> Double {
        guard total > 0 else { return 0 }
        return (value / total as NSDecimalNumber).doubleValue
    }

    /// "June 2026" — named for the pay-cycle month's opening month (so a cycle running 25 Jun–24 Jul
    /// reads as June), which is the calendar month when `startDay == 1`.
    static func monthLabel(_ date: Date, startDay: Int = PayCycle.startDay) -> String {
        let start = PayCycle.month(date, startDay: startDay).start
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: start)
    }

    /// "12 of 30 days" — day count within the current pay-cycle month, not the calendar month.
    static func daysProgress(startDay: Int = PayCycle.startDay) -> String {
        let cal = Calendar.current
        let (start, end) = PayCycle.month(.now, startDay: startDay)
        let startDay0 = cal.startOfDay(for: start)
        let total = (cal.dateComponents([.day], from: startDay0, to: cal.startOfDay(for: end)).day ?? 29) + 1
        let elapsed = min(total, (cal.dateComponents([.day], from: startDay0, to: cal.startOfDay(for: .now)).day ?? 0) + 1)
        return String(localized: "\(elapsed) of \(total) days")
    }
}

/// Circular initials avatar shown in the nav bar / Account header.
struct AvatarView: View {
    let initials: String
    var size: CGFloat = 30
    var fontSize: CGFloat = 12
    var body: some View {
        Circle()
            .fill(Palette.tint)
            .frame(width: size, height: size)
            .overlay(Text(initials).font(.system(size: fontSize, weight: .semibold)).foregroundStyle(.white))
    }
}

/// One receipt row: store avatar, name + date/items, amount + discount, chevron.
struct ReceiptRowView: View {
    let receipt: Receipt
    /// When true the trailing glyph is a disclosure chevron (down/up) for History's expand-in-place,
    /// instead of the default navigate-forward chevron used on Home.
    var expandable = false
    var expanded = false
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue

    var body: some View {
        HStack(spacing: 12) {
            StoreAvatar(store: receipt.store)
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.store).font(.body).foregroundStyle(Palette.label)
                Text("\(dateLabel(receipt.date)) · \(itemCountLabel(receipt.items.count))")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(receipt.paidTotal.formatMoney()).font(.body).fontWeight(.semibold)
                    .foregroundStyle(Palette.label)
                if receipt.discount > 0 {
                    Text("−\(receipt.discount.formatMoney())")
                        .font(.caption).foregroundStyle(Palette.good)
                }
            }
            Image(systemName: expandable ? (expanded ? "chevron.up" : "chevron.down") : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(A11y.receiptRow)
    }

    private func dateLabel(_ date: Date) -> String {
        (DateFormatOption(rawValue: dateFormatRaw) ?? .system).short(date)
    }
}
