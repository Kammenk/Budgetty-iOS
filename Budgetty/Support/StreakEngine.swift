//
//  StreakEngine.swift
//  Budgetty
//
//  Pure, on-device outcome-streak math — the Swift port of Android's `StreakEngine` + `StreakModel`
//  (§2 of the retention spec). No SwiftUI, no SwiftData: it takes plain data in and returns `Streak`s,
//  so it unit-tests in isolation and mirrors the Kotlin 1:1 (a sibling of `WellbeingEngine` /
//  `BuyingLimitCounter`). Money is `Decimal` throughout. Following the `WellbeingEngine.swift`
//  precedent (which merged Android's `WellbeingModel.kt` + `WellbeingEngine.kt`), the model types live
//  in this one file with the engine rather than in a second `StreakModel.swift`.
//
//  The model, from §2:
//   - Per-scope, not all-or-nothing (§2.2): one streak per budgeted category, or a single monthly
//     scope, plus one per buying limit. `allScopesStreak` additionally reproduces the legacy
//     every-scope aggregate the recap's monthly `budgetStreak` card renders.
//   - Closed periods only (§2.3): `current` counts completed periods; the open period feeds
//     `liveOnTrack` and is never counted.
//   - Strict reset + always-computed best (§2.5): a miss resets `current` to 0; `best` is the longest
//     met run within the `maxStreak` window, so no new persistence is needed.
//   - No-data ≠ met: a closed period with no receipts at all is `.noData` and breaks a run, whereas a
//     budgeted scope with a budget and zero spend in a period that DID have receipts is `.met`. These
//     two must never be conflated.
//   - One pass (§2.8): transactions are grouped by (periodIndex, category) exactly once, folded into
//     per-scope per-period totals, then each scope is walked backwards.
//
//  Copy is the surface's concern; this object contains no user-facing strings and no loss framing.
//

import Foundation

// MARK: - Model

/// The kind of scope a `Streak` tracks: a monthly or weekly budget, or a buying-limit window. The
/// scope itself is named by `Streak.label`. `token` is the analytics param value (Android parity:
/// `enum.name.lowercase()`), so BUDGET_MONTH → "budget_month".
enum StreakKind: Equatable {
    case budgetMonth, budgetWeek, limit

    var token: String {
        switch self {
        case .budgetMonth: "budget_month"
        case .budgetWeek: "budget_week"
        case .limit: "limit"
        }
    }
}

/// One outcome streak for a single scope, computed by `StreakEngine` over CLOSED periods only. Pure
/// data, so the surfaces (Budget row, Recap card, Wellbeing evidence) render it however they like.
/// Callers filter to `StreakEngine.minToSurface` before showing anything (§2.7); the engine itself
/// always reports the honest numbers.
struct Streak: Equatable {
    let kind: StreakKind
    /// Scope: a category name, the monthly-budget scope, or a limit's display title.
    let label: String
    /// Consecutive CLOSED periods met, ending with the most recent closed one.
    let current: Int
    /// Personal best within the history window (§2.5).
    let best: Int
    /// How many closed periods actually backed this — honesty for the label.
    let periodsChecked: Int
    /// Is the OPEN period currently on track to extend it. Never counted in `current`.
    let liveOnTrack: Bool
}

/// A purchased line reduced to just what a streak needs, tagged with the `periodIndex` it falls in.
/// Index 0 is the MOST RECENT CLOSED period, increasing into the past (1 = the period before it, …).
/// The caller owns the timestamp → `periodIndex` mapping (pay-cycle months / locale weeks), so the
/// engine stays period-unit-agnostic. `amount` is the NET line contribution (price × quantity);
/// per-receipt paid adjustments (tax on top, fees, discounts) apply to the whole-budget scope only and
/// are supplied separately via `BudgetStreakInput.monthlyAdjustmentByPeriod`.
struct StreakTxn {
    let periodIndex: Int
    let category: String
    let amount: Decimal
}

/// The in-flight (open) period's spend, used only to derive `Streak.liveOnTrack` — never counted.
struct LiveBudgetPeriod {
    let transactions: [StreakTxn]
    /// Whole-budget paid adjustment for the open period (added to the monthly scope only).
    var monthlyAdjustment: Decimal = .zero

    init(transactions: [StreakTxn], monthlyAdjustment: Decimal = .zero) {
        self.transactions = transactions
        self.monthlyAdjustment = monthlyAdjustment
    }
}

/// Everything the engine needs to compute budget streaks in one pass. `transactions` are already tagged
/// with a `periodIndex`; anything outside `0 ..< maxStreak` is ignored. Per-category budgets take
/// precedence over `monthlyBudget` (mirrors the app's budget model): when any category budget is set,
/// the monthly scope is not used; otherwise the single monthly scope is.
struct BudgetStreakInput {
    let transactions: [StreakTxn]
    let categoryBudgets: [String: Decimal]
    let monthlyBudget: Decimal?
    let kind: StreakKind
    /// Label for the single whole-budget scope when only a monthly budget is set.
    var monthlyLabel: String = "MONTHLY"
    /// periodIndex → whole-budget paid adjustment for that closed period (net + tax/fees − discount).
    var monthlyAdjustmentByPeriod: [Int: Decimal] = [:]
    var live: LiveBudgetPeriod?

    init(transactions: [StreakTxn], categoryBudgets: [String: Decimal], monthlyBudget: Decimal?,
         kind: StreakKind, monthlyLabel: String = "MONTHLY",
         monthlyAdjustmentByPeriod: [Int: Decimal] = [:], live: LiveBudgetPeriod? = nil) {
        self.transactions = transactions
        self.categoryBudgets = categoryBudgets
        self.monthlyBudget = monthlyBudget
        self.kind = kind
        self.monthlyLabel = monthlyLabel
        self.monthlyAdjustmentByPeriod = monthlyAdjustmentByPeriod
        self.live = live
    }
}

/// A single closed (or the live) buying-limit window: how many matched, and whether it had any data.
struct LimitWindow {
    let count: Int
    /// False when the window held no receipts at all — "no data", never scored as a met window.
    let hasData: Bool
}

/// Everything the engine needs for one buying limit's streak. `closedWindows` index 0 = the most recent
/// CLOSED window, increasing into the past. Keyword matching + counting is `BuyingLimitCounter`'s job
/// upstream; the engine only decides met / missed / no-data and walks it.
struct LimitStreakInput {
    let label: String
    let cap: Int
    let closedWindows: [LimitWindow]
    var live: LimitWindow?

    init(label: String, cap: Int, closedWindows: [LimitWindow], live: LimitWindow? = nil) {
        self.label = label
        self.cap = cap
        self.closedWindows = closedWindows
        self.live = live
    }
}

// MARK: - Engine

enum StreakEngine {

    /// History window: streaks look back at most this many closed periods, and `best` within it.
    static let maxStreak = 24

    /// Below this a "streak" is just "this period" — callers only surface `current` at or above it (§2.7).
    static let minToSurface = 2

    /// A single closed period's result for one scope. `.noData` is a period with no receipts at all.
    private enum PeriodOutcome { case met, missed, noData }

    /// A budgeted scope reduced to its per-closed-period outcomes and whether the open period is on track.
    private struct Scope {
        let label: String
        let outcomes: [PeriodOutcome]
        let liveOnTrack: Bool
    }

    /// Transactions grouped once by (periodIndex, category), plus which periods held any data.
    private struct Grouped {
        let netByPeriodCat: [Int: [String: Decimal]]
        let periodsWithData: Set<Int>
        /// Highest closed-period index to scan (inclusive), bounded by `maxStreak`; −1 when no data.
        let maxPeriod: Int
    }

    // ── Public API ────────────────────────────────────────────────────────────────

    /// Keeps only streaks worth showing (§2.7): `current` ≥ `minToSurface`.
    static func surfaced(_ streaks: [Streak]) -> [Streak] { streaks.filter { $0.current >= minToSurface } }

    /// One `Streak` per budgeted scope: per category when any category budget is set, otherwise a single
    /// monthly-budget scope. Never all-or-nothing — one over-budget category doesn't zero another's run.
    static func budgetStreaks(_ input: BudgetStreakInput) -> [Streak] {
        let grouped = group(input.transactions)
        return scopesOf(input, grouped).map { buildStreak(input.kind, $0.label, $0.outcomes, $0.liveOnTrack) }
    }

    /// The legacy every-scope aggregate: consecutive closed periods where EVERY budgeted scope stayed
    /// under (a period with no receipts breaks it). This is exactly what the recap's monthly
    /// `budgetStreak` card renders — re-sourced here so there is one implementation. `current` is that
    /// count; `best` the best such run in the window.
    static func allScopesStreak(_ input: BudgetStreakInput) -> Streak {
        let grouped = group(input.transactions)
        let scopes = scopesOf(input, grouped)
        guard let first = scopes.first else {
            return Streak(kind: input.kind, label: input.monthlyLabel, current: 0, best: 0,
                          periodsChecked: 0, liveOnTrack: false)
        }
        let length = first.outcomes.count
        let combined: [PeriodOutcome] = (0..<length).map { i in
            let column = scopes.map { $0.outcomes[i] }
            if column.contains(.noData) { return .noData }
            if column.allSatisfy({ $0 == .met }) { return .met }
            return .missed
        }
        let liveOnTrack = input.live != nil && scopes.allSatisfy(\.liveOnTrack)
        return buildStreak(input.kind, input.monthlyLabel, combined, liveOnTrack)
    }

    /// One buying limit's streak: consecutive closed windows whose matched count stayed at or under the cap.
    static func limitStreak(_ input: LimitStreakInput) -> Streak {
        let outcomes: [PeriodOutcome] = input.closedWindows.prefix(maxStreak).map { w in
            if !w.hasData { return .noData }
            return w.count <= input.cap ? .met : .missed
        }
        // The open window is on track whenever it is still within cap — zero purchases counts as on track.
        let liveOnTrack = input.live.map { $0.count <= input.cap } ?? false
        return buildStreak(.limit, input.label, outcomes, liveOnTrack)
    }

    // ── Core walk ───────────────────────────────────────────────────────────────

    /// Walks one scope's closed-period `outcomes` (index 0 = most recent closed) into the past:
    ///  - `current` = consecutive `.met` from index 0, stopping at the first miss or gap.
    ///  - `best` = the longest met run anywhere in the window (a miss OR a gap breaks a run).
    ///  - `periodsChecked` = closed periods that actually held data (`.noData` excluded).
    private static func buildStreak(_ kind: StreakKind, _ label: String,
                                    _ outcomes: [PeriodOutcome], _ liveOnTrack: Bool) -> Streak {
        var current = 0
        var currentOpen = true
        var run = 0
        var best = 0
        var checked = 0
        for outcome in outcomes {
            switch outcome {
            case .met:
                run += 1
                if run > best { best = run }
                if currentOpen { current += 1 }
                checked += 1
            case .missed:
                run = 0
                currentOpen = false
                checked += 1
            case .noData:
                run = 0
                currentOpen = false
            }
        }
        return Streak(kind: kind, label: label, current: current, best: best,
                      periodsChecked: checked, liveOnTrack: liveOnTrack)
    }

    // ── One-pass grouping + scope derivation (§2.8) ─────────────────────────────────

    private static func group(_ transactions: [StreakTxn]) -> Grouped {
        let inWindow = transactions.filter { (0..<maxStreak).contains($0.periodIndex) }
        var netByPeriodCat: [Int: [String: Decimal]] = [:]
        for (period, list) in Dictionary(grouping: inWindow, by: \.periodIndex) {
            var byCat: [String: Decimal] = [:]
            for (cat, lines) in Dictionary(grouping: list, by: \.category) {
                byCat[cat] = lines.reduce(Decimal.zero) { $0 + $1.amount }
            }
            netByPeriodCat[period] = byCat
        }
        let periods = Set(netByPeriodCat.keys)
        let maxPeriod = min(periods.max() ?? -1, maxStreak - 1)
        return Grouped(netByPeriodCat: netByPeriodCat, periodsWithData: periods, maxPeriod: maxPeriod)
    }

    private static func scopesOf(_ input: BudgetStreakInput, _ grouped: Grouped) -> [Scope] {
        var liveNetByCat: [String: Decimal] = [:]
        if let live = input.live {
            for (cat, lines) in Dictionary(grouping: live.transactions, by: \.category) {
                liveNetByCat[cat] = lines.reduce(Decimal.zero) { $0 + $1.amount }
            }
        }
        // 0 ..< (maxPeriod + 1) is 0 ..< 0 (empty) when there's no data — the Swift-safe form of
        // Kotlin's `0..maxPeriod` (which is likewise empty for maxPeriod == -1).
        let periods = 0..<(grouped.maxPeriod + 1)
        if !input.categoryBudgets.isEmpty {
            return input.categoryBudgets.map { category, budget in
                let outcomes = periods.map { p in
                    outcomeAt(grouped, p, spend: grouped.netByPeriodCat[p]?[category] ?? .zero, budget: budget)
                }
                let liveOnTrack = input.live != nil && (liveNetByCat[category] ?? .zero) <= budget
                return Scope(label: category, outcomes: outcomes, liveOnTrack: liveOnTrack)
            }
        } else {
            guard let monthly = input.monthlyBudget else { return [] }
            let outcomes = periods.map { p in
                outcomeAt(grouped, p, spend: monthlySpendAt(grouped, input, p), budget: monthly)
            }
            let liveMonthly = liveNetByCat.values.reduce(Decimal.zero, +) + (input.live?.monthlyAdjustment ?? .zero)
            let liveOnTrack = input.live != nil && liveMonthly <= monthly
            return [Scope(label: input.monthlyLabel, outcomes: outcomes, liveOnTrack: liveOnTrack)]
        }
    }

    /// Whole-budget spend for closed period `p`: net across all categories plus that period's paid adjustment.
    private static func monthlySpendAt(_ grouped: Grouped, _ input: BudgetStreakInput, _ p: Int) -> Decimal {
        let net = grouped.netByPeriodCat[p]?.values.reduce(Decimal.zero, +) ?? .zero
        return net + (input.monthlyAdjustmentByPeriod[p] ?? .zero)
    }

    private static func outcomeAt(_ grouped: Grouped, _ p: Int, spend: Decimal, budget: Decimal) -> PeriodOutcome {
        if !grouped.periodsWithData.contains(p) { return .noData }
        return spend <= budget ? .met : .missed
    }
}
