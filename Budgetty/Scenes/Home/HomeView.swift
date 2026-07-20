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

struct HomeView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.selectTab) private var selectTab
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]
    @Query private var recurrings: [Recurring]

    @AppStorage(HomeLayoutStore.orderKey) private var orderRaw = ""
    @AppStorage(HomeLayoutStore.hiddenKey) private var hiddenRaw = HomeLayoutStore.defaultHidden
    @State private var showCustomize = false

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

    private var monthReceipts: [Receipt] {
        let cal = Calendar.current
        return receipts.filter { cal.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
    }

    private var monthSpent: Decimal { monthReceipts.reduce(.zero) { $0 + $1.paidTotal } }
    private var monthSavings: Decimal { monthReceipts.reduce(.zero) { $0 + $1.discount } }

    private func budget(_ key: String) -> Decimal? {
        budgets.first { $0.key == key }.map(\.amount)
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
            .reportsDockScroll()
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
                case .totalSpent: heroCard
                case .weekComparison: if lastWeekSpent > 0 { weekCard }
                case .budgets: if hasBudget { budgetsCard }
                case .receipts: recentReceiptsSection
                }
            }
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let monthlyBudget = budget(Budget.monthlyKey)
        let frac = monthlyBudget.map { Self.fraction(monthSpent, of: $0) } ?? 0
        let left = monthlyBudget.map { $0 - monthSpent }

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Total spent")
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                // A static period label — no chevron, so it doesn't read as a tappable control.
                Text(Self.monthLabel(.now)).font(.caption).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, 6)

            // Mockup: the big figure never truncates — very large amounts scroll horizontally.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(monthSpent.formatMoney())
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 4)

            Text("\(String(localized: "\(monthReceipts.count) receipts")) · \(Self.daysProgress())")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 14)

            if monthBills > 0 {
                billsBlock
            } else if let monthlyBudget {
                ProgressBarView(fraction: frac, color: .white.opacity(0.85), height: 5,
                                track: .white.opacity(0.22))
                HStack {
                    Text("\(Int(frac * 100))% of monthly budget")
                    Spacer()
                    if let left { Text("\(left.formatMoney()) left") }
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .padding(.top, 5)
            } else {
                Text("Set a budget to track your spending")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                let _ = monthlyBudget // keep branch explicit
            }
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

    // MARK: - Bills strip (mockup "1b planned strip")

    /// Actual spend paired with this month's planned recurring bills: a two-segment strip (solid
    /// spent, hatched planned), a legend, and the combined "With bills" total. The hatching keeps
    /// the planned portion visually lighter than money already spent.
    private var billsBlock: some View {
        let withBills = monthSpent + monthBills
        let spentShare = Self.fraction(monthSpent, of: withBills)

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
                      label: "Spent", value: monthSpent.formatMoney())
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
                budgetRow(title: "Monthly", spent: monthSpent, limit: m)
            } else if let w = weekly {
                budgetRow(title: "Weekly", spent: weekSpent, limit: w)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
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

    private func budgetRow(title: LocalizedStringKey, spent: Decimal, limit: Decimal) -> some View {
        let frac = Self.fraction(spent, of: limit)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        return VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(spent.formatMoney()) / \(limit.formatMoney())")
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

            if receipts.isEmpty {
                emptyReceipts
            } else {
                VStack(spacing: 0) {
                    let recent = Array(receipts.prefix(5))
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

    static func monthLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: date)
    }

    static func daysProgress() -> String {
        let cal = Calendar.current
        let day = cal.component(.day, from: .now)
        let range = cal.range(of: .day, in: .month, for: .now)?.count ?? 30
        return String(localized: "\(day) of \(range) days")
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
            Image(systemName: "chevron.right")
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
