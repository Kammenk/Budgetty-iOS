//
//  RecapModel.swift
//  Budgetty
//
//  The end-of-period Recap's pure data model — the Swift port of Android's `RecapModel.kt` +
//  `RecapFrequency`. No SwiftUI, no SwiftData: a `RecapStory` is a list of `RecapCard`s carrying RAW
//  figures (Decimal/Int/enum), so the story view is a dumb renderer that formats money, dates and copy
//  itself, and the whole model ports 1:1 to Android. Built by `RecapBuilder` for the just-closed period.
//

import Foundation

/// Which cadence a recap covers. Monthly is the full report card; weekly is a lighter momentum check.
enum RecapKind { case monthly, weekly }

/// How often the end-of-period recap interstitial appears. The 0–100 wellbeing score is a monthly
/// measure, so `.weekly` is a lighter momentum check with no score; `.monthly` is the full report card;
/// `.both` shows each on its own boundary. Default is `.both` (§1.1) — the weekly recap is the app's
/// strongest retention asset, so it runs by default; made safe by the in-story frequency control (§1.4)
/// that puts its own off-switch on the very first weekly recap a user sees. Stored as its raw string
/// (device-global, like appearance — NOT reset on sign-out). Android parity: `RecapFrequency`.
enum RecapFrequency: String, CaseIterable, Identifiable {
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case both = "BOTH"

    var id: String { rawValue }

    /// The stored cadence, defaulting to `.both` when unset (matches the Android §1.1 default).
    static var current: RecapFrequency {
        RecapFrequency(rawValue: UserDefaults.standard.string(forKey: SettingsKey.recapFrequency) ?? "")
            ?? .both
    }
}

/// The tonal band backdrop of a card, mapped to the app's theme tokens in the view layer (never a
/// hard-coded colour) so every card themes correctly in dark mode. Mirrors the mockup CSS vars:
/// PRIMARY = `--pc`, GOOD = `--goodc`, WARN = `--warnc`, GREAT = `--greatc`, SECONDARY = `--secc`,
/// NEUTRAL = `--sch`.
enum RecapBand { case primary, good, warn, great, secondary, neutral }

/// Accent tone of a small pill (e.g. the "↓ 12% less" chip): good = the improvement green, warn = amber.
enum RecapPillTone { case good, warn, neutral }

/// Traffic-light state of one budget scope, for the budget card's segment bar.
enum RecapSegStatus { case good, warn, bad }

/// One buying-limit outcome chip: emoji + label + how many were bought against the `cap`. `under` is
/// STRICTLY under the cap (green + counted in "stayed under N of M"); at or over the cap is the warm
/// "reached" state (never red, never counted) — matching the mockup, where 4-of-4 reads as warn, not as
/// a kept limit (§1.3 / no-loss-framing). Android parity: `RecapLimitChip.under = bought < cap`.
struct RecapLimitChip: Identifiable {
    let emoji: String
    let label: String
    let bought: Int
    let cap: Int

    var under: Bool { bought < cap }
    var id: String { "\(label)|\(emoji)|\(cap)" }
}

/// The second-biggest category mover, shown as a trailing clause on the mover card.
struct RecapSecondMover {
    let category: String
    let delta: Decimal
}

/// The one focus/tip that closes the story. Raw payload only; the view owns the localized copy.
enum RecapFocus {
    /// A concrete cap to try next period (the tougher-month close, or an over-budget category).
    case capCategory(category: String, amount: Decimal)
    /// Keep an eye on a category that crept up.
    case watchCategory(category: String)
    /// A material category has no budget yet.
    case setBudget(category: String)
    /// Nothing to fix — a genuine "keep it up".
    case keepItUp
}

/// One card of the story. Each carries RAW figures — the stateless view formats money, dates and copy
/// so it localizes and dark-themes correctly. Rendered by a single view switching on the case.
enum RecapCard {
    /// Opening card: title/sub come from the story's kind + dates in the view.
    case cover(band: RecapBand)

    /// Total spent (monthly) or spent-this-period, with an optional vs-previous comparison.
    /// `deltaPercent` is signed vs the previous period (negative = spent less); nil = no comparison.
    case total(band: RecapBand, spent: Decimal, deltaPercent: Int?,
               prevMonthStart: Date?, prevTotal: Decimal?, improved: Bool)

    /// Monthly-only wellbeing score ring + its change vs the previous month. `delta` is nil when there's
    /// no prior score.
    case score(band: RecapBand, score: Int, scoreBand: WellbeingBand, delta: Int?, prevMonthStart: Date?)

    /// The single biggest category move vs the previous period. `delta` = current − previous (negative =
    /// a drop, the good direction).
    case mover(band: RecapBand, category: String, dotColorArgb: Int, delta: Decimal,
               previousAmount: Decimal, currentAmount: Decimal, second: RecapSecondMover?)

    /// Budget adherence + streak, with the per-scope segment bar and safe-to-spend at the close.
    /// `streakMonths` is consecutive closed months where every budgeted scope stayed under, ending with
    /// the just-closed one (0 when it wasn't all-under). The hero de-flames per §2.4 (no 🔥) and shows the
    /// streak `StreakMotif` once `streakMonths` ≥ 2 (§2.7); `best` (personal-best run within the 24-month
    /// window) drives the best-run fallback (§2.5); `liveOnTrack` is whether the open month is on track —
    /// the motif's dotted ghost segment.
    case budgetStreak(band: RecapBand, streakMonths: Int, best: Int, liveOnTrack: Bool,
                      underCount: Int, scopeCount: Int, segments: [RecapSegStatus], safeToSpend: Decimal)

    /// Outcome-streak card (§1.3 / §2): one scope's run of consecutive CLOSED periods met, on the calm
    /// secondary band. Sourced from `StreakEngine`; only ever built when there is something worth showing
    /// — a current run (`current` ≥ 2, `isBestRun` = false) or, when the current run is 0, the
    /// personal-best fallback (`best` ≥ 2, `isBestRun` = true). Never padded: when neither holds the card
    /// is dropped entirely (a bare week stays Cover → Pace → Focus). `scope` is a category name for a
    /// per-category run, or nil for the whole-budget scope ("under budget"). `liveOnTrack` = whether the
    /// open period is on track to extend the run (the motif's dotted ghost segment).
    case streak(band: RecapBand, kind: StreakKind, scope: String?, current: Int, best: Int,
                liveOnTrack: Bool, isBestRun: Bool)

    /// Buying-limits outcome: how many stayed under, plus a chip per limit. Dropped when the user has none.
    case limits(band: RecapBand, underCount: Int, totalCount: Int, chips: [RecapLimitChip])

    /// Weekly pace: spend vs last week + a pace bar. `fractionUsed` is spent÷budget clamped 0…1 (0 when
    /// no weekly budget); `paceFraction` is where the week "should" be by its close (always 1 for a
    /// closed week).
    case pace(band: RecapBand, spent: Decimal, weeklyBudget: Decimal?, fractionUsed: Double,
              paceFraction: Double, remaining: Decimal, deltaPercent: Int?)

    /// Closing card: the one focus for next period + the Done / See details actions (rendered by the
    /// frame, since they exit the story).
    case focus(band: RecapBand, focus: RecapFocus, isWeekly: Bool)

    /// The card's tonal band backdrop.
    var band: RecapBand {
        switch self {
        case let .cover(band): band
        case let .total(band, _, _, _, _, _): band
        case let .score(band, _, _, _, _): band
        case let .mover(band, _, _, _, _, _, _): band
        case let .budgetStreak(band, _, _, _, _, _, _, _): band
        case let .streak(band, _, _, _, _, _, _): band
        case let .limits(band, _, _, _): band
        case let .pace(band, _, _, _, _, _, _): band
        case let .focus(band, _, _): band
        }
    }
}

/// A fully-built recap ready to render: the ordered `cards` plus the dates the frame's header needs.
/// Built by `RecapBuilder` for the just-closed period; the view is a dumb renderer of it.
struct RecapStory {
    let kind: RecapKind
    /// The just-closed pay-cycle month's start (monthly). For weekly this is `weekEnd` (unused there).
    let monthStart: Date
    /// The next pay-cycle month's start, for the monthly focus card's "FOCUS FOR {month}" kicker.
    let nextMonthStart: Date
    let weekStart: Date
    let weekEnd: Date
    let cards: [RecapCard]
}
