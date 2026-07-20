//
//  ReviewGate.swift
//  Budgetty
//
//  Decides *when* to ask for an App Store rating; the caller performs the ask via
//  `@Environment(\.requestReview)`. This is a one-for-one mirror of the Android `ReviewTracker`
//  gate (decided once for both platforms) so the two prompt on identical conditions.
//
//  Apple hands out at most 3 prompts per user per 365 days and may silently show nothing — the only
//  thing under our control is spending a request at a good moment. The trigger is a successfully
//  finalized *scan* (not a manual entry, not an edit re-save): the user just got what they came for,
//  gated behind enough usage that they have an opinion worth leaving.
//
//  Deliberately *not* done: asking "do you like the app?" first and routing only happy users to the
//  card. Apple discourages it and Play forbids it. Everyone is asked, unconditionally, at a good
//  moment.
//
//  Device-level, like `ScanQuota` — a rating is per Apple ID per device, so there is nothing to
//  isolate per signed-in user. Cleared on account deletion alongside the scan quota.
//

import Foundation

enum ReviewGate {
    /// Successful scans before the first ask. Keep in step with the Android gate.
    static let scansBeforePrompt = 3
    /// Days since the first recorded scan before the first ask. Keep in step with the Android gate.
    static let daysUsingBeforePrompt = 3
    /// Days before asking again. Apple throttles far harder than this on its own; the cooldown just
    /// stops us burning requests in a burst if a user scans heavily in one week.
    static let cooldownDays = 90

    private static let keyScans = "review.successfulScans"
    private static let keyFirstSeen = "review.firstSeen"
    private static let keyLastAsked = "review.lastAsked"

    /// Call when a scan is finalized into a saved receipt. Mirrors the `ScanQuota` increment — both
    /// sit behind the same guard, so a manual entry or an edit re-save never counts. Returns `true`
    /// when the user has just earned a prompt and the caller should fire `requestReview`.
    @discardableResult
    static func recordSuccessfulScan(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        let scans = defaults.integer(forKey: keyScans) + 1
        defaults.set(scans, forKey: keyScans)
        // First write also stamps first-seen, so a brand-new user is 0 days old here and can never be
        // asked on their very first scan even if `scansBeforePrompt` were 1.
        if defaults.object(forKey: keyFirstSeen) == nil {
            defaults.set(now, forKey: keyFirstSeen)
        }
        return isEligible(now: now, scans: scans, defaults: defaults)
    }

    /// Call once the prompt has been handed to StoreKit. Starts the cooldown. As on Android this
    /// records that we *asked*, not that anything was shown — the system deliberately never tells us,
    /// and treating "asked" as "shown" is the conservative choice.
    static func onPromptRequested(now: Date = .now, defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: keyLastAsked)
    }

    /// Clears prompt history, e.g. on account deletion (parity with `ScanQuota.reset()`).
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyScans)
        defaults.removeObject(forKey: keyFirstSeen)
        defaults.removeObject(forKey: keyLastAsked)
    }

    private static func isEligible(now: Date, scans: Int, defaults: UserDefaults) -> Bool {
        #if DEBUG
        // Lets a build force the prompt for verification regardless of counters (see save()).
        if ProcessInfo.processInfo.environment["REVIEW_PROMPT"] == "force" { return true }
        #endif
        if scans < scansBeforePrompt { return false }
        #if DEBUG
        // Debug builds skip the age gate so the flow is verifiable without waiting three days.
        let ageMet = true
        #else
        let firstSeen = defaults.object(forKey: keyFirstSeen) as? Date ?? now
        let ageMet = daysBetween(firstSeen, now) >= daysUsingBeforePrompt
        #endif
        if !ageMet { return false }
        guard let lastAsked = defaults.object(forKey: keyLastAsked) as? Date else { return true }
        return daysBetween(lastAsked, now) >= cooldownDays
    }

    private static func daysBetween(_ from: Date, _ to: Date) -> Int {
        Int(to.timeIntervalSince(from) / 86_400)
    }
}
