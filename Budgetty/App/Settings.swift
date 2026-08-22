//
//  Settings.swift
//  Budgetty
//
//  Persisted user preferences (UserDefaults keys + the appearance option). Read via @AppStorage in
//  views; `formatMoney` reads the currency key directly so display updates everywhere.
//

import SwiftUI

enum SettingsKey {
    static let appearance = "pref.appearance"
    static let currency = "pref.currency"
    static let language = "pref.language"
    static let dateFormat = "pref.dateFormat"
    /// The pay day the financial "month" starts on (1–31; 1 = calendar month). See `PayCycle`.
    static let monthStartDay = "pref.monthStartDay"
    /// Unspent budget carries into the next period (opt-in, default off). See `BudgetRolloverMath`.
    static let budgetRolloverEnabled = "pref.budgetRolloverEnabled"
    static let accent = "pref.accent"             // Premium accent theme (see AccentOption/AppTheme)
    static let faceID = "pref.faceID"
    /// App lock (PIN gate) on/off; the PIN hash itself lives in the Keychain (see `PinLock`).
    static let appLockEnabled = "pref.appLockEnabled"
    /// Auto-lock delay in minutes: 0 = immediately, 1, or 5.
    static let autoLockMinutes = "pref.autoLockMinutes"
    /// Crashlytics collection — default-ON with an opt-out toggle (see `CrashReporting`).
    /// Unlike the `analytics` and `notifications` keys deleted alongside the trim, this one is read.
    static let crashReporting = "pref.crashReporting"
    static let premium = "pref.premium"           // effective Premium flag (subscription OR comped account)
    /// Account-comp entitlement cache: the server-granted `premium` auth claim (see `CompEntitlement`,
    /// set by functions/tools/comp.js). Cached so a comped account shows Premium instantly on launch.
    static let comp = "pref.comp"
    static let onboarded = "pref.onboarded"
    static let quizPending = "pref.quizPending"   // armed at sign-up; gates the one-time Insights setup quiz
    static let scanQuotaUsed = "quota.scansUsed"  // lifetime finalized AI scans (see ScanQuota)
    /// Whether the user has agreed to the one-time disclosure that a scanned receipt photo is sent to
    /// a third-party AI service (App Review 5.1.2(i)). Gates the first cloud scan; manual entry never
    /// checks it. See `ScanConsentSheet`.
    static let scanAIConsent = "pref.scanAIConsent"
    /// Dismissed Wellbeing tips, as newline-separated "periodId|tipId" entries (see WellbeingTipsStore).
    static let dismissedWellbeingTips = "wellbeing.dismissedTips"
    // ── End-of-period recap ──
    /// Whether the end-of-period recap interstitial is shown at all. Default on. Device-global (like
    /// appearance) — NOT reset on sign-out. See `RecapScheduler`.
    static let recapEnabled = "recap.enabled"
    /// Which period(s) trigger a recap (`RecapFrequency` raw value). Default MONTHLY. Device-global.
    static let recapFrequency = "recap.frequency"
    /// ISO date (yyyy-MM-dd) of the start of the last weekly recap already shown; empty = none yet.
    /// Per-user timing — reset on sign-out so the next account gets fresh boundaries.
    static let recapLastShownWeek = "recap.lastShownWeek"
    /// Pay-cycle month id (yyyy-MM) of the last monthly recap already shown; empty = none yet. Per-user.
    static let recapLastShownMonth = "recap.lastShownMonth"
}

/// Wipes every setting tied to the signed-in account — the app-lock PIN + biometric, the one-time
/// setup quiz, dismissed Wellbeing tips, and personal Home/Insights layout — while leaving
/// device/app display preferences (appearance, currency, language, date format, pay day) intact.
///
/// UserDefaults is a single device-global store, so anything left here leaks to the next account on
/// a shared device. (Identity comes from Firebase on iOS, so there's no local display name or search
/// history to clear — unlike Android.) Every sign-out and account-deletion path must call this; both
/// real sign-out paths (the Account button and Forgot-PIN) route through `AuthModel.signOut()`.
/// Android parity: `SettingsStore.clearUserState`.
enum UserState {
    static func clear() {
        let defaults = UserDefaults.standard
        for key in [
            SettingsKey.quizPending,
            SettingsKey.dismissedWellbeingTips,
            SettingsKey.appLockEnabled,
            SettingsKey.faceID,
            // Per-user recap timing (not the cadence preference, which is device-global like appearance):
            // reset so the next account on a shared device gets fresh recap boundaries. Android parity.
            SettingsKey.recapLastShownWeek,
            SettingsKey.recapLastShownMonth,
            HomeLayoutStore.orderKey,
            HomeLayoutStore.hiddenKey,
            InsightsLayoutStore.orderKey,
            InsightsLayoutStore.hiddenKey,
        ] {
            defaults.removeObject(forKey: key)
        }
        // The app-lock PIN hash lives in the Keychain, not UserDefaults.
        PinLock.clear()
    }
}

/// The free tier's receipt-scan allowance (Android parity). The count is a **lifetime** total with
/// no monthly reset: a scan is consumed only when a scanned receipt is actually finalized/saved —
/// failed reads and abandoned reviews never burn one — and it clears only on account deletion.
/// Manual entry is always free. (Device-level like Android; per-user split is a known follow-up.)
enum ScanQuota {
    static let freeLimit = 10
    static var used: Int { UserDefaults.standard.integer(forKey: SettingsKey.scanQuotaUsed) }
    static var remaining: Int { max(0, freeLimit - used) }
    static func reset() { UserDefaults.standard.removeObject(forKey: SettingsKey.scanQuotaUsed) }
}

/// The free tier's recurring-bill allowance (Android parity: `RecurringRepository.FREE_RECURRING_LIMIT`).
///
/// Bills only — income sources are never capped, since the point is planning what you earn against
/// what you owe, and capping income would just make the forecast wrong. Nothing is persisted: the
/// count is the live number of bills, so deleting one frees its slot immediately.
enum RecurringQuota {
    static let freeLimit = 3
}

/// App appearance preference, applied at the root via `.preferredColorScheme`.
enum AppearancePref: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Currencies offered in the picker (code, symbol, name). Europe-only cut (matches Android): kept
/// EUR/GBP/CHF/SEK/NOK and the home currencies of the other supported markets (DKK/PLN/CZK/RON).
/// Bulgaria uses EUR. EUR default; a removed currency saved by an existing user falls back to EUR.
enum CurrencyOption {
    static let all: [(code: String, symbol: String, name: String)] = [
        ("EUR", "€", "Euro"),
        ("GBP", "£", "British Pound"),
        ("CHF", "CHF", "Swiss Franc"),
        ("SEK", "kr", "Swedish Krona"),
        ("NOK", "kr", "Norwegian Krone"),
        ("DKK", "kr", "Danish Krone"),
        ("PLN", "zł", "Polish Złoty"),
        ("CZK", "Kč", "Czech Koruna"),
        ("RON", "lei", "Romanian Leu"),
    ]
    /// Symbol for a stored code; unknown/removed codes fall back to the euro (Android parity).
    static func symbol(_ code: String) -> String {
        all.first { $0.code == code }?.symbol ?? "€"
    }
}

/// App languages offered in the picker (BCP-47 code + native display name). "System default" follows
/// the device language; the rest match the Android build's 16 European locales. Native names are
/// intentionally left untranslated (each shown in its own language).
enum LanguageOption {
    static let all: [(code: String, name: String)] = [
        ("system", String(localized: "System default")),
        ("en", "English"),
        ("bg", "Български"),
        ("cs", "Čeština"),
        ("da", "Dansk"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fi", "Suomi"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("nb", "Norsk"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("pt", "Português"),
        ("ro", "Română"),
        ("ru", "Русский"),
        ("sv", "Svenska"),
    ]
    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? "English"
    }

    /// Apply the in-app language choice: an AppleLanguages override (takes effect on next
    /// launch, like Android's locale switch minus the live re-inflate).
    static func apply(_ code: String) {
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
    }
}
