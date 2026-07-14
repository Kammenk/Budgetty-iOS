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
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var wide = false
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]
    @Query private var budgets: [Budget]

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
                    Group {
                        if hSize == .regular {
                            if wide { wideStack } else { regularStack }
                        } else {
                            compactStack
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .reportsDockScroll()
            .trackWideLandscape($wide)
            .screenCanvas()
            // The mockup puts the brand title and the avatar on ONE row, which the system large-title
            // nav bar can't do (toolbar items sit in the small bar above the large title). So Home
            // draws its own header row and hides the navigation bar.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Custom header: the large "Budgetty" brand title with the account avatar trailing on the same
    /// baseline row, exactly as in the mockup.
    private var homeHeader: some View {
        HStack {
            Text("Budgetty")
                .font(.largeTitle).fontWeight(.bold)
            Spacer()
            NavigationLink { AccountView() } label: {
                AvatarView(initials: auth.initials, size: 36, fontSize: 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Layout

    /// iPhone: one column.
    private var compactStack: some View {
        VStack(spacing: 14) {
            heroCard
            if hasBudget { budgetsCard }
            recentReceiptsSection
        }
    }

    /// iPad portrait: hero full-width, then budgets | recent receipts side by side, capped/centered.
    private var regularStack: some View { homeStack(maxWidth: Dimens.wideContentMaxWidth) }

    /// iPad landscape: same arrangement (keeps the receipts list in a half-width column so its rows
    /// don't stretch), with a wider cap.
    private var wideStack: some View { homeStack(maxWidth: Dimens.landscapeContentMaxWidth) }

    private func homeStack(maxWidth: CGFloat) -> some View {
        VStack(spacing: Dimens.regularColumnSpacing) {
            heroCard
            if hasBudget {
                RegularColumns {
                    budgetsCard
                } right: {
                    recentReceiptsSection
                }
            } else {
                recentReceiptsSection
            }
        }
        .adaptiveReadableWidth(maxWidth)
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
                HStack(spacing: 4) {
                    Text(Self.monthLabel(.now)).font(.caption).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.bottom, 6)

            Text(monthSpent.formatMoney())
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 4)

            Text("\(monthReceipts.count) receipts · \(Self.daysProgress())")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.bottom, 14)

            if let monthlyBudget {
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

    // MARK: - Budgets

    private var budgetsCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Budgets").font(.headline)
                Spacer()
                Text("See All").font(.subheadline).foregroundStyle(Palette.tint)
            }
            if let m = budget(Budget.monthlyKey) {
                budgetRow(title: "Monthly", spent: monthSpent, limit: m)
            }
            if let w = budget(Budget.weeklyKey) {
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

    private func budgetRow(title: String, spent: Decimal, limit: Decimal) -> some View {
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
                Text("See All").font(.subheadline).foregroundStyle(Palette.tint)
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
        return "\(day) of \(range) days"
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
                Text("\(dateLabel(receipt.date)) · \(receipt.items.count) item\(receipt.items.count == 1 ? "" : "s")")
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
    }

    private func dateLabel(_ date: Date) -> String {
        (DateFormatOption(rawValue: dateFormatRaw) ?? .system).short(date)
    }
}
