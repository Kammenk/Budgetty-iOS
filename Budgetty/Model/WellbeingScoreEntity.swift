//
//  WellbeingScoreEntity.swift
//  Budgetty
//
//  A finalized Wellbeing score for one CLOSED pay-cycle month (§3.1) — the only new persistence in the
//  retention spec, and the Swift port of Android's Room `WellbeingScoreEntity` (+ its DAO / repository,
//  folded into `WellbeingScoreStore` below). `WellbeingScan.run` scores the just-closed month for the
//  trend and records a snapshot here; the in-flight month is never stored, so history stays a fixed,
//  non-revisionist record. Recomputing an old month against today's budgets/goals would silently
//  rewrite the past and make the future trend line lie, so the snapshot — not a recompute — is the
//  source of truth.
//
//  `periodId` is the pay-cycle month id "yyyy-MM" (see `PayCycle`) and is `@Attribute(.unique)`, so
//  re-scoring the same month upserts its row rather than duplicating (Android's `@Upsert`, PK =
//  periodId). `componentsJson` holds the per-component sub-scores (see `WellbeingHistory.encodeComponents`)
//  for the future breakdown-over-time view; the saved total is never re-derived from it — the row is
//  the snapshot. `computedAt` is a `Date` (iOS-idiomatic; Android stores epoch millis) and is audit-only,
//  never part of the score.
//

import Foundation
import SwiftData

@Model
final class WellbeingScoreEntity {
    /// Pay-cycle month id "yyyy-MM"; unique, so a re-scored month replaces its row (no duplicates).
    @Attribute(.unique) var periodId: String
    var score: Int
    /// `WellbeingBand` stable name at snapshot time (e.g. "HEALTHY"); see `WellbeingBand.name`.
    var band: String
    /// Per-component sub-scores as stable JSON (componentKey -> sub-score, null when not counted).
    var componentsJson: String
    /// When this snapshot was written — audit only, never part of the score.
    var computedAt: Date

    init(periodId: String, score: Int, band: String, componentsJson: String, computedAt: Date) {
        self.periodId = periodId
        self.score = score
        self.band = band
        self.componentsJson = componentsJson
        self.computedAt = computedAt
    }
}

/// The Wellbeing score history's persistence surface — the Swift analog of Android's
/// `WellbeingScoreDao` + `WellbeingScoreRepository`. iOS has no DAO/repository layer (SwiftData is read
/// via `@Query` / `ModelContext`), so the two behaviours §3.1 depends on live here: an idempotent
/// per-`periodId` `upsert`, and the closed-month-only `record` the Wellbeing surfaces call. Every write
/// routes through here.
@MainActor
enum WellbeingScoreStore {
    /// Insert or update keyed by `periodId` (Android's `@Upsert`). Idempotent: re-scoring the same
    /// closed month replaces its row in place, so a month can never appear twice in the trend. The
    /// `snapshot` may be a detached entity built by `WellbeingHistory.closedSnapshot`; on a clash its
    /// fields are copied onto the existing row (the detached one is discarded).
    static func upsert(_ snapshot: WellbeingScoreEntity, into context: ModelContext) {
        let pid = snapshot.periodId
        let existing = (try? context.fetch(FetchDescriptor<WellbeingScoreEntity>(
            predicate: #Predicate { $0.periodId == pid })))?.first
        if let existing {
            existing.score = snapshot.score
            existing.band = snapshot.band
            existing.componentsJson = snapshot.componentsJson
            existing.computedAt = snapshot.computedAt
        } else {
            context.insert(snapshot)
        }
        try? context.save()
    }

    /// Records the just-closed cycle's snapshot (§3.1): CLOSED month ONLY (never the in-flight month),
    /// idempotent on `periodId`, no backfill of older months. A no-op when the closed month can't be
    /// scored yet (`closedScore.score == nil`) — no junk row is written. Called from the Wellbeing
    /// surfaces where the previous cycle is already scored for the trend (mirrors Android's
    /// `WellbeingProvider` upserting the just-closed month as a side effect of scoring it).
    static func record(closedScore: WellbeingScore, closedPeriodId: String,
                       into context: ModelContext, computedAt: Date = .now) {
        guard let snapshot = WellbeingHistory.closedSnapshot(
            closedPeriodId: closedPeriodId, closedScore: closedScore, computedAt: computedAt) else { return }
        upsert(snapshot, into: context)
    }
}
