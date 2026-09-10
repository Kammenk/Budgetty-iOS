//
//  BackupSettingsRoundTripTests.swift
//  BudgettyTests
//
//  Guards the display / interpretation preferences half of backup restore (`SettingsDTO`): that every
//  field survives the JSON round-trip under the Android-parity keys, that the block is applied on a full
//  `.replace` ONLY (never a merge, which must not clobber the current device's prefs) and only for the
//  fields it carries, and — crucially — that a backup written BEFORE this change still decodes with the
//  block absent and leaves every on-device preference untouched. Port of Android's settings-backup test.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct BackupSettingsRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// A throwaway, disk-backed defaults isolated from `.standard` so the apply/merge assertions never
    /// touch the shared store (and so `SettingsDTO.apply` skips the live-`AppTheme` nudge — see its guard).
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)   // start clean even if a prior run crashed mid-test
        return d
    }

    private func fullSettings() -> SettingsDTO {
        SettingsDTO(
            currency: "GBP",
            dateFormat: "dmy",
            language: "de",
            themeMode: "dark",
            accent: "ocean",
            monthStartDay: 15,
            budgetRolloverEnabled: true,
            hiddenHomeSections: ["receipts"],
            hiddenInsightsSections: ["stats", "income"],
            homeSectionOrder: ["budgets", "totalSpent", "upcomingBills"],
            insightsSectionOrder: ["trend", "breakdown"],
            recapEnabled: false,
            recapFrequency: "WEEKLY")
    }

    // MARK: - Round-trip + on-disk key contract

    @Test func settingsSurviveTheJsonRoundTripUnderAndroidKeys() throws {
        var file = BackupFile()
        file.settings = fullSettings()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601        // matches BackupService's decoder
        let data = try encoder.encode(file)

        // Every field comes back byte-for-byte.
        let decoded = try BackupService.decode(data)
        #expect(decoded.settings == fullSettings())

        // The on-disk shape uses the cross-platform key names + string-case enums, and section
        // lists are JSON arrays — NOT the iOS `pref.*` UserDefaults key names.
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let s = try #require(obj["settings"] as? [String: Any])
        #expect(s["themeMode"] as? String == "dark")
        #expect(s["monthStartDay"] as? Int == 15)
        #expect(s["recapFrequency"] as? String == "WEEKLY")
        #expect(s["budgetRolloverEnabled"] as? Bool == true)
        #expect(s["homeSectionOrder"] as? [String] == ["budgets", "totalSpent", "upcomingBills"])
        #expect(s["appearance"] == nil)                // iOS internal key never leaks into the file
    }

    // MARK: - Backward compatibility

    @Test func backupWithoutSettingsBlockDecodesAndLeavesPrefsUntouched() throws {
        let ctx = try makeContext()
        let d = isolatedDefaults("BackupSettingsTests.legacy")
        defer { d.removePersistentDomain(forName: "BackupSettingsTests.legacy") }
        d.set("EUR", forKey: SettingsKey.currency)     // a pref the restore must NOT touch

        // A realistic pre-settings backup: a full BackupFile JSON with the `settings` key stripped
        // (Swift's synthesized Decodable throws on a missing NON-optional key, so this proves the
        // block is optional and its absence tolerated — same technique as the buying-limits guard).
        let full = try BackupService.export(from: ctx)
        var obj = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        obj.removeValue(forKey: "settings")
        let legacy = try JSONSerialization.data(withJSONObject: obj)

        let decoded = try BackupService.decode(legacy)
        #expect(decoded.settings == nil)

        // Even a full REPLACE restore of a settings-less backup leaves the device's prefs alone.
        try BackupService.restore(decoded, into: ctx, mode: .replace, defaults: d)
        #expect(d.string(forKey: SettingsKey.currency) == "EUR")
    }

    // MARK: - Apply on replace only

    @Test func mergeNeverAppliesSettingsButReplaceDoes() throws {
        let ctx = try makeContext()
        let d = isolatedDefaults("BackupSettingsTests.applyMode")
        defer { d.removePersistentDomain(forName: "BackupSettingsTests.applyMode") }

        // Seed the "current device" with distinct values.
        d.set("EUR", forKey: SettingsKey.currency)
        d.set(1, forKey: SettingsKey.monthStartDay)
        d.set("light", forKey: SettingsKey.appearance)

        var file = BackupFile()
        file.settings = fullSettings()

        // A MERGE must never clobber the current device's display prefs.
        try BackupService.restore(file, into: ctx, mode: .merge, defaults: d)
        #expect(d.string(forKey: SettingsKey.currency) == "EUR")
        #expect(d.integer(forKey: SettingsKey.monthStartDay) == 1)
        #expect(d.string(forKey: SettingsKey.appearance) == "light")

        // A full REPLACE applies them — currency (symbol), month-start day + rollover (bucketing),
        // theme, recap cadence, and the section layout (rejoined to the stores' CSV shape).
        try BackupService.restore(file, into: ctx, mode: .replace, defaults: d)
        #expect(d.string(forKey: SettingsKey.currency) == "GBP")
        #expect(d.integer(forKey: SettingsKey.monthStartDay) == 15)
        #expect(d.string(forKey: SettingsKey.appearance) == "dark")
        #expect(d.bool(forKey: SettingsKey.budgetRolloverEnabled) == true)
        #expect(d.string(forKey: SettingsKey.recapFrequency) == "WEEKLY")
        #expect(d.string(forKey: HomeLayoutStore.orderKey) == "budgets,totalSpent,upcomingBills")
        #expect(d.string(forKey: HomeLayoutStore.hiddenKey) == "receipts")
        #expect(d.string(forKey: InsightsLayoutStore.hiddenKey) == "stats,income")
        // Language also sets the AppleLanguages override, exactly as the settings picker does.
        #expect(d.string(forKey: SettingsKey.language) == "de")
        #expect(d.stringArray(forKey: "AppleLanguages") == ["de"])
    }

    @Test func replaceAppliesOnlyThePresentFields() throws {
        let ctx = try makeContext()
        let d = isolatedDefaults("BackupSettingsTests.partial")
        defer { d.removePersistentDomain(forName: "BackupSettingsTests.partial") }

        // The device is on Sage; the backup carries a currency but NO accent.
        d.set("sage", forKey: SettingsKey.accent)
        var file = BackupFile()
        file.settings = SettingsDTO(currency: "CHF")

        try BackupService.restore(file, into: ctx, mode: .replace, defaults: d)
        #expect(d.string(forKey: SettingsKey.currency) == "CHF")   // present → applied
        #expect(d.string(forKey: SettingsKey.accent) == "sage")    // absent → untouched
    }

    // MARK: - Snapshot reads effective defaults

    @Test func currentSnapshotUsesTheAppStorageDefaultsForUnsetKeys() throws {
        let d = isolatedDefaults("BackupSettingsTests.current")
        defer { d.removePersistentDomain(forName: "BackupSettingsTests.current") }

        // Nothing set: the snapshot must reflect what the user actually sees, not UserDefaults' zeros.
        let snap = SettingsDTO.current(from: d)
        #expect(snap.currency == "EUR")
        #expect(snap.monthStartDay == 1)              // not 0 (UserDefaults.integer for an absent key)
        #expect(snap.budgetRolloverEnabled == false)
        #expect(snap.recapEnabled == true)            // default ON
        #expect(snap.recapFrequency == "BOTH")
        #expect(snap.themeMode == "system")
        #expect(snap.accent == "violet")
        #expect(snap.hiddenHomeSections == ["weekComparison"])   // the Home default-hidden section

        // A set value flows straight through, and CSV layout state splits into an array.
        d.set("PLN", forKey: SettingsKey.currency)
        d.set("totalSpent,budgets", forKey: HomeLayoutStore.orderKey)
        let snap2 = SettingsDTO.current(from: d)
        #expect(snap2.currency == "PLN")
        #expect(snap2.homeSectionOrder == ["totalSpent", "budgets"])
    }
}
