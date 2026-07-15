//
//  InsightsExtraCards.swift
//  Budgetty
//
//  The Android-parity analysis cards from the "iOS Insights Extra Cards" mockup: Highlights
//  (rule-based narrative callouts), Period comparison (this vs the previous period), Budget
//  (budget-vs-actual for week/month periods), and Biggest purchases (top line items).
//  All period-relative; the hosting InsightsView feeds them pre-windowed data.
//

import SwiftUI

// MARK: - Highlights

/// One narrative callout row. Mirrors Android's `computeHighlights` rules.
struct InsightHighlight: Identifiable {
    enum Kind {
        case newCategory(amount: Decimal)
        case move(percent: Int, up: Bool)
        case share(percent: Int)
    }
    let id = UUID()
    let category: String
    let kind: Kind

    var emoji: String {
        switch kind {
        case .newCategory: "🎉"
        case .move(_, let up): up ? "📈" : "📉"
        case .share: "💡"
        }
    }

    /// The sentence, with the moving part bold (Android's highlight strings).
    func text(compareNoun: String) -> AttributedString {
        func bold(_ s: String) -> AttributedString {
            var a = AttributedString(s); a.font = .system(size: 14, weight: .semibold); return a
        }
        switch kind {
        case .newCategory(let amount):
            return AttributedString("First spend in ") + bold(category) + AttributedString(" — \(amount.formatMoney())")
        case .move(let percent, let up):
            return bold(category) + AttributedString(up ? " up " : " down ") + bold("\(percent)%")
                + AttributedString(" \(compareNoun)")
        case .share(let percent):
            return bold(category) + AttributedString(" made up ") + bold("\(percent)%")
                + AttributedString(" of spending")
        }
    }

    /// Up to three rule-based callouts: a brand-new category, the biggest % increase, the biggest
    /// % decrease (both ≥ 5%), and — if fewer than three so far — a category dominating ≥ 40%.
    static func compute(current: [LineItem], previous: [LineItem]) -> [InsightHighlight] {
        var curr: [String: Decimal] = [:]
        for it in current { curr[it.category, default: .zero] += it.lineTotal }
        curr = curr.filter { $0.value > 0 }
        guard !curr.isEmpty else { return [] }
        var prev: [String: Decimal] = [:]
        for it in previous { prev[it.category, default: .zero] += it.lineTotal }
        let netTotal = curr.values.reduce(Decimal.zero, +)

        func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }
        func pct(_ part: Double, _ whole: Double) -> Int { whole > 0 ? Int((part / whole * 100).rounded()) : 0 }

        var used = Set<String>()
        var out: [InsightHighlight] = []

        // 1. A brand-new category — spend now, none in the previous period — biggest first.
        if let (c, v) = curr.filter({ (prev[$0.key] ?? 0) <= 0 }).max(by: { $0.value < $1.value }) {
            out.append(InsightHighlight(category: c, kind: .newCategory(amount: v)))
            used.insert(c)
        }
        // 2. Biggest percentage increase over a category that also had spend before.
        if let (c, v) = curr
            .filter({ !used.contains($0.key) && (prev[$0.key] ?? 0) > 0 && $0.value > prev[$0.key]! })
            .max(by: { dbl($0.value - prev[$0.key]!) / dbl(prev[$0.key]!) < dbl($1.value - prev[$1.key]!) / dbl(prev[$1.key]!) }) {
            let p = pct(dbl(v - prev[c]!), dbl(prev[c]!))
            if p >= 5 { out.append(InsightHighlight(category: c, kind: .move(percent: p, up: true))); used.insert(c) }
        }
        // 3. Biggest percentage decrease.
        if let (c, v) = curr
            .filter({ !used.contains($0.key) && (prev[$0.key] ?? 0) > 0 && $0.value < prev[$0.key]! })
            .min(by: { dbl($0.value - prev[$0.key]!) / dbl(prev[$0.key]!) < dbl($1.value - prev[$1.key]!) / dbl(prev[$1.key]!) }) {
            let p = pct(dbl(prev[c]!) - dbl(v), dbl(prev[c]!))
            if p >= 5 { out.append(InsightHighlight(category: c, kind: .move(percent: p, up: false))); used.insert(c) }
        }
        // 4. A category that dominated the period (≥ 40% of net spend).
        if out.count < 3, let (c, v) = curr.max(by: { $0.value < $1.value }) {
            let p = pct(dbl(v), dbl(netTotal))
            if !used.contains(c) && p >= 40 {
                out.append(InsightHighlight(category: c, kind: .share(percent: p)))
            }
        }
        return Array(out.prefix(3))
    }
}

/// ✨ Highlights — emoji-led narrative rows (mockup).
struct HighlightsCard: View {
    let highlights: [InsightHighlight]
    let compareNoun: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("✨").font(.system(size: 18))
                Text("Highlights").font(.headline)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights) { h in
                    HStack(alignment: .top, spacing: 10) {
                        Text(h.emoji).font(.system(size: 16))
                        Text(h.text(compareNoun: compareNoun))
                            .font(.system(size: 14)).foregroundStyle(Palette.label)
                            .lineSpacing(2)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }
}

// MARK: - Period comparison

/// This period vs the previous one: delta pill, two amount tiles with mini bars, plain-English
/// footer. Only meaningful (and only shown) when the previous period had spend.
struct PeriodComparisonCard: View {
    let currentTotal: Decimal
    let previousTotal: Decimal
    let currentLabel: String   // "This month"
    let previousLabel: String  // "Last month"
    let compareNoun: String    // "vs last month"

    private var deltaPercent: Int {
        let prev = (previousTotal as NSDecimalNumber).doubleValue
        let curr = (currentTotal as NSDecimalNumber).doubleValue
        guard prev > 0 else { return 0 }
        return Int(((curr - prev) / prev * 100).rounded())
    }

    var body: some View {
        let down = currentTotal <= previousTotal
        let color = down ? Palette.good : Palette.bad
        let maxTotal = max(currentTotal, previousTotal)

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Period comparison").font(.headline)
                    Text(compareNoun).font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: down ? "arrow.down" : "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(abs(deltaPercent))%").font(.caption).fontWeight(.semibold)
                }
                .foregroundStyle(color)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.14), in: Capsule())
            }

            HStack(spacing: 12) {
                comparisonTile(label: currentLabel, amount: currentTotal, highlight: true,
                               fraction: HomeView.fraction(currentTotal, of: maxTotal))
                comparisonTile(label: previousLabel, amount: previousTotal, highlight: false,
                               fraction: HomeView.fraction(previousTotal, of: maxTotal))
            }

            footerText(down: down)
                .font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private func footerText(down: Bool) -> Text {
        let diff = abs(currentTotal - previousTotal)
        return Text("You've spent ")
            + Text("\(diff.formatMoney()) \(down ? "less" : "more")")
                .fontWeight(.semibold).foregroundColor(down ? Palette.good : Palette.bad)
            + Text(" \(compareNoun.hasPrefix("vs ") ? "than" : "than") \(compareNoun.replacingOccurrences(of: "vs ", with: "")).")
    }

    private func comparisonTile(label: String, amount: Decimal, highlight: Bool, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.secondaryLabel)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(amount.formatMoney())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(highlight ? Palette.label : Palette.secondaryLabel)
            }
            ProgressBarView(fraction: fraction,
                            color: highlight ? Palette.tint : Palette.tertiaryLabel,
                            height: 5, track: Palette.fill)
                .padding(.top, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? Palette.tintSoft : Palette.fill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Budget vs actual

/// Spend against the period's budget (monthly budget on month periods, weekly on week periods),
/// with a status-colored bar and a days-left caption for the in-progress period.
struct BudgetVsActualCard: View {
    let spent: Decimal
    let budget: Decimal
    let daysLeft: Int?

    var body: some View {
        let frac = HomeView.fraction(spent, of: budget)
        let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
        let left = budget - spent

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Budget").font(.headline)
                Spacer()
                if let daysLeft {
                    Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                        .font(.system(size: 13)).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(spent.formatMoney())
                    .font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.label)
                    .lineLimit(1)
                Text("of \(budget.formatMoney())")
                    .font(.system(size: 15)).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.bottom, 10)

            ProgressBarView(fraction: frac, color: color, height: 8, track: Palette.fill)

            HStack {
                Text("\(Int((frac * 100).rounded()))% used")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
                Spacer()
                if left >= 0 {
                    Text("\(left.formatMoney()) left")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondaryLabel)
                } else {
                    Text("\(abs(left).formatMoney()) over")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.bad)
                }
            }
            .padding(.top, 7)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }
}

// MARK: - Biggest purchases

/// The period's top line items by line total: category-colored emoji tile, item name,
/// "store · date" caption, amount.
struct BiggestPurchasesCard: View {
    /// (item, store) pairs, already sorted largest-first and capped.
    let purchases: [(item: LineItem, store: String)]
    var colorFor: (String) -> Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Biggest purchases").font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(purchases.enumerated()), id: \.element.item.persistentModelID) { idx, entry in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(colorFor(entry.item.category))
                            .frame(width: 36, height: 36)
                            .overlay(Text(Categories.emoji(for: entry.item.category)).font(.system(size: 18)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.item.name).font(.system(size: 16)).foregroundStyle(Palette.label)
                                .lineLimit(1)
                            Text(caption(entry))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondaryLabel)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(entry.item.lineTotal.formatMoney())
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.label)
                    }
                    .padding(.vertical, 10)
                    if idx < purchases.count - 1 { Divider() }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    private func caption(_ entry: (item: LineItem, store: String)) -> String {
        let date = entry.item.createdAt.formatted(.dateTime.day().month(.abbreviated))
        return entry.store.isEmpty ? date : "\(entry.store) · \(date)"
    }
}
