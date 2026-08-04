//
//  WellbeingSummary.swift
//  Budgetty
//
//  The derivation layer between SwiftData and the Wellbeing screen — the Swift port of Android's
//  `WellbeingProvider.build` + `WellbeingSummary`. Pure math on top of `WellbeingEngine`: every figure
//  comes from the user's own local receipts, budgets, goals and recurring plan, so nothing leaves the
//  device. The screen, the Home banner and the Insights row all read one `WellbeingSummary`.
//
//  Not a ViewModel — the entry-point views call `WellbeingScan.run(...)` from a computed property, the
//  same pattern `SubscriptionsCard` uses for `SubscriptionScan`.
//

import Foundation
import SwiftData

/// The weekly check-in "pace card" figures (Android's `WeeklyPace`).
struct WeeklyPace {
    let spent: Decimal
    let weeklyBudget: Decimal?
    /// Spent ÷ budget, clamped 0...1 (0 when there's no weekly budget).
    let fractionUsed: Double
    /// Where the week "should" be by now (days elapsed ÷ 7), for the pace marker.
    let paceFraction: Double
    let remaining: Decimal
    let daysLeft: Int
    let deltaPercentVsLastWeek: Int?
    let onTrack: Bool
}

/// Raw figures behind one component, for the tap-to-expand explanation copy (localised in the UI).
/// Field order is load-bearing: each `ComponentDetail(...)` call below passes a contiguous ordered
/// subset, relying on the synthesized memberwise init's defaults for the rest.
struct ComponentDetail {
    var savingsRatePercent: Int? = nil
    var saved: Decimal? = nil
    var income: Decimal? = nil
    var overCount: Int? = nil
    var budgetedCount: Int? = nil
    var overspend: Decimal? = nil
    var trendPercent: Int? = nil
    var avgSpend: Decimal? = nil
    var subsMonthly: Decimal? = nil
    var subsSharePercent: Int? = nil
    var goalsOnPace: Int? = nil
    var goalsTotal: Int? = nil
}

/// A wins-strip pill. Copy is localised in the UI from `type`; `emoji` is the leading glyph.
struct WellbeingWin {
    let emoji: String
    let type: TipType
    var label: String? = nil
    var percent: Int? = nil
}

/// Everything the Wellbeing screen, the Home banner and the Insights row read — computed once by
/// `WellbeingScan.run`. Tips here are ranked but NOT yet filtered by the user's dismissals; the view
/// drops dismissed ids for the current `periodId` so dismissal survives recomposition.
struct WellbeingSummary {
    let score: WellbeingScore
    let monthlyTips: [WellbeingTip]
    let weekly: WeeklyPace
    let weeklyTips: [WellbeingTip]
    let wins: [WellbeingWin]
    let detail: [WellbeingComponentKey: ComponentDetail]
    let receiptsLogged: Int
    let hasBudget: Bool
    /// Pay-cycle month key (e.g. "2026-06"); tip dismissals are scoped to it so tips resurface next month.
    let periodId: String
    /// "June 2026" — the nav-bar label in monthly mode.
    let monthLabel: String
    /// "22 Jun – 28 Jun" — the nav-bar label in weekly mode.
    let weekLabel: String

    var hasScore: Bool { score.hasScore }
}

// MARK: - Derivation

enum WellbeingScan {

    /// Builds the whole `WellbeingSummary` for the current pay-cycle month (plus the previous month
    /// for the trend delta) and the current Mon–Sun week. A faithful port of `WellbeingProvider.build`.
    static func run(receipts: [Receipt], budgets: [Budget], recurring: [Recurring],
                    goals: [SavingsGoal], contributions: [SavingsContribution],
                    ignoredSubs: Set<String>, today: Date = .now, monthStartDay: Int) -> WellbeingSummary {
        let cal = Calendar.current

        // ── Windowed spend helpers (pay-cycle months) ──────────────────────────────
        func monthReceipts(_ offset: Int) -> [Receipt] {
            let iv = PayCycle.monthInterval(today, startDay: monthStartDay, offset: offset)
            return receipts.filter { iv.contains($0.createdAt) }
        }
        func monthSpend(_ offset: Int) -> Decimal {
            monthReceipts(offset).reduce(Decimal.zero) { $0 + $1.paidTotal }
        }
        func netSpend(_ items: [LineItem]) -> Decimal {
            items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        }

        // Distinct calendar months with any logged item — gates subscription data + trend history.
        let monthsTracked = Set(receipts.flatMap(\.items)
            .map { cal.dateComponents([.year, .month], from: $0.createdAt) }).count

        // Subscriptions (global, from all receipts) — one charge per receipt, minus ignored merchants.
        let subScan = SubscriptionScan.run(receipts: receipts, ignored: ignoredSubs, today: today)
        let subsMonthly = subScan.monthlyTotal
        let subsCount = subScan.detected.count
        let hasSubsData = receipts.count >= WellbeingEngine.minReceiptsToScore && monthsTracked >= 1

        // Trailing monthly-spend average (previous up-to-6 months with spend), for trend + subs share.
        func avgBefore(_ offset: Int) -> Decimal? {
            let spends = (1...6).map { monthSpend(offset - $0) }.filter { $0 > 0 }
            guard !spends.isEmpty else { return nil }
            let sum = spends.reduce(Decimal.zero, +)
            return SubscriptionDetector.round2(sum / Decimal(spends.count))
        }
        func trendPercent(_ offset: Int, spend: Decimal) -> Int? {
            guard let avg = avgBefore(offset), avg > 0 else { return nil }
            return ((dbl(spend) / dbl(avg) - 1.0) * 100).roundedInt
        }

        // Budgets keyed by category, plus the overall monthly/weekly limits.
        var catBudgets: [String: Decimal] = [:]
        for b in budgets where b.key.hasPrefix("CAT:") {
            catBudgets[String(b.key.dropFirst(4))] = b.amount
        }
        let monthlyBudget = budgets.first { $0.key == Budget.monthlyKey }?.amount
        let weeklyBudget = budgets.first { $0.key == Budget.weeklyKey }?.amount
        let avgSpend = avgBefore(0)

        // Per-category trailing monthly average (over prior months that had spend).
        let monthsWithData = max(1, (1...6).filter { monthSpend(-$0) > 0 }.count)
        var catTotals: [String: Decimal] = [:]
        for off in 1...6 {
            let grouped = Dictionary(grouping: monthReceipts(-off).flatMap(\.items), by: \.category)
            for (cat, items) in grouped { catTotals[cat, default: .zero] += netSpend(items) }
        }
        let catAvg = catTotals.mapValues { SubscriptionDetector.round2($0 / Decimal(monthsWithData)) }

        // ── Per-month inputs to the engine ─────────────────────────────────────────
        func inputsFor(_ offset: Int, withDetail: Bool) -> WellbeingInputs {
            let interval = PayCycle.monthInterval(today, startDay: monthStartDay, offset: offset)
            let monthRcpts = receipts.filter { interval.contains($0.createdAt) }
            let monthItems = monthRcpts.flatMap(\.items)
            let spend = monthRcpts.reduce(Decimal.zero) { $0 + $1.paidTotal }

            let income = recurring.filter(\.isIncome).reduce(Decimal.zero) { $0 + $1.windowAmount(interval) }
            let bills = recurring.filter { !$0.isIncome }.reduce(Decimal.zero) { $0 + $1.windowAmount(interval) }
            let hasIncome = income > 0
            let saved = income - bills - spend
            let rate = hasIncome ? (dbl(saved) / dbl(income) * 100).roundedInt : 0

            let catSpend = Dictionary(grouping: monthItems, by: \.category).mapValues { netSpend($0) }
            let scopes: [(spent: Decimal, budget: Decimal)]
            if !catBudgets.isEmpty {
                scopes = catBudgets.map { (spent: catSpend[$0.key] ?? .zero, budget: $0.value) }
            } else if let mb = monthlyBudget {
                scopes = [(spent: spend, budget: mb)]
            } else {
                scopes = []
            }
            let overScopes = scopes.filter { $0.spent > $0.budget }
            let overspend = overScopes.reduce(Decimal.zero) { $0 + ($1.spent - $1.budget) }
            let budgetedTotal = scopes.reduce(Decimal.zero) { $0 + $1.budget }

            let baseline = avgSpend ?? spend
            let subsShare: Int? = {
                if !hasSubsData { return nil }
                if subsCount == 0 { return 0 }
                return baseline > 0 ? (dbl(subsMonthly) / dbl(baseline) * 100).roundedInt : nil
            }()

            let goalPaces: [GoalPace] = goals.map { g in
                let cs = contributions.filter { $0.goal?.persistentModelID == g.persistentModelID }
                let p = SavingsMath.progress(target: g.targetAmount, targetDate: g.targetDate,
                                             contributions: cs, today: today)
                return GoalPace(name: g.name, reached: p.reached, behind: p.behind)
            }

            let categories: [CategorySpend]
            if withDetail {
                let keys = Set(catSpend.keys).union(catBudgets.keys).union(catAvg.keys)
                categories = keys.map { cat in
                    CategorySpend(category: cat,
                                  current: catSpend[cat] ?? .zero,
                                  average: catAvg[cat] ?? .zero,
                                  monthlyAverage: catAvg[cat] ?? .zero,
                                  hasBudget: catBudgets[cat] != nil,
                                  count: monthItems.filter { $0.category == cat }.count)
                }
            } else {
                categories = []
            }

            return WellbeingInputs(
                hasIncome: hasIncome, savingsRatePercent: rate, income: income, saved: saved, netCashflow: saved,
                hasAnyBudget: !scopes.isEmpty, budgetedCount: scopes.count, overCount: overScopes.count,
                overspendTotal: overspend, budgetedTotal: budgetedTotal,
                trendPercent: trendPercent(offset, spend: spend),
                subsSharePercent: subsShare, subsMonthly: subsMonthly, subsCount: subsCount,
                goals: goalPaces, categories: categories, spend: spend,
                receiptsLogged: receipts.count, monthsTracked: monthsTracked)
        }

        let previousScore = WellbeingEngine.score(inputsFor(-1, withDetail: false)).score
        var current = inputsFor(0, withDetail: true)
        current.previousScore = previousScore
        let score = WellbeingEngine.score(current)
        let monthlyTips = WellbeingEngine.tips(current)

        // ── Weekly pace card + tactical tips (Mon–Sun of the current week) ──────────
        let startOfToday = cal.startOfDay(for: today)
        let weekdayToday = cal.component(.weekday, from: startOfToday)   // 1 = Sun … 7 = Sat
        let mondayOffset = (weekdayToday + 5) % 7                        // Mon = 0 … Sun = 6
        let weekStart = cal.date(byAdding: .day, value: -mondayOffset, to: startOfToday) ?? startOfToday
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let daysElapsed = mondayOffset + 1                              // Mon = 1 … Sun = 7

        func spend(from start: Date, to end: Date) -> ([Receipt], Decimal) {
            let iv = DateInterval(start: start, end: end)
            let rs = receipts.filter { iv.contains($0.createdAt) }
            return (rs, rs.reduce(Decimal.zero) { $0 + $1.paidTotal })
        }
        let weekEndExclusive = cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekEnd
        let (weekReceipts, weekSpent) = spend(from: weekStart, to: weekEndExclusive)
        let weekItems = weekReceipts.flatMap(\.items)
        let (_, lastWeekSpent) = spend(from: cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart,
                                       to: weekStart)

        let paceFraction = Double(daysElapsed) / 7.0
        let fractionUsed: Double = {
            guard let wb = weeklyBudget, wb > 0 else { return 0 }
            return min(max(dbl(weekSpent) / dbl(wb), 0), 1)
        }()
        let weekDelta: Int? = lastWeekSpent > 0
            ? ((dbl(weekSpent) / dbl(lastWeekSpent) - 1.0) * 100).roundedInt : nil
        let remaining = weeklyBudget.map { max($0 - weekSpent, 0) } ?? 0
        let weekly = WeeklyPace(spent: weekSpent, weeklyBudget: weeklyBudget, fractionUsed: fractionUsed,
                                paceFraction: paceFraction, remaining: remaining,
                                daysLeft: max(7 - daysElapsed, 0), deltaPercentVsLastWeek: weekDelta,
                                onTrack: weeklyBudget == nil || fractionUsed <= paceFraction + 0.05)

        let paced: PacedCategory? = (weeklyBudget != nil && (weeklyBudget ?? 0) > 0 && fractionUsed >= 0.7)
            ? PacedCategory(name: "", percentUsed: (fractionUsed * 100).roundedInt, remaining: remaining)
            : nil
        let leak: LeakCategory? = Dictionary(grouping: weekItems, by: \.category)
            .compactMapValues { items -> (count: Int, total: Decimal)? in
                let total = netSpend(items)
                return (items.count >= 6 && total > 0 && dbl(total) / Double(items.count) < 10.0)
                    ? (items.count, total) : nil
            }
            .max { $0.value.count < $1.value.count }
            .map { LeakCategory(name: $0.key, count: $0.value.count, total: $0.value.total) }
        let underPace: UnderPaceCategory? = {
            guard let wb = weeklyBudget, wb > 0,
                  dbl(weekSpent) < dbl(wb) * paceFraction * 0.8 else { return nil }
            let expected = wb * Decimal(paceFraction)
            return UnderPaceCategory(name: "", under: max(expected - weekSpent, 0))
        }()

        let weeklyTips = WellbeingEngine.weeklyTips(
            WeeklyInputs(spent: weekSpent, weeklyBudget: weeklyBudget, daysElapsed: daysElapsed,
                         daysInWeek: 7, deltaPercentVsLastWeek: weekDelta,
                         pacedCategory: paced, leakCategory: leak, underPaceCategory: underPace))

        // ── Wins + per-component detail ─────────────────────────────────────────────
        let wins = monthlyTips.filter { $0.tone == .win }.map {
            WellbeingWin(emoji: winEmoji($0.type), type: $0.type, label: $0.label, percent: $0.percent)
        }
        let onPace = current.goals.filter { $0.reached || !$0.behind }.count
        let detail: [WellbeingComponentKey: ComponentDetail] = [
            .savings: ComponentDetail(savingsRatePercent: current.savingsRatePercent,
                                      saved: current.saved, income: current.income),
            .budget: ComponentDetail(overCount: current.overCount, budgetedCount: current.budgetedCount,
                                     overspend: current.overspendTotal),
            .trend: ComponentDetail(trendPercent: current.trendPercent, avgSpend: avgSpend),
            .subscriptions: ComponentDetail(subsMonthly: current.subsMonthly,
                                            subsSharePercent: current.subsSharePercent),
            .goals: ComponentDetail(goalsOnPace: onPace, goalsTotal: current.goals.count),
        ]

        // ── Labels ──────────────────────────────────────────────────────────────────
        let cycleStart = PayCycle.month(today, startDay: monthStartDay, offset: 0).start
        let idFmt = DateFormatter(); idFmt.dateFormat = "yyyy-MM"
        let monthFmt = DateFormatter(); monthFmt.dateFormat = "MMMM yyyy"
        let dayFmt = DateFormatter(); dayFmt.setLocalizedDateFormatFromTemplate("d MMM")

        return WellbeingSummary(
            score: score, monthlyTips: monthlyTips, weekly: weekly, weeklyTips: weeklyTips, wins: wins,
            detail: detail, receiptsLogged: receipts.count, hasBudget: current.hasAnyBudget,
            periodId: idFmt.string(from: cycleStart),
            monthLabel: monthFmt.string(from: cycleStart),
            weekLabel: "\(dayFmt.string(from: weekStart)) – \(dayFmt.string(from: weekEnd))")
    }

    private static func winEmoji(_ type: TipType) -> String {
        switch type {
        case .savingsWin: "🔥"
        case .categoryImproved: "📉"
        case .underPaceWin: "🎉"
        default: "✅"
        }
    }
}

// MARK: - Small numeric helpers

private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

private extension Double {
    /// Round half-away-from-zero to the nearest Int (matches Kotlin's `roundToInt`).
    var roundedInt: Int { Int(self.rounded()) }
}
