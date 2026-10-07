//
//  WarrantyStatus.swift
//  Budgetty
//
//  Pure warranty math + the free-tier cap (no SwiftData/SwiftUI), a 1:1 port of Android's
//  `ui/warranties/WarrantyStatus.kt` + `Warranties`. Nothing is scheduled (the app has no push
//  reminders) — warranties surface in-app.
//

import Foundation

/// Where a warranty sits in its life: still covered, ending within 30 days, or past.
enum WarrantyState { case active, expiringSoon, expired }

struct WarrantyStatus {
    let expiryDate: Date
    /// 0...1 fraction of the coverage period elapsed — drives the ring.
    let elapsedFraction: Double
    /// Whole days until expiry; negative once expired.
    let daysLeft: Int
    /// Whole months until expiry (floored, min 0) — the active-state chip.
    let monthsLeft: Int
    let state: WarrantyState
}

enum Warranties {
    /// Free users can track this many warranties; adding past it routes to the paywall.
    static let freeLimit = 5
    /// A warranty within this many days of expiry counts as "expiring soon".
    static let expiringSoonDays = 30

    /// Derives the status for a warranty bought on `purchaseDate` for `durationMonths`.
    static func status(purchaseDate: Date, durationMonths: Int, today: Date = .now,
                       calendar cal: Calendar = .current) -> WarrantyStatus {
        let start = cal.startOfDay(for: purchaseDate)
        let now = cal.startOfDay(for: today)
        let expiry = cal.date(byAdding: .month, value: durationMonths, to: start) ?? start
        let totalDays = max(1, days(start, expiry, cal))
        let elapsedDays = min(max(0, days(start, now, cal)), totalDays)
        let fraction = min(1, max(0, Double(elapsedDays) / Double(totalDays)))
        let daysLeft = days(now, expiry, cal)
        let monthsLeft = max(0, cal.dateComponents([.month], from: now, to: expiry).month ?? 0)
        let state: WarrantyState =
            daysLeft < 0 ? .expired : (daysLeft <= expiringSoonDays ? .expiringSoon : .active)
        return WarrantyStatus(expiryDate: expiry, elapsedFraction: fraction, daysLeft: daysLeft,
                              monthsLeft: monthsLeft, state: state)
    }

    private static func days(_ from: Date, _ to: Date, _ cal: Calendar) -> Int {
        cal.dateComponents([.day], from: from, to: to).day ?? 0
    }
}
