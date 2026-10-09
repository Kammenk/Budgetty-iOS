//
//  AmountInputTests.swift
//  BudgettyTests
//
//  The shared money-input rules behind `AmountField` (every amount field in the app). The field keeps
//  the text as typed and writes its value on every keystroke, so these rules ARE what a Save button
//  sees: "2,80" typed and saved at once must be 2.80 (device test 2026-10-09 stored 2), comma and dot
//  decimals both work whatever the region, a blank field means 0, and a stored value reloads with two
//  decimals and parses back to itself.
//

import Testing
import Foundation
@testable import Budgetty

struct AmountInputTests {
    private let de = Locale(identifier: "de_DE")
    private let en = Locale(identifier: "en_US")

    private func dec(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    // MARK: - Parsing

    @Test func commaAndDotDecimalsBothParse() {
        #expect(AmountInput.parse("2,80") == dec("2.80"))
        #expect(AmountInput.parse("2.80") == dec("2.80"))
        #expect(AmountInput.parse("0,5") == dec("0.5"))
        #expect(AmountInput.parse("18.50") == dec("18.50"))
    }

    @Test func thousandsSeparatorsAndSymbolsAreTolerated() {
        #expect(AmountInput.parse("1.234,56") == dec("1234.56"))
        #expect(AmountInput.parse("1,234.56") == dec("1234.56"))
        #expect(AmountInput.parse("€ 3") == 3)
        #expect(AmountInput.parse("12 €") == 12)
    }

    @Test func noNumberParsesToNil() {
        #expect(AmountInput.parse("") == nil)
        #expect(AmountInput.parse("abc") == nil)
        #expect(AmountInput.parse("-") == nil)
    }

    // MARK: - What the field writes

    @Test func blankFieldMeansZeroAndAPartialEntryKeepsTheValue() {
        #expect(AmountInput.value(forText: "") == 0)
        #expect(AmountInput.value(forText: "   ") == 0)
        #expect(AmountInput.value(forText: "-") == nil)          // mid-typing: leave the value alone
        #expect(AmountInput.value(forText: "2,") == 2)            // the comma is kept in the text
        #expect(AmountInput.value(forText: "2,8") == dec("2.8"))
        #expect(AmountInput.value(forText: "2,80") == dec("2.80"))
    }

    // MARK: - Display

    @Test func storedValueShowsWithTwoDecimalsInTheUsersRegion() {
        #expect(AmountInput.text(for: 300, locale: de) == "300,00")
        #expect(AmountInput.text(for: 300, locale: en) == "300.00")
        #expect(AmountInput.text(for: dec("2.8"), locale: de) == "2,80")
        #expect(AmountInput.text(for: dec("1234.5"), locale: de) == "1234,50")   // no grouping to trip on
        #expect(AmountInput.text(for: dec("1.845"), locale: de) == "1,845")      // extra precision kept
    }

    @Test func zeroShowsBlankSoThePlaceholderShows() {
        #expect(AmountInput.text(for: 0, locale: de) == "")
        #expect(AmountInput.decimalPlaceholder(locale: de) == "0,00")
        #expect(AmountInput.decimalPlaceholder(locale: en) == "0.00")
    }

    @Test func displayedTextParsesBackToTheSameValue() {
        for value in [dec("300"), dec("2.8"), dec("1.845"), dec("1234.5"), dec("0.01")] {
            for locale in [de, en] {
                #expect(AmountInput.value(forText: AmountInput.text(for: value, locale: locale)) == value,
                        "\(value) in \(locale.identifier)")
            }
        }
    }

    // MARK: - Whole numbers

    @Test func wholeNumberFieldParsesDigitsAndLeavesBlankAlone() {
        #expect(WholeNumberField.parse("15") == 15)
        #expect(WholeNumberField.parse(" 24 ") == 24)
        #expect(WholeNumberField.parse("") == nil)
        #expect(WholeNumberField.parse("abc") == nil)
    }
}
