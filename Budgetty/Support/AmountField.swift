//
//  AmountField.swift
//  Budgetty
//
//  The app's money input. Every amount field goes through `AmountField` rather than
//  `TextField(value:format: .number)`, which only writes its binding on COMMIT (return / focus loss)
//  and parses with the region's number format — so typing "2,80" and tapping Save straight away
//  stored 2 (device test 2026-10-09). This field keeps the text exactly as typed and writes the bound
//  value on every keystroke through one tolerant parser (comma OR dot decimals, whatever the region),
//  so whatever reads the value — a Save button, a live total, a live-saving row — always sees what's
//  on screen.
//
//  `WholeNumberField` is the same idea for the two integer inputs (a bill's day of month, a custom
//  warranty length).
//

import SwiftUI

/// Parsing + display rules for typed money amounts. Pure, so they unit-test directly.
enum AmountInput {

    /// The amount `text` spells, or nil when it holds no number. Tolerant like the CSV importer
    /// (`CsvImport.parseAmount`, the app's one amount parser): "2,80", "2.80", "1.234,56", "1,234.56",
    /// "€ 3" and "(4.50)" all read as expected; a lone comma is a decimal point (European).
    static func parse(_ text: String) -> Decimal? { CsvImport.parseAmount(text) }

    /// What a field's current text means for its bound value: blank → 0 ("no amount", which every
    /// caller treats as unset), a number → that number, anything else (e.g. a lone "-" mid-typing) →
    /// nil, meaning "leave the value as it is".
    static func value(forText text: String) -> Decimal? {
        text.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : parse(text)
    }

    /// How a stored value is shown when the field (re)loads: blank for 0 — so the placeholder shows and
    /// typing never appends to a "0" ("018.50") — else at least two decimals in the user's region
    /// ("300,00", "2,80"), more only when the amount has them ("1,845").
    static func text(for value: Decimal, locale: Locale = .current) -> String {
        guard value != 0 else { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(2...6)).locale(locale))
    }

    /// "0,00" / "0.00" in the user's region — the same decimal separator the decimal pad offers.
    static func decimalPlaceholder(locale: Locale = .current) -> String {
        Decimal.zero.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}

/// A money `TextField` bound to a `Decimal` that is always up to date with what's typed (see the file
/// header). Blank writes 0. Carries the decimal pad; callers add alignment, font, frame and focus as
/// before (`.focused` / `.multilineTextAlignment` reach the inner field).
struct AmountField: View {
    private let placeholder: String
    @Binding private var value: Decimal
    @State private var text: String

    init(_ placeholder: String = "0", value: Binding<Decimal>) {
        self.placeholder = placeholder
        _value = value
        _text = State(initialValue: AmountInput.text(for: value.wrappedValue))
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .onChange(of: text) { _, typed in
                if let parsed = AmountInput.value(forText: typed), parsed != value { value = parsed }
            }
            // Follow a value set from elsewhere (a sheet loading the saved amount after appearing, a
            // reset), but never rewrite the text while it already means that value — mid-typing "2,"
            // parses to 2, and reformatting it would eat the comma.
            .onChange(of: value) { _, newValue in
                if AmountInput.value(forText: text) != newValue { text = AmountInput.text(for: newValue) }
            }
    }
}

/// The integer counterpart: a whole-number `TextField` (number pad) that writes its `Int` binding on
/// every keystroke. A blank field leaves the value unchanged (there is no "zero days"); non-digits are
/// ignored. A value changed elsewhere (a stepper, a clamp) is reflected back into the text.
struct WholeNumberField: View {
    private let placeholder: String
    @Binding private var value: Int
    @State private var text: String

    init(_ placeholder: String, value: Binding<Int>) {
        self.placeholder = placeholder
        _value = value
        _text = State(initialValue: String(value.wrappedValue))
    }

    /// The number `text` spells (digits only), or nil when it has none.
    static func parse(_ text: String) -> Int? { Int(text.filter(\.isNumber).prefix(9)) }

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .onChange(of: text) { _, typed in
                if let parsed = Self.parse(typed), parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                if Self.parse(text) != newValue { text = String(newValue) }
            }
    }
}
