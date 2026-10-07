//
//  DebtPayoffSimulator.swift
//  Budgetty
//
//  Month-by-month debt payoff simulation — no SwiftData/SwiftUI deps, so it's unit-testable. 1:1 port
//  of Android's `ui/planners/DebtPayoffSimulator.kt`. Each month every debt accrues interest, then pays
//  its minimum; whatever is left of the fixed budget (all original minimums + the user's extra, so a
//  cleared debt's minimum frees up and cascades) attacks one debt at a time in the strategy's order.
//  Pure Double math (an estimate), capped at `maxMonths` so a self-growing balance can't loop forever.
//

import Foundation

/// The order debts are attacked in once every minimum is covered.
enum PayoffStrategy {
    /// Smallest balance first — quick wins that keep motivation up.
    case snowball
    /// Highest APR first — the least interest paid overall.
    case avalanche
}

/// One debt's figures fed into the simulation (names/emoji live on the entity, not here). `id` is a
/// caller-assigned key (the debt's index) used only to report the month each debt clears.
struct DebtInput {
    let id: Int
    let balance: Decimal
    let aprPercent: Decimal
    let minPayment: Decimal
}

/// The outcome of simulating a payoff plan: how long it takes, the interest paid, the total balance
/// after each month (for the chart), and the month each debt cleared. `clearedAll` is false when the
/// plan never reaches zero within the cap (e.g. a minimum that doesn't cover its own interest).
struct DebtPayoffResult {
    let months: Int
    let totalInterest: Decimal
    /// Total balance owed at month 0, 1, 2, … down to 0 — length is `months` + 1.
    let balanceSeries: [Decimal]
    /// Debt id → the month index (1-based) it was cleared; absent for a debt still owing at the cap.
    let payoffMonthById: [Int: Int]
    let clearedAll: Bool
}

enum DebtPayoffSimulator {

    /// 50 years — well past any realistic payoff; a plan still owing here never clears at this rate.
    static let maxMonths = 600
    /// Half a cent — the "effectively zero" threshold so float dust doesn't keep a debt alive.
    private static let cent = 0.005

    static func simulate(debts: [DebtInput], extraPerMonth: Decimal, strategy: PayoffStrategy?) -> DebtPayoffResult {
        let active = debts.filter { $0.balance > 0 }.map {
            MutableDebt(id: $0.id, balance: dbl($0.balance), monthlyRate: dbl($0.aprPercent) / 1200.0, min: dbl($0.minPayment))
        }
        if active.isEmpty {
            return DebtPayoffResult(months: 0, totalInterest: 0, balanceSeries: [0], payoffMonthById: [:], clearedAll: true)
        }

        let budget = active.reduce(0) { $0 + $1.min } + Swift.max(0, dbl(extraPerMonth))
        var payoffMonth: [Int: Int] = [:]
        var series: [Double] = [active.reduce(0) { $0 + $1.balance }]
        var totalInterest = 0.0
        var month = 0

        while active.contains(where: { $0.balance > Self.cent }) && month < maxMonths {
            month += 1
            // Accrue interest on everything still owing.
            for d in active where d.balance > 0 {
                let interest = d.balance * d.monthlyRate
                d.balance += interest
                totalInterest += interest
            }
            // Every debt pays its minimum first.
            var available = budget
            for d in active where d.balance > 0 {
                let pay = Swift.min(d.min, d.balance)
                d.balance -= pay
                available -= pay
            }
            // The remainder cascades onto the target debt(s) in strategy order.
            if let strategy, available > Self.cent {
                let order = active.filter { $0.balance > 0 }.sorted(by: comparator(strategy))
                for d in order {
                    if available <= Self.cent { break }
                    let pay = Swift.min(available, d.balance)
                    d.balance -= pay
                    available -= pay
                }
            }
            // Record any debt that just cleared.
            for d in active where d.balance <= Self.cent && payoffMonth[d.id] == nil {
                d.balance = 0
                payoffMonth[d.id] = month
            }
            series.append(active.reduce(0) { $0 + $1.balance })
        }

        let cleared = !active.contains { $0.balance > Self.cent }
        return DebtPayoffResult(months: month, totalInterest: money(totalInterest),
                                balanceSeries: series.map(money), payoffMonthById: payoffMonth, clearedAll: cleared)
    }

    private static func comparator(_ s: PayoffStrategy) -> (MutableDebt, MutableDebt) -> Bool {
        switch s {
        case .snowball: return { $0.balance < $1.balance }
        case .avalanche: return { $0.monthlyRate > $1.monthlyRate }
        }
    }

    nonisolated private static func dbl(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
    nonisolated private static func money(_ v: Double) -> Decimal {
        var r = Decimal(); var d = Decimal(v); NSDecimalRound(&r, &d, 2, .plain); return r
    }

    private final class MutableDebt {
        let id: Int
        var balance: Double
        let monthlyRate: Double
        let min: Double
        init(id: Int, balance: Double, monthlyRate: Double, min: Double) {
            self.id = id; self.balance = balance; self.monthlyRate = monthlyRate; self.min = min
        }
    }
}
