//
//  NewStringsLocalizationTests.swift
//  BudgettyTests
//
//  The restore prompt ("Import 113 receipts and 345 items?") showed in English in a German UI
//  (device test 2026-10-09): `confirmationDialog` takes a `String` title verbatim, so it never reached
//  the catalog. These resolve the strings added for that fix (and the fortnight switch sheet / manual
//  entry) through the COMPILED catalog of every shipped locale, so a missing translation, a broken
//  format specifier or a key that no longer matches the code's interpolation fails here.
//

import Testing
import Foundation
@testable import Budgetty

struct NewStringsLocalizationTests {

    private static let locales = ["bg", "cs", "da", "de", "es", "fi", "fr", "hu", "it", "nb", "nl", "pl",
                                  "pt", "ro", "ru", "sv"]

    private func bundle(_ lang: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: lang, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func restorePromptTitleIsGermanInAGermanUI() throws {
        let de = try bundle("de")
        #expect(String(localized: "Import \(113) receipts and \(345) items?", bundle: de)
                == "113 Belege und 345 Artikel importieren?")
        #expect(String(localized: "Import backup?", bundle: de) == "Backup importieren?")
        #expect(String(localized: "That file isn't a valid Budgetty backup.", bundle: de)
                == "Diese Datei ist kein gültiges Budgetty-Backup.")
    }

    @Test func englishRestorePromptPluralizesBothCounts() throws {
        let en = try bundle("en")
        #expect(String(localized: "Import \(1) receipts and \(1) items?", bundle: en, locale: Locale(identifier: "en"))
                == "Import 1 receipt and 1 item?")
        #expect(String(localized: "Import \(113) receipts and \(345) items?", bundle: en, locale: Locale(identifier: "en"))
                == "Import 113 receipts and 345 items?")
    }

    @Test func everyNewStringIsTranslatedInEveryLocale() throws {
        let keys = ["Import backup?", "Import %lld receipts and %lld items?", "That file isn't a valid Budgetty backup.",
                    "Couldn't prepare the export.", "Select category", "Your first fortnight",
                    "This fortnight · %@ – %@", "%@ → %@ / fortnight", "%@ / fortnight"]
        for lang in Self.locales {
            let b = try bundle(lang)
            for key in keys {
                let value = b.localizedString(forKey: key, value: "∅", table: nil)
                #expect(value != "∅" && value != key, "\(lang): \(key)")
            }
        }
    }

    @Test func fortnightRowsKeepBothArgumentsInEveryLocale() throws {
        for lang in Self.locales {
            let b = try bundle(lang)
            let window = String(localized: "This fortnight · \("6 Oct") – \("19 Oct")", bundle: b)
            #expect(window.contains("6 Oct") && window.contains("19 Oct"), "\(lang): \(window)")
            let budget = String(localized: "\("650 €") → \("300 €") / fortnight", bundle: b)
            #expect(budget.hasPrefix("650 € → 300 € "), "\(lang): \(budget)")
        }
    }
}
