//
//  IncomeCards.swift
//  Budgetty
//
//  The income/recurring Insights cards (shown when there's income or bills): Income vs Spending,
//  Savings rate, Fixed vs Flexible, Upcoming bills, Income by source. Money model: everything scaled
//  to a monthly figure; Net = income − bills − spend.
//

import SwiftUI

struct IncomeInsightsCards: View {
    let income: [Recurring]
    let bills: [Recurring]
    let monthSpent: Decimal

    private var monthlyIncome: Decimal { income.reduce(.zero) { $0 + $1.monthlyEquivalent } }
    private var monthlyBills: Decimal { bills.reduce(.zero) { $0 + $1.monthlyEquivalent } }
    private var net: Decimal { monthlyIncome - monthlyBills - monthSpent }
    private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

    var body: some View {
        if !income.isEmpty || !bills.isEmpty {
            VStack(spacing: 14) {
                if monthlyIncome > 0 { incomeVsSpending; savingsRate }
                if monthlyBills > 0 || monthSpent > 0 { fixedVsFlexible }
                if !bills.isEmpty { upcomingBills }
                if !income.isEmpty { incomeBySource }
            }
        }
    }

    // MARK: - Cards

    private var incomeVsSpending: some View {
        card("Income vs Spending") {
            VStack(spacing: 10) {
                comparisonRow("Income", monthlyIncome, Palette.good)
                comparisonRow("Bills", monthlyBills, Palette.bad)
                comparisonRow("Spending", monthSpent, Palette.tint)
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

    private func comparisonRow(_ title: String, _ value: Decimal, _ color: Color) -> some View {
        let frac = monthlyIncome > 0 ? min(dbl(value) / dbl(monthlyIncome), 1) : 0
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
        let rate = monthlyIncome > 0 ? max(0, dbl(net) / dbl(monthlyIncome)) : 0
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
                    Text("You're keeping \(Int(rate * 100))% of your income this month.")
                        .font(.subheadline).foregroundStyle(Palette.label)
                    Text("\(net.formatMoney()) of \(monthlyIncome.formatMoney())")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
                Spacer()
            }
        }
    }

    private var fixedVsFlexible: some View {
        let total = dbl(monthlyBills) + dbl(monthSpent)
        let fixedFrac = total > 0 ? dbl(monthlyBills) / total : 0
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
                    legend("Fixed bills", monthlyBills, Palette.tint)
                    Spacer()
                    legend("Flexible spend", monthSpent, Palette.warn)
                }
            }
        }
    }

    private func legend(_ title: String, _ value: Decimal, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption2).foregroundStyle(Palette.secondaryLabel)
                Text(value.formatMoney()).font(.caption).fontWeight(.semibold)
            }
        }
    }

    private var upcomingBills: some View {
        card("Upcoming bills") {
            VStack(spacing: 0) {
                let sorted = bills.sorted { $0.dueDay < $1.dueDay }
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
    }

    private var incomeBySource: some View {
        card("Income by source") {
            VStack(spacing: 0) {
                let sorted = income.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
                ForEach(Array(sorted.enumerated()), id: \.element.persistentModelID) { idx, s in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.good)
                            .frame(width: 30, height: 30)
                            .overlay(Image(systemName: "dollarsign").font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                        Text(s.label).font(.subheadline)
                        Spacer()
                        Text("+\(s.monthlyEquivalent.formatMoney())").font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(Palette.good)
                    }
                    .padding(.vertical, 8)
                    if idx < sorted.count - 1 { Divider() }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
