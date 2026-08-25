//
//  Analytics.swift
//  Budgetty
//
//  The one place that touches the Firebase Analytics SDK, so the rest of the app depends on this small
//  typed surface rather than Firebase directly — the Swift port of Android's `Analytics`, and a sibling
//  of `CrashReporting`. Every event is its own method with fixed params, so a call site cannot
//  fat-finger an event name or a param key; the names/params live only in the `Event`/`Param` enums.
//
//  Collection is default-on with an opt-out: `SettingsKey.analytics` defaults to true and the Account
//  screen exposes a toggle, SEPARATE from crash reporting. The stored preference is the source of truth —
//  `setEnabled` is applied at startup (`FirebaseBootstrap.configure`) and again on every toggle change,
//  so the SDK state always follows the user's choice. `setAnalyticsCollectionEnabled` persists inside the
//  SDK and survives process death, so a user who opts out stays opted out even before startup re-applies
//  the preference (same as `CrashReporting`).
//
//  Privacy: params carry ONLY enums and ints (kind, type, source, length, gain, cards viewed). No
//  category name, item name, amount, email, store name, or any other free text is ever logged here, and
//  no extra collection (screen tracking, user properties) is added beyond these events. iOS needs no
//  App Tracking Transparency prompt: default Firebase Analytics collects no IDFA (no `AdSupport`), and
//  there is no AD_ID concern as on Android.
//
//  ⚠️ Shipping this also requires the App Store Connect App Privacy label to declare the collected
//  analytics data (not linked to the user, not used for tracking) and a privacy-policy disclosure —
//  those are Console/policy tasks, not code (the Android equivalent is a Play Data-safety update).
//

import Foundation
import FirebaseAnalytics

/// Where a buying limit was created from — the `source` param of `Analytics.logLimitCreated`.
enum LimitSource: String {
    case manual, suggestion
    /// Analytics param value (Android parity: `LimitSource.paramValue`).
    var token: String { rawValue }
}

enum Analytics {

    // ── Collection toggle (opt-out, default-on) ───────────────────────────────────

    /// The user's persisted choice; default-on when never set. Device-global, NOT reset on sign-out.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.analytics) as? Bool ?? true
    }

    /// Point the SDK at `enabled`. Called at startup and on every toggle change. Firebase's own
    /// `Analytics` type is module-qualified here to avoid colliding with this wrapper's name.
    static func setEnabled(_ enabled: Bool) {
        FirebaseAnalytics.Analytics.setAnalyticsCollectionEnabled(enabled)
    }

    /// Apply the stored preference. Runs during Firebase configuration.
    static func applyStoredPreference() {
        setEnabled(isEnabled)
    }

    // ── Events (identical names + params to Android) ───────────────────────────────

    /// A scheduled recap story became visible.
    static func logRecapShown(_ kind: RecapKind) {
        log(Event.recapShown, [Param.kind: kind.token])
    }

    /// A recap story was closed. `cardsViewed` is the highest card index reached + 1, so a partial read
    /// (1) is distinguishable from a full one.
    static func logRecapCompleted(_ kind: RecapKind, cardsViewed: Int) {
        log(Event.recapCompleted, [Param.kind: kind.token, Param.cardsViewed: cardsViewed])
    }

    /// A streak was surfaced to the user (Budget row / Recap card / Wellbeing evidence). Stub until the
    /// §1/§2 streak surfaces land; the event set is fixed now so the wiring is a one-liner later.
    static func logStreakSurfaced(_ kind: StreakKind, length: Int) {
        log(Event.streakSurfaced, [Param.kind: kind.token, Param.length: length])
    }

    /// A Wellbeing tip's CTA was acted on.
    static func logTipActed(_ type: TipType) {
        log(Event.tipActed, [Param.type: type.token])
    }

    /// A Wellbeing tip's modelled "+N to your score" projection was shown. Stub until §3.3 lands.
    static func logTipProjectedGain(_ type: TipType, gain: Int) {
        log(Event.tipProjectedGain, [Param.type: type.token, Param.gain: gain])
    }

    /// A new buying limit was created, from the editor (`.manual`) or a suggestion (`.suggestion`, §4.4).
    static func logLimitCreated(_ source: LimitSource) {
        log(Event.limitCreated, [Param.source: source.token])
    }

    // ── Internals ─────────────────────────────────────────────────────────────────

    private static func log(_ event: String, _ params: [String: Any]) {
        FirebaseAnalytics.Analytics.logEvent(event, parameters: params)
    }

    /// Event names — the single source of truth (Android parity).
    private enum Event {
        static let recapShown = "recap_shown"
        static let recapCompleted = "recap_completed"
        static let streakSurfaced = "streak_surfaced"
        static let tipActed = "tip_acted"
        static let tipProjectedGain = "tip_projected_gain"
        static let limitCreated = "limit_created"
    }

    /// Param keys — the single source of truth (Android parity).
    private enum Param {
        static let kind = "kind"
        static let type = "type"
        static let source = "source"
        static let length = "length"
        static let gain = "gain"
        static let cardsViewed = "cards_viewed"
    }
}

// MARK: - Enum → param tokens (Android parity: `Enum.name.lowercase()`)

extension RecapKind {
    /// Analytics param value: MONTHLY → "monthly", WEEKLY → "weekly".
    var token: String {
        switch self {
        case .monthly: "monthly"
        case .weekly: "weekly"
        }
    }
}

extension TipType {
    /// Analytics param value — the snake_case lowered Android enum name.
    var token: String {
        switch self {
        case .negativeCashflow: "negative_cashflow"
        case .overBudget: "over_budget"
        case .categorySpike: "category_spike"
        case .subscriptionCost: "subscription_cost"
        case .missingBudget: "missing_budget"
        case .noGoal: "no_goal"
        case .goalOffTrack: "goal_off_track"
        case .savingsWin: "savings_win"
        case .categoryImproved: "category_improved"
        case .budgetPace: "budget_pace"
        case .smallPurchaseLeak: "small_purchase_leak"
        case .underPaceWin: "under_pace_win"
        }
    }
}
