//
//  LoanCalculator.swift
//  Budgetty
//
//  Closed-form loan amortisation — no SwiftData/SwiftUI deps, so the math is unit-testable. 1:1 port of
//  Android's `ui/planners/LoanCalculator.kt`. Everything is an estimate (fees and lender rounding
//  aside) — see the screen's note.
//

import Foundation

/// One year of a loan's amortisation: how much of the year's payments went to principal vs interest,
/// and the balance still owed at the end of that year.
struct LoanYear: Identifiable {
    let year: Int
    let principalPaid: Decimal
    let interestPaid: Decimal
    let endBalance: Decimal
    var id: Int { year }
}

/// The amortised result of a fixed-rate loan: the level monthly payment and where the money goes over
/// the whole term.
struct LoanResult {
    let monthlyPayment: Decimal
    let months: Int
    let totalInterest: Decimal
    let totalPaid: Decimal
    /// Share of total paid that is principal, 0–100 (the rest is interest).
    let principalPercent: Int
    let years: [LoanYear]
    var interestPercent: Int { 100 - principalPercent }
}

enum LoanCalculator {

    /// The level monthly payment is `P·r ÷ (1 − (1 + r)^−n)` with `r = APR ÷ 12` and `n` months,
    /// degrading to `P ÷ n` at 0%. The per-year breakdown re-runs the month-by-month schedule so
    /// principal/interest/balance always reconcile with the payment shown.
    static func compute(amount: Decimal, aprPercent: Decimal, years: Int) -> LoanResult {
        let principal = Swift.max(0, dbl(amount))
        let termYears = Swift.max(1, years)
        let n = termYears * 12
        let monthlyRate = dbl(aprPercent) / 1200.0

        let payment = monthlyRate <= 0
            ? principal / Double(n)
            : principal * monthlyRate / (1 - pow(1 + monthlyRate, -Double(n)))

        var balance = principal
        var yearRows: [LoanYear] = []
        for y in 1...termYears {
            var principalThisYear = 0.0
            var interestThisYear = 0.0
            for _ in 0..<12 where balance > 0 {
                let interest = balance * monthlyRate
                let principalPart = Swift.min(payment - interest, balance)
                interestThisYear += interest
                principalThisYear += principalPart
                balance -= principalPart
            }
            yearRows.append(LoanYear(year: y, principalPaid: money(principalThisYear),
                                     interestPaid: money(interestThisYear),
                                     endBalance: money(Swift.max(0, balance))))
        }

        let totalPaid = payment * Double(n)
        let totalInterest = Swift.max(0, totalPaid - principal)
        let principalPercent = totalPaid > 0 ? roundToIntSafe(principal / totalPaid * 100) : 100

        return LoanResult(monthlyPayment: money(payment), months: n, totalInterest: money(totalInterest),
                          totalPaid: money(totalPaid), principalPercent: Swift.min(100, Swift.max(0, principalPercent)),
                          years: yearRows)
    }

    private static func dbl(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
    private static func money(_ v: Double) -> Decimal {
        var r = Decimal(); var d = Decimal(v); NSDecimalRound(&r, &d, 2, .plain); return r
    }
    private static func roundToIntSafe(_ v: Double) -> Int {
        (v.isNaN || v.isInfinite) ? 0 : Int(v.rounded())
    }
}
