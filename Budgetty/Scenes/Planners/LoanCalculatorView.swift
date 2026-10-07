//
//  LoanCalculatorView.swift
//  Budgetty
//
//  The Loan calculator: scratch inputs (amount, APR, term) feeding a closed-form amortisation. Nothing
//  is persisted — a free what-if tool. Monthly payment is the hero, then total interest/paid, a
//  principal-vs-interest split and a by-year breakdown + table. Android parity: `LoanCalculatorScreen`.
//  Planner figures use `formatMoneyRaw` (scratch values stay readable even in Hide-amounts mode).
//

import SwiftUI

struct LoanCalculatorView: View {
    private enum Term: Int, CaseIterable, Identifiable { case y3 = 3, y5 = 5, y7 = 7; var id: Int { rawValue } }

    @State private var amountText = "15000"
    @State private var aprText = "6.9"
    @State private var term: Term = .y5

    private var result: LoanResult {
        LoanCalculator.compute(amount: Decimal(string: amountText) ?? 0,
                               aprPercent: Decimal(string: aprText) ?? 0, years: term.rawValue)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                inputsCard
                heroCard
                statTiles
                whereCard
                amortisationCard
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .underFloatingDock()
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Loan calculator").navigationBarTitleDisplayMode(.inline)
    }

    private var inputsCard: some View {
        VStack(spacing: 10) {
            PlannerNumberField(label: "Loan amount", value: $amountText, labelColor: Palette.tint,
                               trailing: plannerCurrencySymbol)
            PlannerNumberField(label: "Interest rate (APR)", value: $aprText, trailing: "%")
            VStack(alignment: .leading, spacing: 6) {
                Text("Term").font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
                GlassSegmentedControl(options: Term.allCases, selection: $term) { "\($0.rawValue) yr" }
            }
        }
        .padding(16).contentCard(cornerRadius: 22)
    }

    private var heroCard: some View {
        VStack(spacing: 4) {
            Text("Monthly payment").font(.subheadline).foregroundStyle(Palette.label)
            Text(result.monthlyPayment.formatMoneyRaw()).font(.system(size: 34, weight: .bold)).foregroundStyle(Palette.label)
            Text("for \(result.months) months").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statTiles: some View {
        HStack(spacing: 12) {
            statTile("Total interest", result.totalInterest.formatMoneyRaw(), Palette.bad)
            statTile("Total paid", result.totalPaid.formatMoneyRaw(), Palette.label)
        }
    }

    private func statTile(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Palette.secondaryLabel)
            Text(value).font(.headline).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16).contentCard(cornerRadius: 18)
    }

    private var whereCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where your money goes").font(.headline).foregroundStyle(Palette.label)
            SplitBar(principalPercent: result.principalPercent)
            HStack {
                legendDot(Palette.tint, "Principal \(result.principalPercent)%")
                Spacer()
                legendDot(Palette.bad, "Interest \(result.interestPercent)%")
            }
            if result.years.count > 1 {
                Text("By year").font(.caption).fontWeight(.bold).foregroundStyle(Palette.label).padding(.top, 6)
                YearlyBars(years: result.years)
            }
        }
        .padding(16).contentCard(cornerRadius: 22)
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
    }

    private var amortisationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Amortisation").font(.headline).foregroundStyle(Palette.label)
            HStack(spacing: 6) {
                tableCell("Year", header: true, year: true)
                tableCell("Principal", header: true, end: true)
                tableCell("Interest", header: true, end: true)
                tableCell("Balance", header: true, end: true)
            }
            ForEach(result.years) { y in
                HStack(spacing: 6) {
                    tableCell("\(y.year)", bold: true, year: true)
                    tableCell(y.principalPaid.formatMoneyRaw(), end: true)
                    tableCell(y.interestPaid.formatMoneyRaw(), end: true, color: Palette.bad)
                    tableCell(y.endBalance.formatMoneyRaw(), end: true, bold: true)
                }
            }
            Text("Estimate only. Lenders may add fees or round differently.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.top, 4)
        }
        .padding(16).contentCard(cornerRadius: 22)
    }

    private func tableCell(_ text: String, header: Bool = false, end: Bool = false,
                           bold: Bool = false, color: Color = Palette.label, year: Bool = false) -> some View {
        Text(text)
            .font(header ? .caption2 : .caption)
            .fontWeight(header || bold ? .bold : .regular)
            .foregroundStyle(header ? Palette.secondaryLabel : color)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: year ? 34 : nil, alignment: year ? .leading : (end ? .trailing : .leading))
            .frame(maxWidth: year ? nil : .infinity, alignment: end ? .trailing : .leading)
    }
}

/// A thin two-segment bar: principal (tint) then interest (red), proportional to `principalPercent`.
private struct SplitBar: View {
    let principalPercent: Int
    var body: some View {
        let p = Swift.min(100, Swift.max(0, principalPercent))
        GeometryReader { geo in
            HStack(spacing: 2) {
                if p > 0 { Rectangle().fill(Palette.tint).frame(width: geo.size.width * CGFloat(p) / 100) }
                if p < 100 { Rectangle().fill(Palette.bad) }
            }
        }
        .frame(height: 12).clipShape(Capsule())
    }
}

/// Per-year stacked bars (interest on top of principal), each scaled to the biggest year's payments.
private struct YearlyBars: View {
    let years: [LoanYear]
    var body: some View {
        let maxYear = Swift.max(1, years.map { NSDecimalNumber(decimal: $0.principalPaid + $0.interestPaid).doubleValue }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(years) { y in
                let pH = 70 * Swift.min(1, NSDecimalNumber(decimal: y.principalPaid).doubleValue / maxYear)
                let iH = 70 * Swift.min(1, NSDecimalNumber(decimal: y.interestPaid).doubleValue / maxYear)
                VStack(spacing: 0) {
                    if iH > 0 {
                        UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4)
                            .fill(Palette.bad).frame(height: iH)
                    }
                    Rectangle().fill(Palette.tint).frame(height: pH)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 70)
    }
}
