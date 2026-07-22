//
//  PremiumBenefits.swift
//  Budgetty
//
//  The single list of what Premium unlocks, ported from Android's `premiumBenefits()`. One source so
//  every surface says the same thing, and — the point of the exercise — **every number is
//  interpolated from the constant that enforces it**, so retuning a cap can't leave stale copy
//  advertising the old one.
//
//  The rule for adding a row: it may only appear as a real benefit if some code path actually gates
//  on it. A feature that isn't built yet goes in as `soon`, which renders muted with a clock instead
//  of a check — honest about the roadmap without pretending it ships today.
//
//  ⚠️ Audited 2026-07-21 against the enforcing code; four of the five original rows were wrong:
//  - "Home screen widgets" — removed, widgets were free on both platforms and nothing gated them.
//    (Back as of 2026-07-22, but only because `WidgetQuota` now genuinely caps them.)
//  - "10 custom categories" — the number didn't exist; the real cap is `Categories.freeCustomLimit`
//    free and `maxCustomLimit` (unlimited) paid, so the row both undersold and quoted fiction.
//  - "Cloud backup & sync" — no such feature; demoted to `soon`, where it stays.
//  - "Accent color themes" — wasn't built either.
//  2026-07-22: the last of those is now real, and two more gates landed. `AccentOption` ships
//  Android's Sage/Ocean/Plum behind a premium-gated Account picker, and free bills are capped at
//  `RecurringQuota.freeLimit` on the Budget screen — so iOS unlocks the same four things Android does.
//
//  Copy is Android's, verbatim, so its finished 16-locale translations carry over unchanged rather
//  than being rewritten here (see PARITY.md — never re-translate).
//

import Foundation

struct PremiumBenefit: Identifiable {
    let id: String
    /// SF Symbol, outline per the mockup — the tile carries the tint, the glyph stays light-line.
    let symbol: String
    let title: String
    let detail: String
    /// Not built yet: shown muted with a clock, so it reads as roadmap rather than a promise.
    var soon = false
}

enum PremiumBenefits {
    static var all: [PremiumBenefit] { real + soon }

    /// Unlocks a code path actually enforces today. Computed rather than stored so the interpolated
    /// numbers re-localize when the in-app language changes.
    static var real: [PremiumBenefit] {
        [
            PremiumBenefit(
                id: "scans",
                symbol: "camera",
                title: String(localized: "Unlimited receipt scans"),
                detail: String(localized: "Free plan stops at \(ScanQuota.freeLimit)")
            ),
            PremiumBenefit(
                id: "categories",
                symbol: "star",
                title: String(localized: "Unlimited custom categories"),
                detail: String(localized: "Free plan includes \(Categories.freeCustomLimit)")
            ),
            PremiumBenefit(
                id: "recurring",
                symbol: "arrow.triangle.2.circlepath",
                title: String(localized: "Unlimited recurring bills"),
                detail: String(localized: "Free plan includes \(RecurringQuota.freeLimit)")
            ),
            PremiumBenefit(
                id: "widgets",
                symbol: "square.grid.2x2",
                title: String(localized: "Unlimited home-screen widgets"),
                detail: String(localized: "Free plan includes \(WidgetQuota.freeLimit)")
            ),
            PremiumBenefit(
                id: "themes",
                symbol: "paintpalette",
                title: String(localized: "Every accent theme"),
                detail: String(localized: "Sage, Ocean and Plum")
            ),
        ]
    }

    /// Announced but unbuilt. Kept visible on purpose — the product decision on Android was to show
    /// the roadmap rather than delete it — but never dressed up as something you get today.
    static var soon: [PremiumBenefit] {
        [
            PremiumBenefit(
                id: "cloud",
                symbol: "icloud",
                title: String(localized: "Cloud backup & sync"),
                detail: String(localized: "Coming soon"),
                soon: true
            ),
        ]
    }
}
