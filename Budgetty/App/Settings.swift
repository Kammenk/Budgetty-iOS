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
    static let premium = "pref.premium"           // effective Premium flag (subscription OR tester)
    static let testerPremium = "pref.testerPremium" // hidden 11-tap tester unlock, kept separate
    static let onboarded = "pref.onboarded"
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
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Currencies offered in the picker (code, symbol, name). EUR default.
enum CurrencyOption {
    static let all: [(code: String, symbol: String, name: String)] = [
        ("EUR", "€", "Euro"),
        ("USD", "$", "US Dollar"),
        ("GBP", "£", "British Pound"),
        ("BGN", "лв", "Bulgarian Lev"),
        ("CHF", "Fr", "Swiss Franc"),
        ("SEK", "kr", "Swedish Krona"),
        ("PLN", "zł", "Polish Złoty"),
        ("CZK", "Kč", "Czech Koruna"),
        ("RON", "lei", "Romanian Leu"),
        ("JPY", "¥", "Japanese Yen"),
    ]
    static func symbol(_ code: String) -> String {
        all.first { $0.code == code }?.symbol ?? code
    }
}

/// App languages offered in the picker (BCP-47 code + native display name). "System" follows the
/// device language; the rest match the Android build's 21-language set.
enum LanguageOption {
    static let all: [(code: String, name: String)] = [
        ("system", "System default"),
        ("en", "English"),
        ("ar", "العربية"),
        ("bg", "Български"),
        ("bn", "বাংলা"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("hi", "हिन्दी"),
        ("id", "Bahasa Indonesia"),
        ("it", "Italiano"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("pt", "Português"),
        ("ru", "Русский"),
        ("tr", "Türkçe"),
        ("uk", "Українська"),
        ("ur", "اردو"),
        ("vi", "Tiếng Việt"),
        ("zh-Hans", "简体中文"),
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

