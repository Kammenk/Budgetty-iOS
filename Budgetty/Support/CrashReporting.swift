//
//  CrashReporting.swift
//  Budgetty
//
//  The one place that touches the Crashlytics SDK, so the rest of the app depends on this small
//  surface rather than Firebase directly (mirrors Android's `CrashReporting`).
//
//  Collection model — **default-on with an opt-out**, matching Android (confirmed with the user):
//  `SettingsKey.crashReporting` defaults to true and the Account screen exposes a real toggle. A
//  genuine toggle is what makes default-on defensible for a Europe-only (GDPR) user base. The stored
//  preference is the source of truth: applied at startup in `FirebaseBootstrap.configure()` and again
//  on every toggle change, so the SDK state always follows the user's choice.
//
//  `setCrashlyticsCollectionEnabled` persists inside Crashlytics and survives process death, so a
//  user who opts out stays opted out even before startup re-applies the preference.
//
//  ⚠️ SHIPPING BLOCKER (not code): releasing this also requires the App Store Connect **App Privacy**
//  nutrition label to declare Crash Data / Diagnostics, plus a privacy-policy disclosure. Android has
//  the equivalent Play Data-safety change pending. Do not ship Crashlytics without it.
//

import Foundation
import FirebaseCrashlytics

enum CrashReporting {
    /// The user's persisted choice; default-on when never set.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.crashReporting) as? Bool ?? true
    }

    /// Point the SDK at `enabled`. Called at startup and on every toggle change.
    static func setEnabled(_ enabled: Bool) {
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(enabled)
    }

    /// Apply the stored preference. Runs during Firebase configuration, before anything can crash.
    static func applyStoredPreference() {
        setEnabled(isEnabled)
    }
}
