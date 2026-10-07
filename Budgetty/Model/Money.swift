//
//  Money.swift
//  Budgetty
//
//  Money is `Decimal` throughout — never `Double` — so cents stay exact, matching the
//  Android app's use of BigDecimal.
//

import Foundation

extension Decimal {
    /// Format as currency for display — the real figure, never masked. Use for amounts the user is
    /// actively setting (filter bounds, entry-field echoes) that must stay readable even in Hide-amounts
    /// mode; everything that *displays* spending uses `formatMoney` instead. Android: `formatMoneyRaw`.
    func formatMoneyRaw(currencyCode: String = UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR",
                        locale: Locale = .current) -> String {
        let n = self as NSDecimalNumber
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = locale
        return f.string(from: n) ?? "\(n)"
    }

    /// Format as currency for display (Account → Currency, default EUR), or a privacy mask (e.g.
    /// "•••• €") while "Hide amounts" is on. The default `currencyCode` is re-read on every call so a
    /// currency change updates formatting app-wide; reading `MoneyVisibility.shared.hidden` here is what
    /// lets flipping the eye re-mask every on-screen amount in one pass (see `MoneyVisibility`). The mask
    /// drops the sign and magnitude so neither leaks; the currency symbol stays so the slot still reads
    /// as money. `MoneyText` renders the approved frosted-pill variant for prominent amounts.
    func formatMoney(currencyCode: String = UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR",
                     locale: Locale = .current) -> String {
        if MoneyVisibility.shared.hidden {
            return "•••• \(CurrencyOption.symbol(currencyCode))"
        }
        return formatMoneyRaw(currencyCode: currencyCode, locale: locale)
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

/// "N items" with locale-correct pluralization (the "%lld items" catalog key carries the
/// plural variations converted from Android's `item_count` plurals).
func itemCountLabel(_ n: Int) -> String { String(localized: "\(n) items") }

/// "N receipts" with locale-correct pluralization (History summary strip).
func receiptCountLabel(_ n: Int) -> String { String(localized: "\(n) receipts") }
