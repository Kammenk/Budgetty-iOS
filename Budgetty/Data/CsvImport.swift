//
//  CsvImport.swift
//  Budgetty
//
//  Pure CSV-import parsing: turn raw file text into a table, guess which column feeds which field, and
//  parse one row into an importable transaction. No SwiftData/SwiftUI deps, so the whole mapping and
//  number/date handling is unit-testable. The view layer resolves categories, de-duplicates against
//  existing data and writes the rows. 1:1 port of Android's `data/csvimport/CsvImport.kt`.
//

import Foundation

/// The field a CSV column can feed; the Map step cycles through these in order.
enum CsvField: Int, CaseIterable { case date, amount, store, category, ignore }

/// How the sign of the amount column is read. Budgetty stores only expenses, so the "income" side is
/// recognised (to report + skip it) rather than imported.
enum SignConvention: CaseIterable, Identifiable { case minusIsExpense, minusIsIncome; var id: Self { self } }

/// A row's outcome after parsing: an importable `expense`, a recognised but un-importable `income`
/// (Budgetty tracks income as recurring, not as transactions), or an unparseable `invalid` row.
enum RowKind { case expense, income, invalid }

/// The parsed header + data rows of a CSV (data rows padded/truncated to the header width).
struct CsvTable {
    let headers: [String]
    let rows: [[String]]
    var isEmpty: Bool { headers.isEmpty }
}

/// One CSV row resolved against a column mapping. `amount` is the absolute expense amount (always
/// positive) for a `.expense`; `category` is the raw CSV category (the caller canonicalises it).
struct ParsedImportRow {
    let date: Date?
    let name: String
    let amount: Decimal?
    let category: String
    let kind: RowKind
}

enum CsvImport {

    // Date patterns per the Review step's format choice. "d"/"M" accept 1- or 2-digit values. Parsed
    // with a non-lenient `DateFormatter` (en_US_POSIX), which rejects impossible dates like 31 Feb
    // instead of coercing them — the behaviour Android gets from `ResolverStyle.STRICT`.
    static let patternDMY = "d/M/yyyy"
    static let patternMDY = "M/d/yyyy"
    static let patternISO = "yyyy-M-d"

    enum MappingError: Equatable {
        case missing([CsvField])
        case duplicated(CsvField)
    }

    /// Parses `text` into a `CsvTable` — RFC-4180-ish: fields may be quoted, a quoted field may contain
    /// commas and newlines, and an embedded quote is written doubled (`""`). Matches the quoting
    /// `ExportBuilder.toCsv` produces, so Budgetty's own exports round-trip. The first non-blank line is
    /// the header; blank lines are dropped.
    static func parse(_ text: String) -> CsvTable {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if c == "\"" { inQuotes = false }
                else { field.append(c) }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                endField()
            } else if c == "\n" {
                endRow()
            } else if c == "\r" {
                endRow(); if i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { endRow() }

        let cleaned = rows.filter { r in r.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let headerRow = cleaned.first else { return CsvTable(headers: [], rows: []) }
        let headers = headerRow.map { $0.trimmingCharacters(in: .whitespaces) }
        let dataRows = cleaned.dropFirst().map { r in (0..<headers.count).map { idx in idx < r.count ? r[idx] : "" } }
        return CsvTable(headers: headers, rows: Array(dataRows))
    }

    /// Guesses a `CsvField` for each header from its name; Date/Amount/Store/Category are each assigned
    /// to the first matching header only (so nothing is mapped twice by default), the rest Ignore.
    static func guessMapping(_ headers: [String]) -> [CsvField] {
        var taken = Set<CsvField>()
        return headers.map { header in
            let h = header.lowercased()
            let guess: CsvField
            if dateKeys.contains(where: h.contains) && !taken.contains(.date) {
                guess = .date
            } else if amountKeys.contains(where: h.contains) && !h.contains("balance") && !taken.contains(.amount) {
                // "balance" is a running total, never the transaction amount — exclude it.
                guess = .amount
            } else if categoryKeys.contains(where: h.contains) && !taken.contains(.category) {
                guess = .category
            } else if storeKeys.contains(where: h.contains) && !taken.contains(.store) {
                guess = .store
            } else {
                guess = .ignore
            }
            if guess != .ignore { taken.insert(guess) }
            return guess
        }
    }

    /// Whether a `mapping` can be imported: Date and Amount are mapped exactly once each.
    static func mappingError(_ mapping: [CsvField]) -> MappingError? {
        let missing = [CsvField.date, .amount].filter { f in !mapping.contains(f) }
        if !missing.isEmpty { return .missing(missing) }
        let duped = [CsvField.date, .amount, .store, .category].first { f in mapping.filter { $0 == f }.count > 1 }
        return duped.map { .duplicated($0) }
    }

    /// Parses one raw `row` against `mapping`, the chosen `pattern` and `sign` convention.
    static func parseRow(_ row: [String], mapping: [CsvField], pattern: String,
                         sign: SignConvention, calendar: Calendar = .current) -> ParsedImportRow {
        func value(_ field: CsvField) -> String {
            guard let idx = mapping.firstIndex(of: field), idx < row.count else { return "" }
            return row[idx].trimmingCharacters(in: .whitespaces)
        }
        let date = parseDate(value(.date), pattern: pattern, calendar: calendar)
        let signed = parseAmount(value(.amount))
        let name = titleCase(value(.store)).isEmpty ? defaultName : titleCase(value(.store))
        let category = value(.category)
        let kind: RowKind
        if date == nil || signed == nil || signed == 0 {
            kind = .invalid
        } else if isExpense(signed!, sign) {
            kind = .expense
        } else {
            kind = .income
        }
        return ParsedImportRow(date: date, name: name, amount: signed.map { abs($0) }, category: category, kind: kind)
    }

    /// Parses `raw` as a date using `pattern` (English month names); nil on any failure. Non-lenient,
    /// so impossible dates (31 Feb) are rejected rather than coerced.
    static func parseDate(_ raw: String, pattern: String, calendar: Calendar = .current) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.timeZone = calendar.timeZone
        fmt.isLenient = false
        fmt.dateFormat = pattern
        guard let day = fmt.date(from: trimmed) else { return nil }
        return calendar.startOfDay(for: day)
    }

    /// Parses a monetary `raw` string to a signed `Decimal`, tolerating currency symbols, spaces,
    /// thousands separators and parenthesised negatives. Decimal separator: when both '.' and ',' are
    /// present the last one wins (the other is thousands); a lone ',' is treated as the decimal point
    /// (European). Returns nil when there's no number.
    static func parseAmount(_ raw: String) -> Decimal? {
        var t = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        if t.isEmpty { return nil }
        let negative = t.hasPrefix("-") || (t.hasPrefix("(") && t.hasSuffix(")"))
        t = String(t.filter { $0.isNumber || $0 == "." || $0 == "," })
        if t.isEmpty { return nil }
        let hasDot = t.contains("."), hasComma = t.contains(",")
        if hasDot && hasComma {
            if t.lastIndex(of: ".")! > t.lastIndex(of: ",")! { t = t.replacingOccurrences(of: ",", with: "") }
            else { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        } else if hasComma {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        guard let n = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return negative ? -n : n
    }

    /// A stable key for duplicate detection: same day, same absolute amount, same store (normalised).
    static func dedupKey(date: Date, amount: Decimal, name: String, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let rounded = NSDecimalNumber(decimal: amount).rounding(accordingToBehavior:
            NSDecimalNumberHandler(roundingMode: .plain, scale: 2, raiseOnExactness: false,
                                   raiseOnOverflow: false, raiseOnUnderflow: false, raiseOnDivideByZero: false))
        return "\(day)|\(rounded.stringValue)|\(name.lowercased().trimmingCharacters(in: .whitespaces))"
    }

    private static func isExpense(_ signed: Decimal, _ sign: SignConvention) -> Bool {
        switch sign {
        case .minusIsExpense: return signed < 0
        case .minusIsIncome: return signed > 0
        }
    }

    /// Title-cases an UPPER/lower store name ("LIDL SAGT DANKE" -> "Lidl Sagt Danke").
    private static func titleCase(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map { $0.lowercased().prefix(1).uppercased() + $0.lowercased().dropFirst() }
            .joined(separator: " ")
    }

    private static let defaultName = "Imported"
    private static let dateKeys = ["date", "booking", "buchung", "datum", "time"]
    private static let amountKeys = ["amount", "betrag", "sum", "value", "price", "montant", "importe", "debit"]
    private static let categoryKeys = ["categ", "kategorie"]
    private static let storeKeys =
        ["payee", "merchant", "store", "description", "name", "recipient", "beneficiary", "narrative"]
}
