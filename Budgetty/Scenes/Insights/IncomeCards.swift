//
//  IncomeCards.swift
//  Budgetty
//
//  The income/recurring Insights cards (shown when there's income or bills): Income vs Spending,
//  Savings rate, Fixed vs Flexible, Income by source. Income & bills scale to the SELECTED period
//  via `Recurring.windowAmount` (Android parity) and pair with that period's actual spend;
//  Net = income − bills − spend. (Upcoming bills moved to the Home screen.)
//

import SwiftUI

struct IncomeInsightsCards: View {
    let income: [Recurring]
    let bills: [Recurring]
    /// Actual spend in the selected period (paired with the period-scaled income/bills below).
    let periodSpent: Decimal
    /// The selected Insights period; income & bills scale to it via `Recurring.windowAmount`.
    let window: DateInterval

    private var periodIncome: Decimal { income.reduce(.zero) { $0 + $1.windowAmount(window) } }
    private var periodBills: Decimal { bills.reduce(.zero) { $0 + $1.windowAmount(window) } }
    private var net: Decimal { periodIncome - periodBills - periodSpent }
    private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

    var body: some View {
        if !income.isEmpty || !bills.isEmpty {
            VStack(spacing: 14) {
                if periodIncome > 0 { incomeVsSpending; savingsRate }
                if periodBills > 0 || periodSpent > 0 { fixedVsFlexible }
                if !income.isEmpty { incomeBySource }
            }
        }
    }

    // MARK: - Cards

    private var incomeVsSpending: some View {
        card("Income vs Spending") {
            VStack(spacing: 10) {
                comparisonRow("Income", periodIncome, Palette.good)
                comparisonRow("Bills", periodBills, Palette.bad)
                comparisonRow("Spending", periodSpent, Palette.tint)
                Divider()
                HStack {
                    Text("Left over").font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text(net.formatMoney()).font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(net >= 0 ? Palette.good : Palette.bad)
                }
            }
        }
    }

    private func comparisonRow(_ title: LocalizedStringKey, _ value: Decimal, _ color: Color) -> some View {
        let frac = periodIncome > 0 ? min(dbl(value) / dbl(periodIncome), 1) : 0
        return VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text(value.formatMoney()).font(.caption).fontWeight(.semibold)
            }
            ProgressBarView(fraction: frac, color: color, height: 6)
        }
    }

    private var savingsRate: some View {
        let rate = periodIncome > 0 ? max(0, dbl(net) / dbl(periodIncome)) : 0
        return card("Savings rate") {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Palette.fill, lineWidth: 10)
                    Circle().trim(from: 0, to: rate)
                        .stroke(Palette.good, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(rate * 100))%").font(.headline)
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You're keeping \(Int(rate * 100))% of your income.")
                        .font(.subheadline).foregroundStyle(Palette.label)
                    Text("\(net.formatMoney()) of \(periodIncome.formatMoney())")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
            }
        }
    }

    private var fixedVsFlexible: some View {
        let total = dbl(periodBills) + dbl(periodSpent)
        let fixedFrac = total > 0 ? dbl(periodBills) / total : 0
        return card("Fixed vs Flexible") {
            VStack(spacing: 10) {
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        Capsule().fill(Palette.tint).frame(width: geo.size.width * fixedFrac)
                        Capsule().fill(Palette.warn)
                    }
                }
                .frame(height: 10)
                HStack {
                    legend("Fixed bills", periodBills, Palette.tint)
                    Spacer()
                    legend("Flexible spend", periodSpent, Palette.warn)
                }
            }
        }
    }

    private func legend(_ title: LocalizedStringKey, _ value: Decimal, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                Text(value.formatMoney()).font(.caption).fontWeight(.semibold)
            }
        }
    }

    private var incomeBySource: some View {
        card("Income by source") {
            VStack(spacing: 0) {
                let sorted = income.sorted { $0.windowAmount(window) > $1.windowAmount(window) }
                ForEach(Array(sorted.enumerated()), id: \.element.persistentModelID) { idx, s in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.good)
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: "dollarsign").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                        Text(s.label).font(.subheadline)
                        Spacer()
                        Text("+\(s.windowAmount(window).formatMoney())").font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Palette.good)
                    }
                    .padding(.vertical, 8)
                    if idx < sorted.count - 1 { Divider() }
                }
            }
        }
    }

    private func card<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }
}
