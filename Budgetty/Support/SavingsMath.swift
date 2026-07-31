//
//  SavingsMath.swift
//  Budgetty
//
//  Pure progress math for savings goals — a direct port of Android's `SavingsMath`. A goal's saved
//  total is the signed sum of its contributions; pace/behind are only meaningful with a target date.
//

import Foundation

/// Derived progress for one savings goal.
struct SavingsProgress {
    let saved: Decimal
    let remaining: Decimal
    let fraction: Double
    let reached: Bool
    /// remaining ÷ whole months to the target date; nil when there's no date or the goal is reached.
    let monthlyRate: Decimal?
    /// True when the required `monthlyRate` exceeds the goal's recent average monthly deposit.
    let behind: Bool
}

enum SavingsMath {

    static func saved(_ contributions: [SavingsContribution]) -> Decimal {
        contributions.reduce(.zero) { $0 + $1.amount }
    }

    static func progress(target: Decimal, targetDate: Date?, contributions: [SavingsContribution],
                         today: Date = .now, calendar cal: Calendar = .current) -> SavingsProgress {
        let saved = self.saved(contributions)
        let remaining = max(target - saved, 0)
        let fraction: Double = target <= 0 ? 0
            : min(max((saved as NSDecimalNumber).doubleValue / (target as NSDecimalNumber).doubleValue, 0), 1)
        let reached = target > 0 && saved >= target

        guard !reached, let targetDate, remaining > 0 else {
            return SavingsProgress(saved: saved, remaining: remaining, fraction: fraction,
                                   reached: reached, monthlyRate: nil, behind: false)
        }
        // Whole months between this month and the target month (min 1), matching Android's YearMonth math.
        let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: targetDate)) ?? targetDate
        let months = max(1, cal.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0)
        let rate = (remaining as NSDecimalNumber)
            .dividing(by: NSDecimalNumber(value: months),
                      withBehavior: Self.round2).decimalValue
        let avg = averageMonthlyDeposit(contributions, cal: cal)
        return SavingsProgress(saved: saved, remaining: remaining, fraction: fraction,
                               reached: false, monthlyRate: rate,
                               behind: avg != nil && rate > avg!)
    }

    /// Average monthly deposit across the distinct months that have a deposit (withdrawals ignored).
    private static func averageMonthlyDeposit(_ contributions: [SavingsContribution],
                                              cal: Calendar) -> Decimal? {
        let deposits = contributions.filter { $0.amount > 0 }
        guard !deposits.isEmpty else { return nil }
        let months = Set(deposits.map { cal.dateComponents([.year, .month], from: $0.date) }).count
        let total = deposits.reduce(Decimal.zero) { $0 + $1.amount }
        return (total as NSDecimalNumber)
            .dividing(by: NSDecimalNumber(value: max(1, months)), withBehavior: Self.round2).decimalValue
    }

    private static let round2 = NSDecimalNumberHandler(
        roundingMode: .plain, scale: 2, raiseOnExactness: false, raiseOnOverflow: false,
        raiseOnUnderflow: false, raiseOnDivideByZero: false)
}
