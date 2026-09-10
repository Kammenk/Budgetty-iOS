//
//  CrashReporting.swift
//  Budgetty
//
//  The one place that touches the Crashlytics SDK, so the rest of the app depends on this small
//  surface rather than Firebase directly (mirrors Android's `CrashReporting`).
//
//  Collection model — **opt-in, default OFF**, matching Android: `SettingsKey.crashReporting` defaults
//  to false, and nothing is collected until the user turns it on — either at the first-run consent gate
//  (`AnalyticsConsentView`) or via the Account screen's toggle. Opt-in is the safe default for a
//  Europe-only (GDPR) user base. The stored preference is the source of truth: applied at startup in
//  `FirebaseBootstrap.configure()` (which also forces collection off until the consent choice is made)
//  and again on every toggle change, so the SDK state always follows the user's choice.
//
//  `setCrashlyticsCollectionEnabled` persists inside Crashlytics and survives process death, so a user
//  who has not opted in stays off even before startup re-applies the preference.
//
//  ⚠️ SHIPPING BLOCKER (not code). Two of the three disclosure pieces are now done:
//   ✅ `PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypeCrashData` — not linked, not
//      tracking. "Not linked" is only true because nothing here calls `setUserID`; add that and the
//      manifest and the App Store label both become wrong.
//   ✅ The privacy policy discloses crash reporting in §1(f), and Support & About finally links to
//      it — every row on that screen used to be a no-op.
//   ❌ The **App Store Connect App Privacy label** must declare Diagnostics › Crash Data, purpose
//      App Functionality, not linked to the user, not used for tracking. Apple compares the label
//      against the manifest above. It's a console action — it cannot be done from the repo.
//  Do not upload a build until that last one is set. Android's equivalent Play Data-safety change
//  is still pending on its side.
//

import Foundation
import FirebaseCrashlytics

enum CrashReporting {
    /// The user's persisted choice; default-OFF when never set (opt-in).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.crashReporting) as? Bool ?? false
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
