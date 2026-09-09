//
//  ReceiptDateReview.swift
//  Budgetty
//
//  Whether a just-scanned receipt's date looks implausible and should be flagged for the user to
//  confirm before saving — a direct port of Android's `receiptDateNeedsReview` (ui/util). A soft
//  review nudge only; the date is never auto-corrected.
//

import Foundation

enum ReceiptDateReview {

    /// How recent a just-scanned receipt's purchase date is expected to be. A date more than this many
    /// days before "today" — or any date in the future — is treated as a likely misread and surfaced
    /// for review instead of saved silently. Mirrors Android's `RECEIPT_DATE_REVIEW_WINDOW_DAYS`.
    static let windowDays = 45

    /// True when `date` can't plausibly be a receipt scanned around `today`: a future date, or one more
    /// than `windowDays` in the past. Such a date is usually the extractor misreading the printed date —
    /// a wrong month (8 Sep read as 8 Apr), or an unrelated date/year lifted off the receipt (copyright,
    /// loyalty, card expiry, registration). Callers only highlight the date on the strength of this; it
    /// is never auto-corrected, so a genuine old receipt still saves with the date the user picks.
    static func needsReview(_ date: Date, today: Date = .now, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        if day > todayStart { return true }
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else {
            return false
        }
        return day < cutoff
    }
}
