//
//  DebtPayoffView.swift
//  Budgetty
//
//  The Debt payoff planner: add your debts, pick snowball or avalanche, nudge the extra-per-month, and
//  see your debt-free date, the interest saved vs minimums, the balance-to-zero chart, and the payoff
//  order. Purely a planning tool — nothing is linked to an account. Android parity: `DebtPayoffScreen`
//  + `DebtsViewModel`; the payoff math is pure (`DebtPayoffSimulator`). Figures use `formatMoneyRaw`.
//

import SwiftUI
import SwiftData

private let extraStep = 25
private let extraMax = 500
private let debtEmojis = ["💳", "🏠", "🚗", "🎓", "🛍️", "💰", "🏥", "📱"]

struct DebtPayoffView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Debt.createdAt) private var debts: [Debt]

    @State private var strategy: PayoffStrategy = .avalanche
    @State private var extra = 150
    @State private var editing: Debt?
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if debts.isEmpty {
                    emptyState
                } else {
                    let plan = computePlan(debts: debts, extra: extra, strategy: strategy)
                    strategyToggle
                    resultCard(plan)
                    compareRow(plan)
                    PayoffChart(plan: plan).frame(height: 120)
                        .padding(16).contentCard(cornerRadius: 22)
                    extraCard(plan)
                    debtListSection
                    payoffOrderSection(plan)
                    Text("Estimate only. Assumes fixed APRs and no new borrowing. Nothing is linked to an account.")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .underFloatingDock()
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Debt payoff").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { DebtEditorSheet(debt: $0) }
        .sheet(isPresented: $showAdd) { DebtEditorSheet(debt: nil) }
    }

    // MARK: Sections

    private var strategyToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassSegmentedControl(options: [PayoffStrategyOption.snowball, .avalanche],
                                  selection: Binding(
                                    get: { strategy == .snowball ? .snowball : .avalanche },
                                    set: { strategy = $0 == .snowball ? .snowball : .avalanche })) { $0.label }
            Text(strategy == .snowball ? "Smallest balance first, for quick wins that keep you going."
                                       : "Highest APR first, which costs the least interest.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.horizontal, 2)
        }
    }

    private func resultCard(_ plan: DebtPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if plan.result.clearedAll {
                Text("Debt-free by").font(.subheadline).foregroundStyle(Palette.label)
                Text(plan.debtFreeDate).font(.title).fontWeight(.bold).foregroundStyle(Palette.label)
                Text("\(plan.result.months) months · \(plan.monthsSooner) months sooner")
                    .font(.subheadline).foregroundStyle(Palette.label)
                Text("Saves \(plan.interestSaved.formatMoneyRaw()) interest vs minimums")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.good).padding(.top, 6)
            } else {
                Text("Not clearing at this rate").font(.headline).foregroundStyle(Palette.label)
                Text("Your minimums don't cover the interest. Add a little extra each month to start making progress.")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func compareRow(_ plan: DebtPlan) -> some View {
        let avalancheCheapest = plan.avalanche.totalInterest <= plan.snowball.totalInterest
        return HStack(spacing: 12) {
            compareCard("Snowball", cheapest: !avalancheCheapest, date: plan.snowballDate,
                        interest: plan.snowball.totalInterest, selected: strategy == .snowball)
            compareCard("Avalanche", cheapest: avalancheCheapest, date: plan.avalancheDate,
                        interest: plan.avalanche.totalInterest, selected: strategy == .avalanche)
        }
    }

    private func compareCard(_ name: LocalizedStringKey, cheapest: Bool, date: String,
                             interest: Decimal, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.caption).fontWeight(.bold).foregroundStyle(Palette.label)
                Text(cheapest ? "CHEAPEST" : "QUICK WINS").font(.caption2).fontWeight(.bold)
                    .foregroundStyle(cheapest ? Palette.good : Palette.secondaryLabel)
            }
            Text(date).font(.headline).foregroundStyle(Palette.label)
            Text("\(interest.formatMoneyRaw()) interest").font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(selected ? Palette.card : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(selected ? Palette.tint : Palette.separator, lineWidth: selected ? 2 : 1))
    }

    private func extraCard(_ plan: DebtPlan) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Extra each month").font(.headline).foregroundStyle(Palette.label)
                Spacer()
                Text("on top of \(plan.totalMin.formatMoneyRaw()) minimums")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            HStack {
                stepButton("minus", enabled: extra > 0) { extra = Swift.max(0, extra - extraStep) }
                Text(Decimal(extra).formatMoneyRaw()).font(.title3).fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                stepButton("plus", enabled: extra < extraMax, filled: true) { extra = Swift.min(extraMax, extra + extraStep) }
            }
            Slider(value: Binding(get: { Double(extra) },
                                  set: { extra = Int(($0 / Double(extraStep)).rounded()) * extraStep }),
                   in: 0...Double(extraMax), step: Double(extraStep))
            .tint(Palette.tint)
        }
        .padding(16).contentCard(cornerRadius: 22)
    }

    private func stepButton(_ symbol: String, enabled: Bool, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Palette.tint)
                .frame(width: 40, height: 40)
                .background(filled ? Palette.tint : .clear, in: Circle())
                .overlay(filled ? nil : Circle().strokeBorder(Palette.separator, lineWidth: 1))
                .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private var debtListSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Your debts").font(.headline).foregroundStyle(Palette.label)
                Spacer()
                Button { showAdd = true } label: { Label("Add debt", systemImage: "plus").font(.subheadline) }
                    .buttonStyle(.plain).foregroundStyle(Palette.tint)
            }
            VStack(spacing: 10) {
                ForEach(debts) { debt in
                    Button { editing = debt } label: { debtRow(debt) }.buttonStyle(.plain)
                }
            }
            .padding(16).contentCard(cornerRadius: 22)
        }
    }

    private func debtRow(_ debt: Debt) -> some View {
        HStack(spacing: 12) {
            Text(debt.emoji.isEmpty ? "💳" : debt.emoji).font(.system(size: 18))
                .frame(width: 36, height: 36).background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.name.isEmpty ? String(localized: "Debt") : debt.name).font(.body).foregroundStyle(Palette.label)
                Text("\(plainPercent(debt.aprPercent))% APR · \(debt.minPayment.formatMoneyRaw())/mo min")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer()
            Text(debt.balance.formatMoneyRaw()).font(.body).fontWeight(.bold).foregroundStyle(Palette.label)
        }
    }

    @ViewBuilder private func payoffOrderSection(_ plan: DebtPlan) -> some View {
        if !plan.order.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Payoff order · \(String(localized: strategy == .snowball ? "Snowball" : "Avalanche"))")
                    .font(.headline).foregroundStyle(Palette.label)
                VStack(spacing: 8) {
                    ForEach(Array(plan.order.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.caption).fontWeight(.bold)
                                .foregroundStyle(index == 0 ? Color.white : Palette.label)
                                .frame(width: 22, height: 22)
                                .background(index == 0 ? Palette.tint : Palette.tintSoft, in: Circle())
                            Text("\(row.emoji) \(row.name)").font(.subheadline).foregroundStyle(Palette.label)
                            Spacer()
                            Text("Paid off \(row.date)").font(.caption).foregroundStyle(Palette.secondaryLabel)
                        }
                    }
                }
                .padding(16).contentCard(cornerRadius: 22)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("📉").font(.system(size: 40))
            Text("Plan your way to zero").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("Add your debts and see when you'll be debt-free, how much interest you'll save, and which one to clear first.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
            Button { showAdd = true } label: { Text("Add your first debt").fontWeight(.semibold).ctaPill(height: 50) }
                .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 60).padding(.horizontal, 24)
    }
}

/// GlassSegmentedControl option for the strategy toggle.
private enum PayoffStrategyOption: Identifiable {
    case snowball, avalanche
    var id: Self { self }
    var label: LocalizedStringKey { self == .snowball ? "Snowball" : "Avalanche" }
}

/// The balance-to-zero chart: a dashed minimums-only baseline, the plan's filled area + line, and a
/// ring where each debt clears. Android parity: `PayoffChartCard`'s Canvas.
private struct PayoffChart: View {
    let plan: DebtPlan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Balance to zero").font(.headline).foregroundStyle(Palette.label)
                Spacer()
                Text("\(plan.totalOwed.formatMoneyRaw()) owed").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.bad)
            }
            Canvas { ctx, size in
                let plan0 = plan.result.balanceSeries.map { NSDecimalNumber(decimal: $0).doubleValue }
                let base0 = plan.baseline.balanceSeries.map { NSDecimalNumber(decimal: $0).doubleValue }
                let maxMonths = Swift.max(1, Double(plan.baseline.months))
                let maxBal = Swift.max(1, plan0.first ?? 1)
                func pt(_ i: Int, _ v: Double) -> CGPoint {
                    CGPoint(x: Double(i) / maxMonths * size.width, y: size.height - (v / maxBal * size.height))
                }
                // Baseline (dashed).
                if base0.count > 1 {
                    var p = Path()
                    for (i, v) in base0.enumerated() { let o = pt(i, v); i == 0 ? p.move(to: o) : p.addLine(to: o) }
                    ctx.stroke(p, with: .color(Palette.secondaryLabel.opacity(0.55)), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                }
                // Plan (filled area + line).
                if plan0.count > 1 {
                    var line = Path()
                    for (i, v) in plan0.enumerated() { let o = pt(i, v); i == 0 ? line.move(to: o) : line.addLine(to: o) }
                    var area = line
                    area.addLine(to: CGPoint(x: pt(plan0.count - 1, 0).x, y: size.height))
                    area.addLine(to: CGPoint(x: 0, y: size.height))
                    area.closeSubpath()
                    ctx.fill(area, with: .color(Palette.tint.opacity(0.12)))
                    ctx.stroke(line, with: .color(Palette.tint), lineWidth: 2.5)
                }
                // A ring where each debt clears.
                for m in plan.result.payoffMonthById.values where m < plan0.count {
                    let o = pt(m, plan0[m])
                    ctx.fill(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)), with: .color(Palette.card))
                    ctx.stroke(Path(ellipseIn: CGRect(x: o.x - 4, y: o.y - 4, width: 8, height: 8)), with: .color(Palette.tint), lineWidth: 2)
                }
            }
            .frame(height: 70)
            HStack(spacing: 16) {
                legend(Palette.tint, "Your plan")
                legend(Palette.secondaryLabel.opacity(0.6), "Minimums only")
            }
        }
    }
    private func legend(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 3)
            Text(label).font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
    }
}

/// Add / edit a debt: emoji picker, four fields and a live solo-cost line. Android parity: `DebtEditorSheet`.
private struct DebtEditorSheet: View {
    let debt: Debt?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var emoji = debtEmojis[0]
    @State private var name = ""
    @State private var balanceText = ""
    @State private var aprText = ""
    @State private var minText = ""

    private var balance: Decimal { Decimal(string: balanceText) ?? 0 }
    private var apr: Decimal { Decimal(string: aprText) ?? 0 }
    private var minPay: Decimal { Decimal(string: minText) ?? 0 }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && balance > 0 && minPay > 0 }

    private var soloCost: DebtPayoffResult? {
        guard balance > 0, minPay > 0 else { return nil }
        return DebtPayoffSimulator.simulate(debts: [DebtInput(id: 0, balance: balance, aprPercent: apr, minPayment: minPay)],
                                            extraPerMonth: 0, strategy: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(debtEmojis, id: \.self) { e in
                            Button { emoji = e } label: {
                                Text(e).font(.system(size: 18)).frame(width: 38, height: 38)
                                    .background(e == emoji ? Palette.tintSoft : Palette.tertiaryBackground,
                                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }
                    PlannerNumberField(label: "Name", value: $name, labelColor: Palette.tint, numeric: false)
                    PlannerNumberField(label: "Balance owed", value: $balanceText, trailing: plannerCurrencySymbol)
                    HStack(spacing: 8) {
                        PlannerNumberField(label: "APR", value: $aprText, trailing: "%")
                        PlannerNumberField(label: "Minimum / mo", value: $minText, trailing: plannerCurrencySymbol)
                    }
                    if let solo = soloCost, solo.clearedAll {
                        Text("At the minimum only, this debt takes \(solo.months) months and costs \(solo.totalInterest.formatMoneyRaw()) in interest.")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                    if debt != nil {
                        Button(role: .destructive) { delete() } label: {
                            Text("Delete").frame(maxWidth: .infinity)
                        }.padding(.top, 6)
                    }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .navigationTitle(debt == nil ? "Add debt" : "Edit debt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(debt == nil ? "Add" : "Save") { save() }.fontWeight(.semibold).disabled(!valid)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let d = debt else { return }
        emoji = d.emoji.isEmpty ? debtEmojis[0] : d.emoji
        name = d.name
        if d.balance > 0 { balanceText = NSDecimalNumber(decimal: d.balance).stringValue }
        if d.aprPercent > 0 { aprText = NSDecimalNumber(decimal: d.aprPercent).stringValue }
        if d.minPayment > 0 { minText = NSDecimalNumber(decimal: d.minPayment).stringValue }
    }

    private func save() {
        guard valid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let d = debt {
            d.emoji = emoji; d.name = trimmed; d.balance = balance; d.aprPercent = apr; d.minPayment = minPay
        } else {
            context.insert(Debt(emoji: emoji, name: trimmed, balance: balance, aprPercent: apr, minPayment: minPay))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let d = debt { context.delete(d); try? context.save() }
        dismiss()
    }
}

// MARK: - Plan computation

private struct PayoffOrderRow { let emoji: String; let name: String; let date: String }

private struct DebtPlan {
    let result: DebtPayoffResult
    let baseline: DebtPayoffResult
    let snowball: DebtPayoffResult
    let avalanche: DebtPayoffResult
    let debtFreeDate: String
    let snowballDate: String
    let avalancheDate: String
    let monthsSooner: Int
    let interestSaved: Decimal
    let totalOwed: Decimal
    let totalMin: Decimal
    let order: [PayoffOrderRow]
}

private func monthsFromNow(_ months: Int) -> String {
    let date = Calendar.current.date(byAdding: .month, value: months, to: .now) ?? .now
    let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM yyyy"); return f.string(from: date)
}

/// APR as a plain, trailing-zero-trimmed percent string, e.g. "19.9" or "6" (no currency).
private func plainPercent(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func computePlan(debts: [Debt], extra: Int, strategy: PayoffStrategy) -> DebtPlan {
    let inputs = debts.enumerated().map { DebtInput(id: $0.offset, balance: $0.element.balance,
                                                    aprPercent: $0.element.aprPercent, minPayment: $0.element.minPayment) }
    let extraBd = Decimal(extra)
    let result = DebtPayoffSimulator.simulate(debts: inputs, extraPerMonth: extraBd, strategy: strategy)
    let baseline = DebtPayoffSimulator.simulate(debts: inputs, extraPerMonth: 0, strategy: nil)
    let snowball = DebtPayoffSimulator.simulate(debts: inputs, extraPerMonth: extraBd, strategy: .snowball)
    let avalanche = DebtPayoffSimulator.simulate(debts: inputs, extraPerMonth: extraBd, strategy: .avalanche)
    let byId = Dictionary(uniqueKeysWithValues: debts.enumerated().map { ($0.offset, $0.element) })
    let order = result.payoffMonthById.sorted { $0.value < $1.value }.compactMap { id, month -> PayoffOrderRow? in
        guard let d = byId[id] else { return nil }
        return PayoffOrderRow(emoji: d.emoji.isEmpty ? "💳" : d.emoji,
                              name: d.name.isEmpty ? String(localized: "Debt") : d.name, date: monthsFromNow(month))
    }
    return DebtPlan(result: result, baseline: baseline, snowball: snowball, avalanche: avalanche,
                    debtFreeDate: monthsFromNow(result.months), snowballDate: monthsFromNow(snowball.months),
                    avalancheDate: monthsFromNow(avalanche.months),
                    monthsSooner: Swift.max(0, baseline.months - result.months),
                    interestSaved: Swift.max(0, baseline.totalInterest - result.totalInterest),
                    totalOwed: debts.reduce(0) { $0 + $1.balance }, totalMin: debts.reduce(0) { $0 + $1.minPayment },
                    order: order)
}
