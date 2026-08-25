//
//  RecapBuilder.swift
//  Budgetty
//
//  Builds a `RecapStory` for the just-closed period, reusing the app's existing pure engines rather
//  than introducing a new content model — the Swift port of Android's `RecapProvider`. `PayCycle`
//  windows, `Receipt.paidTotal` spend, `WellbeingEngine` for the 0–100 monthly score/band,
//  `BuyingLimitCounter` for the limits outcome, `SavingsMath` + `SubscriptionDetector` (via
//  `SubscriptionScan`) for the score's savings/subscription components. Everything is derived from the
//  user's own local receipts/budgets/goals — nothing leaves the device.
//
//  The score-input derivation intentionally MIRRORS `WellbeingScan.inputsFor`, computed for the past
//  month offset, so the recap's report-card score is the same number the Wellbeing screen would give
//  that month. Keep the two in step.
//

import Foundation
import SwiftData

enum RecapBuilder {

    /// A built recap for the `kind` period at `offset` (−1 = the just-closed period), or nil when the
    /// data guard says there's nothing worth showing.
    static func build(kind: RecapKind,
                      offset: Int = -1,
                      receipts: [Receipt],
                      budgets: [Budget],
                      recurring: [Recurring],
                      goals: [SavingsGoal],
                      contributions: [SavingsContribution],
                      ignoredSubs: Set<String>,
                      limits: [BuyingLimit],
                      monthStartDay: Int,
                      today: Date = .now,
                      firstWeekday: Int = BuyingLimitCounter.localeFirstWeekday(),
                      calendar: Calendar = .current) -> RecapStory? {
        let engine = Engine(receipts: receipts, budgets: budgets, recurring: recurring, goals: goals,
                            contributions: contributions, ignoredSubs: ignoredSubs, limits: limits,
                            monthStartDay: monthStartDay, today: today, firstWeekday: firstWeekday, cal: calendar)
        switch kind {
        case .monthly: return engine.buildMonthly(offset: offset)
        case .weekly: return engine.buildWeekly(offset: offset)
        }
    }

    // Constructive-tone thresholds (Android parity).
    private static let toughSpendUp = 8
    private static let toughScoreDrop = -5
    private static let flatTolerance = 2
    private static let warnFraction = 0.9
    private static let maxStreak = 24
    private static let trailingMonths = 6
    private static let niceStep = 10

    // ── Pure weekly-streak sourcing (§1.3) — top-level so they unit-test standalone (parity with the
    //    Android `weeklyShareOf` / `pickWeekStreak` top-level functions). ─────────────────────────────

    /// A monthly budget amount sliced to one week for the weekly streak comparison (§1.3). Category and
    /// whole-budget amounts in Budgetty are monthly; a month is `52 ⁄ 12` weeks, so a week's allowance is
    /// `monthly × 12 ⁄ 52`, rounded HALF_UP to 2 dp. An explicitly-set WEEKLY budget is already per-week
    /// and used as-is (never passed here).
    static func weeklyShareOf(_ monthly: Decimal) -> Decimal {
        (monthly as NSDecimalNumber)
            .multiplying(by: NSDecimalNumber(value: 12))
            .dividing(by: NSDecimalNumber(value: 52), withBehavior: weekShareRounding)
            .decimalValue
    }

    /// Picks the single scope for the weekly Streak card (§1.3): the strongest live current run (highest
    /// `current`, then `best`) among those clearing the `minToSurface` ≥ 2 floor; failing that, the
    /// strongest best-run fallback (highest `best` ≥ 2). Ties break on label for determinism. Nil when
    /// nothing qualifies, so the card drops out.
    static func pickWeekStreak(_ streaks: [Streak]) -> Streak? {
        if let live = StreakEngine.surfaced(streaks).max(by: { a, b in
            if a.current != b.current { return a.current < b.current }
            if a.best != b.best { return a.best < b.best }
            return a.label < b.label
        }) {
            return live
        }
        return streaks.filter { $0.best >= StreakEngine.minToSurface }.max(by: { a, b in
            if a.best != b.best { return a.best < b.best }
            return a.label < b.label
        })
    }

    /// Maps a chosen `Streak` to the calm secondary-band `.streak` card (best-run when `current < 2`).
    static func streakCard(_ streak: Streak) -> RecapCard {
        .streak(band: .secondary, kind: streak.kind, scope: streak.label.isEmpty ? nil : streak.label,
                current: streak.current, best: streak.best, liveOnTrack: streak.liveOnTrack,
                isBestRun: streak.current < StreakEngine.minToSurface)
    }

    /// HALF_UP-to-2-dp rounding for `weeklyShareOf` (matches Kotlin `divide(52, 2, HALF_UP)`; budgets are
    /// positive, where `.plain` rounds ties up).
    private static let weekShareRounding = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false,
        raiseOnUnderflow: false, raiseOnDivideByZero: false)

    /// Holds the fetched data + params for one build; mirrors the Android `RecapProvider` instance.
    private struct Engine {
        let receipts: [Receipt]
        let budgets: [Budget]
        let recurring: [Recurring]
        let goals: [SavingsGoal]
        let contributions: [SavingsContribution]
        let ignoredSubs: Set<String>
        let limits: [BuyingLimit]
        let monthStartDay: Int
        let today: Date
        let firstWeekday: Int
        let cal: Calendar

        // ── Window + spend helpers ──────────────────────────────────────────────

        private func monthInterval(_ offset: Int) -> DateInterval {
            PayCycle.monthInterval(today, startDay: monthStartDay, offset: offset, calendar: cal)
        }

        private func weekInterval(_ offset: Int) -> DateInterval {
            var wcal = cal
            wcal.firstWeekday = firstWeekday
            let base = wcal.dateInterval(of: .weekOfYear, for: today)?.start ?? wcal.startOfDay(for: today)
            let start = wcal.date(byAdding: .weekOfYear, value: offset, to: base) ?? base
            let end = wcal.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        }

        private func receipts(in interval: DateInterval) -> [Receipt] {
            receipts.filter { interval.contains($0.createdAt) }
        }

        private func paidSpend(_ list: [Receipt]) -> Decimal {
            list.reduce(Decimal.zero) { $0 + $1.paidTotal }
        }

        private func netSpend(_ items: [LineItem]) -> Decimal {
            items.reduce(Decimal.zero) { $0 + $1.lineTotal }
        }

        private func monthSpend(_ offset: Int) -> Decimal {
            paidSpend(receipts(in: monthInterval(offset)))
        }

        private func deltaPercent(_ current: Decimal, _ previous: Decimal) -> Int? {
            previous > 0 ? ((dbl(current) / dbl(previous) - 1.0) * 100).roundedInt : nil
        }

        // ── Monthly ─────────────────────────────────────────────────────────────

        func buildMonthly(offset: Int) -> RecapStory? {
            let (monthStart, monthEnd) = PayCycle.month(today, startDay: monthStartDay, offset: offset, calendar: cal)
            let window = monthInterval(offset)
            let monthReceipts = receipts(in: window)
            let prevReceipts = receipts(in: monthInterval(offset - 1))
            let monthItems = monthReceipts.flatMap(\.items)
            let prevItems = prevReceipts.flatMap(\.items)
            let spend = paidSpend(monthReceipts)
            let prevSpend = paidSpend(prevReceipts)

            let guardResult = RecapDataGuard.evaluate(kind: .monthly, totalReceipts: receipts.count,
                                                      periodReceipts: monthReceipts.count,
                                                      periodHasSpend: spend > 0,
                                                      priorPeriodHasSpend: prevSpend > 0)
            guard case let .show(withComparison) = guardResult else { return nil }

            let delta = withComparison ? deltaPercent(spend, prevSpend) : nil
            let score = scoreForMonth(offset)
            let prevScore = withComparison ? scoreForMonth(offset - 1).score : nil
            let scoreDelta: Int? = {
                if let s = score.score, let p = prevScore { return s - p }
                return nil
            }()
            let movers = withComparison ? topMovers(current: monthItems, previous: prevItems) : []
            let budget = budgetOutcome(monthItems: monthItems, spend: spend)
            let prevCycleStart = PayCycle.month(today, startDay: monthStartDay, offset: offset - 1, calendar: cal).start
            let nextMonthStart = PayCycle.month(today, startDay: monthStartDay, offset: offset + 1, calendar: cal).start

            let cards = isTough(deltaPercent: delta, scoreDelta: scoreDelta)
                ? toughMonthlyCards(spend: spend, delta: delta, prevSpend: prevSpend,
                                    prevCycleStart: prevCycleStart, movers: movers, budget: budget)
                : goodMonthlyCards(offset: offset, spend: spend, delta: delta, prevSpend: prevSpend,
                                   prevCycleStart: prevCycleStart, score: score, scoreDelta: scoreDelta,
                                   movers: movers, budget: budget, window: window)

            return RecapStory(kind: .monthly, monthStart: monthStart, nextMonthStart: nextMonthStart,
                              weekStart: monthStart, weekEnd: monthEnd, cards: cards)
        }

        /// A month reads "tougher" when spend rose meaningfully OR the score fell — never framed as red.
        private func isTough(deltaPercent: Int?, scoreDelta: Int?) -> Bool {
            (deltaPercent != nil && deltaPercent! >= toughSpendUp)
                || (scoreDelta != nil && scoreDelta! <= toughScoreDrop)
        }

        private func goodMonthlyCards(offset: Int, spend: Decimal, delta: Int?, prevSpend: Decimal,
                                      prevCycleStart: Date, score: WellbeingScore, scoreDelta: Int?,
                                      movers: [Mover], budget: BudgetOutcome, window: DateInterval) -> [RecapCard] {
            let improved = delta == nil || delta! <= flatTolerance
            var cards: [RecapCard] = [.cover(band: .primary)]
            cards.append(.total(band: improved ? .good : .warn, spent: spend, deltaPercent: delta,
                                prevMonthStart: delta != nil ? prevCycleStart : nil,
                                prevTotal: delta != nil ? prevSpend : nil, improved: improved))
            if let s = score.score, let sb = score.band {
                cards.append(.score(band: .secondary, score: s, scoreBand: sb, delta: scoreDelta,
                                    prevMonthStart: scoreDelta != nil ? prevCycleStart : nil))
            }
            if let primary = movers.first {
                cards.append(.mover(band: .neutral, category: primary.category, dotColorArgb: primary.colorArgb,
                                    delta: primary.delta, previousAmount: primary.previous,
                                    currentAmount: primary.current,
                                    second: movers.count > 1
                                        ? RecapSecondMover(category: movers[1].category, delta: movers[1].delta)
                                        : nil))
            }
            if budget.hasBudget {
                let ms = monthStreak(endOffset: offset)
                cards.append(.budgetStreak(band: .great, streakMonths: ms.current, best: ms.best,
                                           liveOnTrack: ms.liveOnTrack,
                                           underCount: budget.underCount, scopeCount: budget.scopeCount,
                                           segments: budget.segments, safeToSpend: budget.safeToSpend))
            }
            if !limits.isEmpty {
                let outcome = limitOutcomes(window: window)
                cards.append(.limits(band: .warn, underCount: outcome.filter(\.under).count,
                                     totalCount: outcome.count, chips: outcome))
            }
            cards.append(.focus(band: .primary, focus: deriveMonthlyFocus(budget: budget, movers: movers),
                                isWeekly: false))
            return cards
        }

        private func toughMonthlyCards(spend: Decimal, delta: Int?, prevSpend: Decimal, prevCycleStart: Date,
                                       movers: [Mover], budget: BudgetOutcome) -> [RecapCard] {
            var cards: [RecapCard] = [
                .total(band: .warn, spent: spend, deltaPercent: delta,
                       prevMonthStart: delta != nil ? prevCycleStart : nil,
                       prevTotal: delta != nil ? prevSpend : nil, improved: false),
            ]
            let rise = movers.first { $0.delta > 0 } ?? movers.first
            if let it = rise {
                cards.append(.mover(band: .neutral, category: it.category, dotColorArgb: it.colorArgb,
                                    delta: it.delta, previousAmount: it.previous, currentAmount: it.current,
                                    second: nil))
            }
            cards.append(.focus(band: .primary, focus: deriveToughFocus(rise: rise, budget: budget),
                                isWeekly: false))
            return cards
        }

        // ── Weekly ──────────────────────────────────────────────────────────────

        func buildWeekly(offset: Int) -> RecapStory? {
            let window = weekInterval(offset)
            let weekStart = window.start
            let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let weekReceipts = receipts(in: window)
            let weekItems = weekReceipts.flatMap(\.items)
            let prevReceipts = receipts(in: weekInterval(offset - 1))
            let spend = paidSpend(weekReceipts)
            let prevSpend = paidSpend(prevReceipts)

            let guardResult = RecapDataGuard.evaluate(kind: .weekly, totalReceipts: receipts.count,
                                                      periodReceipts: weekReceipts.count,
                                                      periodHasSpend: spend > 0,
                                                      priorPeriodHasSpend: prevSpend > 0)
            guard case let .show(withComparison) = guardResult else { return nil }

            let weeklyBudget = budgets.first { $0.key == Budget.weeklyKey }?.amount
            let fractionUsed: Double = {
                guard let wb = weeklyBudget, wb > 0 else { return 0 }
                return min(max(dbl(spend) / dbl(wb), 0), 1)
            }()
            let remaining = weeklyBudget.map { max($0 - spend, 0) } ?? 0
            let delta = withComparison ? deltaPercent(spend, prevSpend) : nil
            let onTrack = weeklyBudget == nil || fractionUsed <= 1
            let movers = withComparison ? topMovers(current: weekItems, previous: prevReceipts.flatMap(\.items)) : []

            // §1.3: a fuller weekly story — Cover → Pace → Limits (if any) → Streak (if any) → Focus.
            // Both the Limits and Streak cards drop out entirely when there's nothing to show, so a bare
            // week stays Cover → Pace → Focus (3 cards) and never pads.
            var cards: [RecapCard] = [
                .cover(band: .primary),
                .pace(band: onTrack ? .good : .warn, spent: spend, weeklyBudget: weeklyBudget,
                      fractionUsed: fractionUsed, paceFraction: 1, remaining: remaining, deltaPercent: delta),
            ]
            if !limits.isEmpty {
                let outcome = limitOutcomes(window: window, weekly: true)
                cards.append(.limits(band: .warn, underCount: outcome.filter(\.under).count,
                                     totalCount: outcome.count, chips: outcome))
            }
            if let streak = weekStreak(endOffset: offset) {
                cards.append(RecapBuilder.streakCard(streak))
            }
            cards.append(.focus(band: .primary, focus: deriveWeeklyFocus(movers: movers), isWeekly: true))
            return RecapStory(kind: .weekly, monthStart: weekEnd, nextMonthStart: weekEnd,
                              weekStart: weekStart, weekEnd: weekEnd, cards: cards)
        }

        // ── Movers ──────────────────────────────────────────────────────────────

        struct Mover {
            let category: String
            let colorArgb: Int
            let delta: Decimal
            let previous: Decimal
            let current: Decimal
        }

        private func topMovers(current: [LineItem], previous: [LineItem]) -> [Mover] {
            let currByCat = Dictionary(grouping: current, by: \.category).mapValues { netSpend($0) }
            let prevByCat = Dictionary(grouping: previous, by: \.category).mapValues { netSpend($0) }
            let cats = Set(currByCat.keys).union(prevByCat.keys)
            return cats.map { cat -> Mover in
                let cur = currByCat[cat] ?? .zero
                let prev = prevByCat[cat] ?? .zero
                return Mover(category: cat, colorArgb: Categories.color(for: cat),
                             delta: cur - prev, previous: prev, current: cur)
            }
            .filter { $0.delta != 0 }
            .sorted { abs($0.delta) > abs($1.delta) }
            .prefix(2)
            .map { $0 }
        }

        // ── Budget outcome + streak ───────────────────────────────────────────────

        struct BudgetOutcome {
            let hasBudget: Bool
            let underCount: Int
            let scopeCount: Int
            let segments: [RecapSegStatus]
            let safeToSpend: Decimal
            let overCategory: String?
            let overBudget: Decimal?
        }

        /// Each budgeted scope as (label, spend, budget): per-category budgets if any, else the monthly one.
        private func budgetScopes(monthItems: [LineItem], spend: Decimal) -> [(label: String, spent: Decimal, budget: Decimal)] {
            var catBudgets: [String: Decimal] = [:]
            for b in budgets where b.key.hasPrefix("CAT:") { catBudgets[String(b.key.dropFirst(4))] = b.amount }
            let monthlyBudget = budgets.first { $0.key == Budget.monthlyKey }?.amount
            let catSpend = Dictionary(grouping: monthItems, by: \.category).mapValues { netSpend($0) }
            if !catBudgets.isEmpty {
                return catBudgets.map { (label: $0.key, spent: catSpend[$0.key] ?? .zero, budget: $0.value) }
            } else if let mb = monthlyBudget {
                return [(label: Budget.monthlyKey, spent: spend, budget: mb)]
            }
            return []
        }

        private func budgetOutcome(monthItems: [LineItem], spend: Decimal) -> BudgetOutcome {
            let scopes = budgetScopes(monthItems: monthItems, spend: spend)
            if scopes.isEmpty {
                return BudgetOutcome(hasBudget: false, underCount: 0, scopeCount: 0, segments: [],
                                     safeToSpend: .zero, overCategory: nil, overBudget: nil)
            }
            let segments = scopes.map { segStatus(spent: $0.spent, budget: $0.budget) }
            let over = scopes.filter { $0.spent > $0.budget }
            let worstOver = over.max { ($0.spent - $0.budget) < ($1.spent - $1.budget) }
            let budgetedTotal = scopes.reduce(Decimal.zero) { $0 + $1.budget }
            return BudgetOutcome(hasBudget: true,
                                 underCount: scopes.filter { $0.spent <= $0.budget }.count,
                                 scopeCount: scopes.count, segments: segments,
                                 safeToSpend: budgetedTotal - spend,
                                 overCategory: worstOver?.label, overBudget: worstOver?.budget)
        }

        private func segStatus(spent: Decimal, budget: Decimal) -> RecapSegStatus {
            if budget <= 0 { return .warn }
            if spent > budget { return .bad }
            if dbl(spent) >= dbl(budget) * warnFraction { return .warn }
            return .good
        }

        /// The all-scopes month streak (§2.1): consecutive CLOSED pay-cycle months where EVERY budgeted
        /// scope stayed under, ending with `endOffset`, plus its personal best and whether the current
        /// OPEN month is on track. Feeds the de-flamed monthly `budgetStreak` card (§2.4/§2.6).
        ///
        /// Re-sourced from `StreakEngine.allScopesStreak` so the recap's every-scope streak is the one
        /// shared implementation — the same object the Budget row and Wellbeing evidence read. Each closed
        /// month's line items are tagged with a period index (0 = `endOffset`, increasing into the past);
        /// the OPEN month (one cycle after `endOffset`) becomes the `LiveBudgetPeriod` that only ever feeds
        /// `liveOnTrack`, never counted (§2.3). A month with no receipts is "no data" and breaks the run;
        /// per-category caps use net line spend; the monthly-only scope carries each month's paid
        /// adjustment (tax/fees − discount), exactly as `budgetOutcome` did.
        private func monthStreak(endOffset: Int) -> Streak {
            var txns: [StreakTxn] = []
            var adjustment: [Int: Decimal] = [:]
            for idx in 0..<maxStreak {
                let rcpts = receipts(in: monthInterval(endOffset - idx))
                let items = rcpts.flatMap(\.items)
                guard !items.isEmpty else { continue }   // empty month → no data at this index (breaks the run)
                txns.append(contentsOf: items.map {
                    StreakTxn(periodIndex: idx, category: $0.category, amount: $0.lineTotal)
                })
                adjustment[idx] = paidSpend(rcpts) - netSpend(items)
            }
            var catBudgets: [String: Decimal] = [:]
            for b in budgets where b.key.hasPrefix("CAT:") { catBudgets[String(b.key.dropFirst(4))] = b.amount }
            let monthlyBudget = budgets.first { $0.key == Budget.monthlyKey }?.amount
            return StreakEngine.allScopesStreak(BudgetStreakInput(
                transactions: txns, categoryBudgets: catBudgets, monthlyBudget: monthlyBudget,
                kind: .budgetMonth, monthlyLabel: Budget.monthlyKey,
                monthlyAdjustmentByPeriod: adjustment, live: livePeriod(monthInterval(endOffset + 1))))
        }

        /// The best per-scope WEEK streak to surface on the weekly Streak card (§1.3), or nil when there's
        /// nothing worth showing. Per-category when any category budget is set — each monthly category
        /// budget sliced to a week via `weeklyShareOf` — else the single whole-budget scope (an explicit
        /// WEEKLY budget as-is, or the monthly budget sliced). `pickWeekStreak` chooses one scope: a live
        /// current run first, else a best-run fallback, both gated at the `minToSurface` ≥ 2 floor. Closed
        /// weeks are tagged 0 = `endOffset` increasing into the past; the OPEN week (`endOffset + 1`) feeds
        /// `liveOnTrack` only.
        private func weekStreak(endOffset: Int) -> Streak? {
            var catBudgetsRaw: [String: Decimal] = [:]
            for b in budgets where b.key.hasPrefix("CAT:") { catBudgetsRaw[String(b.key.dropFirst(4))] = b.amount }
            let weeklyBudget = budgets.first { $0.key == Budget.weeklyKey }?.amount
            let monthlyBudget = budgets.first { $0.key == Budget.monthlyKey }?.amount
            let categoryBudgets: [String: Decimal]
            let wholeBudget: Decimal?
            if !catBudgetsRaw.isEmpty {
                categoryBudgets = catBudgetsRaw.mapValues { RecapBuilder.weeklyShareOf($0) }
                wholeBudget = nil
            } else if let wb = weeklyBudget {
                categoryBudgets = [:]
                wholeBudget = wb
            } else if let mb = monthlyBudget {
                categoryBudgets = [:]
                wholeBudget = RecapBuilder.weeklyShareOf(mb)
            } else {
                return nil
            }
            var txns: [StreakTxn] = []
            var adjustment: [Int: Decimal] = [:]
            for idx in 0..<maxStreak {
                let rcpts = receipts(in: weekInterval(endOffset - idx))
                let items = rcpts.flatMap(\.items)
                guard !items.isEmpty else { continue }
                txns.append(contentsOf: items.map {
                    StreakTxn(periodIndex: idx, category: $0.category, amount: $0.lineTotal)
                })
                adjustment[idx] = paidSpend(rcpts) - netSpend(items)
            }
            let streaks = StreakEngine.budgetStreaks(BudgetStreakInput(
                transactions: txns, categoryBudgets: categoryBudgets, monthlyBudget: wholeBudget,
                kind: .budgetWeek, monthlyLabel: "",
                monthlyAdjustmentByPeriod: adjustment, live: livePeriod(weekInterval(endOffset + 1))))
            return RecapBuilder.pickWeekStreak(streaks)
        }

        /// The in-flight (open) period's line items as a `LiveBudgetPeriod` (§2.3): net per category plus
        /// the whole-budget paid adjustment. Feeds `Streak.liveOnTrack` only — never counted.
        private func livePeriod(_ interval: DateInterval) -> LiveBudgetPeriod {
            let rcpts = receipts(in: interval)
            let items = rcpts.flatMap(\.items)
            return LiveBudgetPeriod(
                transactions: items.map { StreakTxn(periodIndex: 0, category: $0.category, amount: $0.lineTotal) },
                monthlyAdjustment: paidSpend(rcpts) - netSpend(items))
        }

        // ── Buying-limits outcome ──────────────────────────────────────────────────

        /// The limit chips for a recap window. In a `weekly` story the window IS a single week, so every
        /// limit is simply counted within it against its cap (§1.3 — weekly limits pair naturally with the
        /// weekly recap). In the monthly story a monthly cap counts over the whole month, while a weekly
        /// cap asks "did you keep every week under it" via the worst week's count.
        private func limitOutcomes(window: DateInterval, weekly: Bool = false) -> [RecapLimitChip] {
            let items = receipts.flatMap(\.items).map {
                CountableItem(name: $0.name, quantity: $0.quantity, timestamp: $0.createdAt)
            }
            return limits.map { limit in
                let bought: Int
                if weekly || limit.timeframe == .monthly {
                    bought = BuyingLimitCounter.countInWindow(items, keywords: limit.keywords, window: window)
                } else {
                    // A weekly cap over a month is "did you keep every week under it": the worst week's count.
                    bought = worstWeekCount(items: items, keywords: limit.keywords, monthWindow: window)
                }
                return RecapLimitChip(emoji: limit.emoji.isEmpty ? "🏷️" : limit.emoji,
                                      label: limit.displayTitle, bought: bought, cap: limit.count)
            }
        }

        private func worstWeekCount(items: [CountableItem], keywords: [String], monthWindow: DateInterval) -> Int {
            var wcal = cal
            wcal.firstWeekday = firstWeekday
            let monthEndExclusive = monthWindow.end
            var weekStart = wcal.dateInterval(of: .weekOfYear, for: monthWindow.start)?.start
                ?? wcal.startOfDay(for: monthWindow.start)
            var worst = 0
            while weekStart < monthEndExclusive {
                let weekEnd = wcal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
                let iv = DateInterval(start: weekStart, end: weekEnd)
                worst = max(worst, BuyingLimitCounter.countInWindow(items, keywords: keywords, window: iv))
                weekStart = wcal.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekEnd
            }
            return worst
        }

        // ── Focus derivation ─────────────────────────────────────────────────────

        /// The over-budget category as a cap-to-try, when one exists.
        private func overBudgetCap(_ budget: BudgetOutcome) -> RecapFocus? {
            guard let cat = budget.overCategory else { return nil }
            return .capCategory(category: cat, amount: roundToNice(budget.overBudget ?? .zero))
        }

        private func deriveMonthlyFocus(budget: BudgetOutcome, movers: [Mover]) -> RecapFocus {
            if let cap = overBudgetCap(budget) { return cap }
            if let rise = movers.first(where: { $0.delta > 0 }) { return .watchCategory(category: rise.category) }
            return .keepItUp
        }

        private func deriveToughFocus(rise: Mover?, budget: BudgetOutcome) -> RecapFocus {
            if let cap = overBudgetCap(budget) { return cap }
            if let rise { return .capCategory(category: rise.category, amount: roundToNice(rise.previous)) }
            return .keepItUp
        }

        private func deriveWeeklyFocus(movers: [Mover]) -> RecapFocus {
            if let rise = movers.first(where: { $0.delta > 0 }) { return .watchCategory(category: rise.category) }
            return .keepItUp
        }

        /// Rounds a suggested cap to the nearest 10 so it reads as an intentional target, not a raw figure.
        private func roundToNice(_ value: Decimal) -> Decimal {
            if value <= 0 { return value }
            let tens = (value as NSDecimalNumber).dividing(by: NSDecimalNumber(value: niceStep), withBehavior: Self.round0)
            let result = tens.multiplying(by: NSDecimalNumber(value: niceStep)).decimalValue
            return max(result, Decimal(niceStep))
        }

        // ── Wellbeing score for a given month (mirrors WellbeingScan.inputsFor) ──────

        private func scoreForMonth(_ offset: Int) -> WellbeingScore {
            WellbeingEngine.score(wellbeingInputs(offset))
        }

        private func wellbeingInputs(_ offset: Int) -> WellbeingInputs {
            let monthsTracked = Set(receipts.flatMap(\.items)
                .map { cal.dateComponents([.year, .month], from: $0.createdAt) }).count

            let subScan = SubscriptionScan.run(receipts: receipts, ignored: ignoredSubs, today: today)
            let subsMonthly = subScan.monthlyTotal
            let subsCount = subScan.detected.count
            let hasSubsData = receipts.count >= WellbeingEngine.minReceiptsToScore && monthsTracked >= 1

            func avgBefore(_ off: Int) -> Decimal? {
                let spends = (1...trailingMonths).map { monthSpend(off - $0) }.filter { $0 > 0 }
                guard !spends.isEmpty else { return nil }
                return SubscriptionDetector.round2(spends.reduce(Decimal.zero, +) / Decimal(spends.count))
            }

            let window = monthInterval(offset)
            let monthReceipts = receipts(in: window)
            let monthItems = monthReceipts.flatMap(\.items)
            let spend = paidSpend(monthReceipts)
            let income = recurring.filter(\.isIncome).reduce(Decimal.zero) { $0 + $1.windowAmount(window) }
            let bills = recurring.filter { !$0.isIncome }.reduce(Decimal.zero) { $0 + $1.windowAmount(window) }
            let hasIncome = income > 0
            let saved = income - bills - spend
            let rate = hasIncome ? (dbl(saved) / dbl(income) * 100).roundedInt : 0

            let scopes = budgetScopes(monthItems: monthItems, spend: spend)
            let overScopes = scopes.filter { $0.spent > $0.budget }
            let overspend = overScopes.reduce(Decimal.zero) { $0 + ($1.spent - $1.budget) }
            let budgetedTotal = scopes.reduce(Decimal.zero) { $0 + $1.budget }

            let baseline = avgBefore(0) ?? spend
            let subsShare: Int? = {
                if !hasSubsData { return nil }
                if subsCount == 0 { return 0 }
                return baseline > 0 ? (dbl(subsMonthly) / dbl(baseline) * 100).roundedInt : nil
            }()
            let trendPercent: Int? = {
                guard let avg = avgBefore(offset), avg > 0 else { return nil }
                return ((dbl(spend) / dbl(avg) - 1.0) * 100).roundedInt
            }()

            let goalPaces: [GoalPace] = goals.map { g in
                let cs = contributions.filter { $0.goal?.persistentModelID == g.persistentModelID }
                let p = SavingsMath.progress(target: g.targetAmount, targetDate: g.targetDate,
                                             contributions: cs, today: today)
                return GoalPace(name: g.name, reached: p.reached, behind: p.behind)
            }

            return WellbeingInputs(
                hasIncome: hasIncome, savingsRatePercent: rate, income: income, saved: saved, netCashflow: saved,
                hasAnyBudget: !scopes.isEmpty, budgetedCount: scopes.count, overCount: overScopes.count,
                overspendTotal: overspend, budgetedTotal: budgetedTotal,
                trendPercent: trendPercent, subsSharePercent: subsShare, subsMonthly: subsMonthly,
                subsCount: subsCount, goals: goalPaces, categories: [], spend: spend,
                receiptsLogged: receipts.count, monthsTracked: monthsTracked)
        }

        private static let round0 = NSDecimalNumberHandler(
            roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
            raiseOnUnderflow: false, raiseOnDivideByZero: false)
    }
}

// MARK: - Numeric helpers

private func dbl(_ d: Decimal) -> Double { (d as NSDecimalNumber).doubleValue }

private extension Double {
    /// Round half-away-from-zero to the nearest Int (matches Kotlin's `roundToInt`).
    var roundedInt: Int { Int(self.rounded()) }
}
