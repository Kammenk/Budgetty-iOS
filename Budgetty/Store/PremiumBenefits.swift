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
//  - "Home screen widgets" — removed, widgets are free on both platforms and nothing gates them.
//  - "10 custom categories" — the number didn't exist; the real cap is `Categories.freeCustomLimit`
//    free and `maxCustomLimit` (unlimited) paid, so the row both undersold and quoted fiction.
//  - "Cloud backup & sync" — no such feature; demoted to `soon`.
//  - "Accent color themes / 8 tints" — also not built. There is no accent preference at all: the
//    Account row shows a fixed "Violet" to Premium users and `Palette.tint` is a single hard-coded
//    colour. Demoted to `soon` too.
//  Android additionally caps recurring bills (`FREE_RECURRING_LIMIT`); iOS has no such cap, so that
//  row is deliberately absent rather than copied across.
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

    /// Unlocks a code path actually enforces today.
    static let real: [PremiumBenefit] = [
        PremiumBenefit(
            id: "scans",
            symbol: "camera",
            title: "Unlimited scans",
            detail: "vs \(ScanQuota.freeLimit) on the free plan"
        ),
        PremiumBenefit(
            id: "categories",
            symbol: "star",
            title: "Unlimited custom categories",
            detail: "vs \(Categories.freeCustomLimit) on the free plan"
        ),
    ]

    /// Announced but unbuilt. Kept visible on purpose — the product decision on Android was to show
    /// the roadmap rather than delete it — but never dressed up as something you get today.
    static let soon: [PremiumBenefit] = [
        PremiumBenefit(
            id: "cloud",
            symbol: "icloud",
            title: "Cloud backup & sync",
            detail: "Coming soon",
            soon: true
        ),
        PremiumBenefit(
            id: "themes",
            symbol: "paintpalette",
            title: "Accent colour themes",
            detail: "Coming soon",
            soon: true
        ),
    ]
}
