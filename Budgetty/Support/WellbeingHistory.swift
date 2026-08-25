//
//  WellbeingHistory.swift
//  Budgetty
//
//  Pure history-snapshot logic for the Wellbeing score (§3.1) — the Swift port of Android's
//  `WellbeingHistory`. No SwiftUI, no ModelContext (it references the `WellbeingScoreEntity` type only,
//  like `RecapBuilder` references SwiftData models), so it unit-tests without a store. `WellbeingScan`
//  uses it to build the row it persists for a CLOSED pay-cycle month via `WellbeingScoreStore`; the
//  in-flight month is never snapshotted — its score is still moving, and §3.1's whole point is a final
//  record.
//
//  The saved snapshot is deliberately NOT a recompute: scoring an old month against today's budgets and
//  goals would silently rewrite the user's past and make the trend line lie, so once written a month's
//  row is left alone (it is only re-touched while it is still the *just-closed* month, idempotently).
//

import Foundation
import SwiftData

enum WellbeingHistory {

    /// Below this many STORED closed months the sparkline renders nothing at all — no placeholder (§3.2).
    static let minTrendMonths = 2

    /// The "yyyy-MM" id of the pay-cycle month at `offset` from `today` (0 = current, -1 = just-closed).
    /// Uses the same `PayCycle` anchoring as the rest of the app, so it matches `WellbeingSummary`'s
    /// current-month id exactly. `en_US_POSIX` + an explicit calendar keeps the id deterministic
    /// (matches `RecapScheduler.justClosedMonthId`).
    static func periodId(_ today: Date, monthStartDay: Int, offset: Int,
                         calendar cal: Calendar = .current) -> String {
        let start = PayCycle.month(today, startDay: monthStartDay, offset: offset, calendar: cal).start
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f.string(from: start)
    }

    /// The snapshot row to persist for the just-closed cycle, or nil when that cycle can't be scored yet
    /// (too little data — `WellbeingScore.score` is nil). `closedScore` MUST be the previous, completed
    /// cycle's score and `closedPeriodId` its id (offset -1); the caller never passes the in-flight cycle
    /// here, so the current month has no path into history. Returns a DETACHED entity (not yet inserted);
    /// `WellbeingScoreStore.upsert` persists it idempotently.
    static func closedSnapshot(closedPeriodId: String, closedScore: WellbeingScore,
                               computedAt: Date) -> WellbeingScoreEntity? {
        guard let score = closedScore.score, let band = closedScore.band else { return nil }
        return WellbeingScoreEntity(
            periodId: closedPeriodId,
            score: score,
            band: band.name,
            componentsJson: encodeComponents(closedScore.components),
            computedAt: computedAt)
    }

    /// Stable JSON object of componentKey -> sub-score (explicit null when the component wasn't counted).
    /// Built by hand so the order is fixed (Savings, Budget, Trend, Subscriptions, Goals) and un-scored
    /// components stay as explicit `null`s — the future breakdown view needs "not counted" told apart
    /// from "absent key". Mirrors Android's Gson `serializeNulls()` over a `LinkedHashMap`.
    static func encodeComponents(_ components: [WellbeingComponent]) -> String {
        let parts = components.map { c in
            "\"\(c.key.serialKey)\":\(c.score.map(String.init) ?? "null")"
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Reads `encodeComponents` back — for the future breakdown-over-time view. Never throws: a malformed
    /// payload decodes to an empty map. An un-scored component is kept as a present key with a `nil`
    /// value (via `updateValue`, which — unlike subscript-assign-nil — does not drop the key).
    static func decodeComponents(_ json: String) -> [String: Int?] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var result: [String: Int?] = [:]
        for (key, value) in obj {
            if let n = value as? Int {
                result.updateValue(n, forKey: key)
            } else {
                result.updateValue(nil, forKey: key)   // JSON null (NSNull) → present-but-nil
            }
        }
        return result
    }

    /// The trend-sparkline model (§3.2) from the stored closed months `recentClosed` (oldest→newest)
    /// plus the in-flight `liveScore`, which becomes the dashed ghost / hollow dot at the end.
    ///
    /// Returns nil below `minTrendMonths` stored months — one point isn't a trend, so the caller renders
    /// NOTHING (no placeholder). The caption delta is "now" (the live score, or the last closed month
    /// when there is no live score) minus the first shown month, so "Up 8 since March." reads honestly.
    static func trend(_ recentClosed: [WellbeingScoreEntity], liveScore: Int?) -> WellbeingTrend? {
        let points = recentClosed.compactMap { e in
            YearMonth(id: e.periodId).map { WellbeingTrendPoint(yearMonth: $0, score: e.score) }
        }
        guard points.count >= minTrendMonths, let first = points.first else { return nil }
        let now = liveScore ?? points[points.count - 1].score
        return WellbeingTrend(closed: points, liveScore: liveScore,
                              deltaSinceFirst: now - first.score, firstMonth: first.yearMonth)
    }
}

// MARK: - Trend model (§3.2)

/// A calendar year+month, parsed from a "yyyy-MM" `periodId`. The Swift stand-in for Android's
/// `java.time.YearMonth` in the trend model.
struct YearMonth: Equatable {
    let year: Int
    let month: Int

    /// Parses "yyyy-MM"; nil for anything else (a malformed stored id is dropped from the trend).
    init?(id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else { return nil }
        year = y
        month = m
    }
}

/// One point on the trend sparkline: a stored closed month and its score.
struct WellbeingTrendPoint: Equatable {
    let yearMonth: YearMonth
    let score: Int
}

/// The §3.2 sparkline model: the stored closed months, the in-flight ghost score, the delta since the
/// first shown month, and that first month (for the "Up 8 since March." caption).
struct WellbeingTrend: Equatable {
    let closed: [WellbeingTrendPoint]
    let liveScore: Int?
    let deltaSinceFirst: Int
    let firstMonth: YearMonth
}

// MARK: - Stable serialization identifiers

extension WellbeingComponentKey {
    /// Stable JSON key for `componentsJson` (Android parity: `WellbeingComponentKey.name`).
    var serialKey: String {
        switch self {
        case .savings: "SAVINGS"
        case .budget: "BUDGET"
        case .trend: "TREND"
        case .subscriptions: "SUBSCRIPTIONS"
        case .goals: "GOALS"
        }
    }
}

extension WellbeingBand {
    /// Stable persisted name (Android parity: `WellbeingBand.name`), stored in `WellbeingScoreEntity.band`.
    var name: String {
        switch self {
        case .needsWork: "NEEDS_WORK"
        case .gettingThere: "GETTING_THERE"
        case .healthy: "HEALTHY"
        case .thriving: "THRIVING"
        }
    }
}
