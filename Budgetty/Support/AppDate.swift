//
//  AppDate.swift
//  Budgetty
//
//  The "Date format" preference (Account → Preferences) and the shared formatters every
//  user-facing day-level date goes through. Parsing (ReceiptExtractor), fixed formats
//  (backup filenames) and month-only labels stay locale/ISO-driven and don't come here.
//

import Foundation

enum DateFormatOption: String, CaseIterable, Identifiable {
    case system                 // follow the device locale
    case dayMonthYear = "dmy"   // 5 Jun 2026
    case monthDayYear = "mdy"   // Jun 5, 2026
    case numeric = "dots"       // 05.06.2026

    var id: String { rawValue }

    /// The persisted selection, for call sites that aren't SwiftUI views. Views that render
    /// dates should also declare `@AppStorage(SettingsKey.dateFormat)` so they re-render on change.
    static var current: DateFormatOption {
        DateFormatOption(rawValue: UserDefaults.standard.string(forKey: SettingsKey.dateFormat) ?? "") ?? .system
    }

    /// Picker row title — the concrete shape each option produces, from today's date.
    var pickerLabel: String {
        self == .system ? "System default" : shortWithYear(.now)
    }

    /// Compact value shown on the Account row.
    var settingLabel: String {
        self == .system ? "System" : shortWithYear(.now)
    }

    /// "5 June 2026" / "June 5, 2026" / "05.06.2026" — receipt detail header.
    func long(_ date: Date) -> String {
        switch self {
        case .system: return formatted(template: "d MMMM y", date)
        case .dayMonthYear: return formatted("d MMMM yyyy", date)
        case .monthDayYear: return formatted("MMMM d, yyyy", date)
        case .numeric: return formatted("dd.MM.yyyy", date)
        }
    }

    /// "5 Jun" / "Jun 5" / "05.06" — list rows and day headers.
    func short(_ date: Date) -> String {
        switch self {
        case .system: return formatted(template: "d MMM", date)
        case .dayMonthYear: return formatted("d MMM", date)
        case .monthDayYear: return formatted("MMM d", date)
        case .numeric: return formatted("dd.MM", date)
        }
    }

    /// "5 Jun 2026" / "Jun 5, 2026" / "05.06.2026" — short form when the year matters.
    func shortWithYear(_ date: Date) -> String {
        switch self {
        case .system: return formatted(template: "d MMM y", date)
        case .dayMonthYear: return formatted("d MMM yyyy", date)
        case .monthDayYear: return formatted("MMM d, yyyy", date)
        case .numeric: return formatted("dd.MM.yyyy", date)
        }
    }

    /// "5/7" / "7/5" / "5.7" — the tiny trend-bar labels.
    func tiny(_ date: Date) -> String {
        switch self {
        case .system, .dayMonthYear: return formatted("d/M", date)
        case .monthDayYear: return formatted("M/d", date)
        case .numeric: return formatted("d.M", date)
        }
    }

    private func formatted(_ format: String, _ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = format; return f.string(from: date)
    }

    private func formatted(template: String, _ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(template); return f.string(from: date)
    }
}
