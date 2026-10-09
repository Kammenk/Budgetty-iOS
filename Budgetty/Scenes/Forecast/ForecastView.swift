//
//  ForecastView.swift
//  Budgetty
//
//  Insights → Trends → Cash-flow forecast (premium). Projects the balance forward from a user-entered
//  starting balance plus the recurring income/bills and average spending, and warns before it dips
//  below a comfort line. An estimate, never a bank balance — Budgetty doesn't connect to banks.
//  Android parity: `ForecastScreen` + `ForecastViewModel`. The projection math lives in `CashFlowForecast`.
//

import SwiftUI
import SwiftData

/// Allowed forecast horizons (months), cycled by the horizon chip.
private let forecastHorizons = [3, 6, 12]

struct ForecastView: View {
    @Environment(\.selectTab) private var selectTab
    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.forecastStartBalance) private var startBalanceRaw = ""
    @AppStorage(SettingsKey.forecastComfortThreshold) private var comfortRaw = ""
    @AppStorage(SettingsKey.forecastDiscretionary) private var discretionaryRaw = ""
    @AppStorage(SettingsKey.forecastHorizonMonths) private var horizonMonths = 3

    @Query private var recurring: [Recurring]
    @Query private var items: [LineItem]

    @State private var showAssumptions = false
    @State private var showPaywall = false

    // MARK: Derived state (Android's ForecastViewModel.build)

    private var hasIncome: Bool { recurring.contains(where: \.isIncome) }
    private var hasBills: Bool { recurring.contains { !$0.isIncome } }
    private var needsData: Bool { !hasIncome || !hasBills }
    private var startBalance: Decimal? { Self.amount(startBalanceRaw) }
    private var comfort: Decimal { Self.amount(comfortRaw) ?? 0 }
    private var discretionaryOverride: Decimal? { Self.amount(discretionaryRaw) }
    private var discretionary: Decimal { discretionaryOverride ?? derivedDiscretionary }

    /// Average spend per month over the last 3 completed pay-cycle months (0 when there's no history).
    private var derivedDiscretionary: Decimal {
        let cal = Calendar.current
        let windowStart = PayCycle.month(offset: -3).start
        let windowEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: PayCycle.month(offset: -1).end)) ?? .now
        let total = items.filter { $0.purchaseDate >= windowStart && $0.purchaseDate < windowEnd }
            .reduce(Decimal.zero) { $0 + $1.lineTotal }
        return Self.round2(total / 3)
    }

    private var result: ForecastResult? {
        guard hasIncome, hasBills, let sb = startBalance else { return nil }
        let endDate = CashFlowForecast.horizonEndDate(today: .now, horizonMonths: horizonMonths)
        let events = recurring.toForecastEvents(today: .now, endDate: endDate)
        return CashFlowForecast.project(startBalance: sb, today: .now, horizonMonths: horizonMonths,
                                        events: events, monthlyDiscretionary: discretionary,
                                        comfortThreshold: comfort)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if needsData {
                    setupState
                } else if !premium {
                    lockedTeaser
                } else if startBalance == nil {
                    needsBalancePrompt
                } else if let result {
                    readyContent(result)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .underFloatingDock()
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Cash-flow forecast").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssumptions) { assumptionsSheet }
        .sheet(isPresented: $showPaywall) { NavigationStack { PaywallView() } }
    }

    // MARK: States

    private var setupState: some View {
        sectionCard {
            Text("A couple of things first").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("The forecast is built from your recurring income and bills. Add them on the Budget tab and it fills in.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            checklistRow("Add your income", done: hasIncome)
            checklistRow("Add your recurring bills", done: hasBills)
            Button { selectTab?(.budget) } label: {
                Text("Go to Budget").frame(maxWidth: .infinity).ctaPill(height: 50)
            }.buttonStyle(.plain)
        }
    }

    private func checklistRow(_ label: LocalizedStringKey, done: Bool) -> some View {
        HStack(spacing: 10) {
            Text(done ? "✓" : "•").foregroundStyle(done ? Palette.good : Palette.secondaryLabel)
            Text(label).font(.subheadline).foregroundStyle(Palette.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lockedTeaser: some View {
        sectionCard {
            Text("✦").font(.largeTitle).foregroundStyle(Palette.tint)
            Text("See where you'll be in 3 months").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("Forecast projects your balance from your income, bills and usual spending, and warns you before it dips low.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Button { showPaywall = true } label: {
                Text("Unlock Forecast").frame(maxWidth: .infinity).ctaPill(height: 50)
            }.buttonStyle(.plain)
        }
    }

    private var needsBalancePrompt: some View {
        sectionCard {
            Text("Add your current balance").font(.title3).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("The forecast starts from the balance you have today. Budgetty never connects to your bank.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Button { showAssumptions = true } label: {
                Text("Add balance").frame(maxWidth: .infinity).ctaPill(height: 50)
            }.buttonStyle(.plain)
        }
    }

    private func readyContent(_ result: ForecastResult) -> some View {
        VStack(spacing: 14) {
            Button { cycleHorizon() } label: {
                Text("Next \(horizonMonths) months").font(.caption).fontWeight(.bold)
                    .foregroundStyle(Palette.tint)
                    .padding(.horizontal, 16).padding(.vertical, 8).background(Palette.tintSoft, in: Capsule())
            }
            .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)

            sectionCard(alignment: .leading) {
                Text("Projected balance · end of \(Self.monthLabel(result.endDate))")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
                Text(result.endBalance.formatMoney()).font(.largeTitle).fontWeight(.bold).foregroundStyle(Palette.label)
                troughCallout(result)
                ForecastChart(result: result, comfortThreshold: comfort)
                    .frame(height: 150).padding(.top, 8)
            }

            sectionCard(alignment: .leading) {
                Text("Month by month").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                ForEach(result.months) { monthRow($0) }
            }

            Button { showAssumptions = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assumptions").font(.body).foregroundStyle(Palette.label)
                        Text("Start \((startBalance ?? 0).formatMoney()) · spending \(discretionary.formatMoney())/mo")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                    Spacer()
                    Text("Edit").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.tint)
                }
                .padding(16).contentCard(cornerRadius: 18)
            }.buttonStyle(.plain)

            Text("An estimate, not a bank balance. It starts from the balance you entered and assumes your recurring income, bills and average spending continue.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).padding(.horizontal, 2)
        }
    }

    private func troughCallout(_ result: ForecastResult) -> some View {
        let color = result.dipsBelowComfort ? Palette.warn : Palette.good
        let money = result.trough.formatMoney()
        let day = Self.dayLabel(result.troughDate)
        let label: LocalizedStringKey = result.dipsBelowComfort
            ? "Dips to \(money) · \(day)"
            : "Lowest point \(money) · \(day)"
        return Text(label).font(.subheadline).fontWeight(.medium).foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(0.14), in: RoundedCornerShape14())
            .padding(.top, 8)
    }

    private func monthRow(_ month: MonthProjection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Self.monthLabel(month.month)).font(.body).fontWeight(.bold).foregroundStyle(Palette.label)
                Spacer()
                Text(month.endBalance.formatMoney()).font(.body).fontWeight(.bold)
                    .foregroundStyle(month.dipsBelowComfort ? Palette.warn : Palette.good)
            }
            Text("In \(month.income.formatMoney()) · Bills \(month.bills.formatMoney()) · Spend \(month.discretionary.formatMoney())")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            if month.dipsBelowComfort {
                Text("Dips to \(month.trough.formatMoney()) · \(Self.dayLabel(month.troughDate))")
                    .font(.caption).fontWeight(.medium).foregroundStyle(Palette.warn).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }

    // MARK: Assumptions sheet

    private var assumptionsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Starting balance") {
                        TextField("0", text: $startBalanceRaw).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                } footer: {
                    Text("You enter this yourself — Budgetty doesn't connect to your bank.")
                }
                Section {
                    LabeledContent("Average monthly spending (excl. bills)") {
                        TextField(derivedDiscretionary.formatMoney(), text: $discretionaryRaw)
                            .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                    Button("Reset to \(derivedDiscretionary.formatMoney()) average") { discretionaryRaw = "" }
                        .font(.caption)
                }
                Section {
                    LabeledContent("Warn me below") {
                        TextField("0", text: $comfortRaw).multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle("Assumptions").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showAssumptions = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Helpers

    private func cycleHorizon() {
        let idx = forecastHorizons.firstIndex(of: horizonMonths) ?? 0
        horizonMonths = forecastHorizons[(idx + 1) % forecastHorizons.count]
    }

    private func sectionCard(alignment: HorizontalAlignment = .leading,
                             @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: alignment, spacing: 8) { content() }
            .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
            .padding(20).contentCard(cornerRadius: 22)
    }

    private static func amount(_ raw: String) -> Decimal? {
        let t = raw.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Decimal(string: t, locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func round2(_ d: Decimal) -> Decimal {
        var r = Decimal(); var v = d; NSDecimalRound(&r, &v, 2, .plain); return r
    }
    nonisolated static func monthLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMM yyyy"); return f.string(from: d)
    }
    nonisolated static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f.string(from: d)
    }
}

/// A continuous rounded rectangle at radius 14 — the trough callout's background.
private struct RoundedCornerShape14: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: 14, style: .continuous)
    }
}

/// The projected-balance curve: a line through the daily balances, a dashed "warn me below" comfort
/// line, a faint zero baseline, and a dot on the lowest point (amber if it dips below comfort, else
/// green). Forward-only — the whole curve is the projection — so it reads as one estimate.
struct ForecastChart: View {
    let result: ForecastResult
    let comfortThreshold: Decimal

    private static let headroom = 1.08

    var body: some View {
        let points = result.points
        let balances = points.map { NSDecimalNumber(decimal: $0.balance).doubleValue }
        let comfort = NSDecimalNumber(decimal: comfortThreshold).doubleValue
        let maxV = (balances.max() ?? 0) * Self.headroom
        let minV = Swift.min(0.0, balances.min() ?? 0, comfort)
        let range = (maxV - minV) > 0 ? (maxV - minV) : 1
        let lastIndex = points.count - 1
        let troughIndex = points.firstIndex { $0.date == result.troughDate } ?? 0
        let troughColor = result.dipsBelowComfort ? Palette.warn : Palette.good

        return Canvas { ctx, size in
            guard lastIndex >= 1 else { return }
            func x(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(lastIndex) * size.width }
            func y(_ v: Double) -> CGFloat { size.height - CGFloat((v - minV) / range) * size.height }

            if minV < 0 && maxV > 0 {
                var base = Path(); base.move(to: CGPoint(x: 0, y: y(0))); base.addLine(to: CGPoint(x: size.width, y: y(0)))
                ctx.stroke(base, with: .color(Palette.separator), lineWidth: 1)
            }
            var comfortLine = Path()
            comfortLine.move(to: CGPoint(x: 0, y: y(comfort)))
            comfortLine.addLine(to: CGPoint(x: size.width, y: y(comfort)))
            ctx.stroke(comfortLine, with: .color(Palette.warn), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))

            var curve = Path()
            curve.move(to: CGPoint(x: x(0), y: y(balances[0])))
            for i in 1...lastIndex { curve.addLine(to: CGPoint(x: x(i), y: y(balances[i]))) }
            ctx.stroke(curve, with: .color(Palette.tint), style: StrokeStyle(lineWidth: 3, lineJoin: .round))

            let c = CGPoint(x: x(troughIndex), y: y(NSDecimalNumber(decimal: result.trough).doubleValue))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(troughColor))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Palette.card))
        }
    }
}
