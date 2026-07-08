//
//  Money.swift
//  Budgetty
//
//  Money is `Decimal` throughout — never `Double` — so cents stay exact, matching the
//  Android app's use of BigDecimal.
//

import Foundation

extension Decimal {
    /// Format as currency for display. Defaults to the user's chosen currency (Account → Currency),
    /// falling back to EUR. The default argument is re-read on every call, so changing the setting
    /// updates formatting app-wide.
    func formatMoney(currencyCode: String = UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR",
                     locale: Locale = .current) -> String {
        let n = self as NSDecimalNumber
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = locale
        return f.string(from: n) ?? "\(n)"
    }

    /// `Decimal` multiplied by an integer quantity — the line total for a purchased item
    /// (Android sums `price × quantity`).
    func times(_ quantity: Int) -> Decimal {
        self * Decimal(quantity)
    }

    static func fromDouble(_ value: Double?) -> Decimal {
        guard let value else { return .zero }
        // Route through a string to avoid binary-float rounding noise when parsing API JSON doubles.
        return Decimal(string: String(value)) ?? Decimal(value)
    }
}
