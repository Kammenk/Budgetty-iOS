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
    static let notifications = "pref.notifications"
    static let faceID = "pref.faceID"
    static let analytics = "pref.analytics"
    /// Crashlytics collection — default-ON with an opt-out toggle (see `CrashReporting`).
    static let crashReporting = "pref.crashReporting"
    static let premium = "pref.premium"           // effective Premium flag (subscription OR tester)
    static let testerPremium = "pref.testerPremium" // hidden 11-tap tester unlock, kept separate
    static let onboarded = "pref.onboarded"
    static let quizPending = "pref.quizPending"   // armed at sign-up; gates the one-time Insights setup quiz
    static let scanQuotaUsed = "quota.scansUsed"  // lifetime finalized AI scans (see ScanQuota)
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
