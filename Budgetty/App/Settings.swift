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
        ("bg", "Български"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("fr", "Français"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("nl", "Nederlands"),
        ("pl", "Polski"),
        ("ro", "Română"),
        ("cs", "Čeština"),
        ("sv", "Svenska"),
        ("da", "Dansk"),
        ("fi", "Suomi"),
        ("el", "Ελληνικά"),
        ("hu", "Magyar"),
        ("tr", "Türkçe"),
        ("uk", "Українська"),
        ("ru", "Русский"),
        ("ja", "日本語"),
    ]
    static func name(_ code: String) -> String {
        all.first { $0.code == code }?.name ?? "English"
    }
}
