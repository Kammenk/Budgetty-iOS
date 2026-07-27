//
//  BudgetRolloverRunner.swift
//  Budgetty
//
//  The SwiftData side of budget rollover: reconciles the stored `BudgetRollover` rows with the
//  current pay-cycle on Budget-screen open (and when the toggle flips). A port of Android's
//  `BudgetViewModel.rollForwardIfNeeded`; the arithmetic lives in `BudgetRolloverMath`.
//

import Foundation
import SwiftData

@MainActor
enum BudgetRolloverRunner {

    /// Brings each monthly-period budget's carry-over up to the current period (accumulating every
    /// elapsed period's unspent leftover), or wipes all carry rows when rollover is off. Only the
    /// overall MONTHLY budget and category budgets carry — a WEEKLY overall budget doesn't. Past-period
    /// spend uses net line prices (an estimate, since budget amounts have no history).
    static func reconcile(context: ModelContext,
                          budgets: [Budget],
                          items: [LineItem],
                          enabled: Bool,
                          startDay: Int,
                          today: Date = .now,
                          calendar cal: Calendar = .current) {
        let existing = (try? context.fetch(FetchDescriptor<BudgetRollover>())) ?? []

        // Off: drop any stored carry-over (matches Android's clearAll()).
        guard enabled else {
            guard !existing.isEmpty else { return }
            for row in existing { context.delete(row) }
            try? context.save()
            return
        }

        let currentKey = BudgetRolloverMath.currentPeriodKey(today, startDay: startDay, calendar: cal)
        let byKey = Dictionary(existing.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let liveKeys = Set(budgets.map(\.key))
        var changed = false

        for budget in budgets where budget.key == Budget.monthlyKey || budget.key.hasPrefix("CAT:") {
            if let row = byKey[budget.key] {
                guard row.periodKey < currentKey else { continue } // already caught up this period
                let category = budget.key.hasPrefix("CAT:") ? String(budget.key.dropFirst(4)) : nil
                row.carried = BudgetRolloverMath.rollForward(
                    storedCarried: row.carried,
                    storedPeriodKey: row.periodKey,
                    currentPeriodKey: currentKey,
                    budget: budget.amount
                ) { spent(in: $0, category: category, items: items, startDay: startDay, cal: cal) }
                row.periodKey = currentKey
                changed = true
            } else {
                // First time / just enabled: carry 0 now, start accruing next period.
                context.insert(BudgetRollover(key: budget.key, carried: 0, periodKey: currentKey))
                changed = true
            }
        }

        // Drop carry rows for budgets that no longer exist.
        for row in existing where !liveKeys.contains(row.key) {
            context.delete(row)
            changed = true
        }

        if changed { try? context.save() }
    }

    /// Net line-price spend in `period`'s pay-cycle window, optionally restricted to a single category
    /// (exact-name match, mirroring Android's rollForward estimate).
    private static func spent(in period: String, category: String?,
                              items: [LineItem], startDay: Int, cal: Calendar) -> Decimal {
        let window = BudgetRolloverMath.periodWindow(period, startDay: startDay, calendar: cal)
        return items
            .filter { window.start <= $0.createdAt && $0.createdAt < window.end }
            .filter { category == nil || $0.category == category }
            .reduce(Decimal.zero) { $0 + $1.lineTotal }
    }
}
