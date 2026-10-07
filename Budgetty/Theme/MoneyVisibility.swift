//
//  MoneyVisibility.swift
//  Budgetty
//
//  "Hide amounts" privacy mode — the single source of truth for whether money figures are masked.
//  Android parity: `AppFormats.hideAmounts` (Compose snapshot state).
//
//  `@Observable` rather than `@AppStorage`, for the same reason as `AppTheme`: `formatMoney()` is a
//  plain function read from dozens of view bodies, and SwiftUI's observation tracking registers a
//  dependency on any `@Observable` property read *during* a body evaluation — even one read inside a
//  called function. So flipping `hidden` re-masks every amount on screen in one pass, with no
//  per-call-site wiring. Persisted to `UserDefaults` so it survives relaunch; the nav-bar eye and the
//  Account → Privacy switch both drive this one flag.
//

import SwiftUI

@Observable
final class MoneyVisibility {
    static let shared = MoneyVisibility()

    var hidden: Bool {
        didSet {
            guard hidden != oldValue else { return }
            UserDefaults.standard.set(hidden, forKey: SettingsKey.hideAmounts)
        }
    }

    private init() { hidden = UserDefaults.standard.bool(forKey: SettingsKey.hideAmounts) }

    func toggle() { hidden.toggle() }

    /// Re-read from `UserDefaults` — after a backup `.replace` writes the key behind our back.
    func refreshFromDefaults() {
        let stored = UserDefaults.standard.bool(forKey: SettingsKey.hideAmounts)
        if stored != hidden { hidden = stored }
    }
}
