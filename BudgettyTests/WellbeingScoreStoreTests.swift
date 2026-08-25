//
//  WellbeingScoreStoreTests.swift
//  BudgettyTests
//
//  The store/persistence half of §3.1 — the Swift analog of Android's `WellbeingScoreDaoTest`, run
//  against a real in-memory SwiftData store (mirrors `BuyingLimitsBackupRestoreTests`). Pins the two
//  behaviours the stored history depends on: the upsert is idempotent per `periodId` (a re-scored month
//  never duplicates), and a backup restore IGNOREs a periodId clash so it keeps the on-device snapshot.
//  Also covers `WellbeingScoreStore.record`'s closed-month guard and the export→import round-trip.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct WellbeingScoreStoreTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func entity(_ periodId: String, _ value: Int, band: String = "HEALTHY") -> WellbeingScoreEntity {
        WellbeingScoreEntity(periodId: periodId, score: value, band: band,
                             componentsJson: "{\"SAVINGS\":\(value)}",
                             computedAt: Date(timeIntervalSince1970: 1_700_000_000))
    }

    // ── upsert idempotence ────────────────────────────────────────────────────────

    @Test func upsertOnTheSamePeriodIdReplacesRatherThanDuplicating() throws {
        let ctx = try makeContext()
        WellbeingScoreStore.upsert(entity("2026-02", 60, band: "GETTING_THERE"), into: ctx)
        WellbeingScoreStore.upsert(entity("2026-02", 74, band: "HEALTHY"), into: ctx)

        // Unique periodId, so re-scoring the just-closed month keeps exactly one row with the latest
        // values — the non-revisionist, no-duplicate guarantee the trend line relies on.
        let all = try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>())
        #expect(all.count == 1)
        #expect(all.first?.score == 74)
        #expect(all.first?.band == "HEALTHY")
    }

    // ── record: closed-month guard ────────────────────────────────────────────────

    @Test func recordWritesTheScoredClosedMonthAndNoOpsWhenUnscored() throws {
        let ctx = try makeContext()
        // Unscored (nil total) → no row is written.
        WellbeingScoreStore.record(
            closedScore: WellbeingScore(score: nil, band: nil, components: [], trendDeltaVsPrevious: nil),
            closedPeriodId: "2026-02", into: ctx)
        #expect(try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()).isEmpty)

        // Scored → exactly one row for that periodId; recording again is idempotent.
        let scored = WellbeingScore(score: 72, band: .healthy, components: [], trendDeltaVsPrevious: nil)
        WellbeingScoreStore.record(closedScore: scored, closedPeriodId: "2026-02", into: ctx)
        WellbeingScoreStore.record(closedScore: scored, closedPeriodId: "2026-02", into: ctx)
        let all = try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>())
        #expect(all.count == 1)
        #expect(all.first?.periodId == "2026-02")
        #expect(all.first?.score == 72)
        #expect(all.first?.band == "HEALTHY")
    }

    // ── backup restore: IGNORE a clash, keep the on-device row ─────────────────────

    @Test func restoreIgnoresAPeriodIdClashSoItKeepsTheOnDeviceSnapshot() throws {
        let ctx = try makeContext()
        WellbeingScoreStore.upsert(entity("2026-02", 74), into: ctx)

        // A backup carrying an older copy of the same month must not overwrite the finalized on-device row.
        let file = BackupFile(wellbeingScores: [
            WellbeingScoreDTO(entity("2026-02", 10)),
            WellbeingScoreDTO(entity("2026-01", 55)),
        ])
        try BackupService.restore(file, into: ctx, mode: .merge)

        let byPeriod = Dictionary(uniqueKeysWithValues:
            try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()).map { ($0.periodId, $0.score) })
        #expect(byPeriod["2026-02"] == 74) // on-device snapshot kept
        #expect(byPeriod["2026-01"] == 55) // the new month added
    }

    // ── export → wipe → import round-trip (replace) ───────────────────────────────

    @Test func exportThenWipeThenImportRestoresEveryFieldOnReplace() throws {
        let ctx = try makeContext()
        WellbeingScoreStore.upsert(entity("2026-01", 55, band: "GETTING_THERE"), into: ctx)
        WellbeingScoreStore.upsert(entity("2026-02", 74, band: "HEALTHY"), into: ctx)

        let data = try BackupService.export(from: ctx)
        for s in try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()) { ctx.delete(s) }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()).isEmpty)

        let file = try BackupService.decode(data)
        try BackupService.restore(file, into: ctx, mode: .replace)

        let all = try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()).sorted { $0.periodId < $1.periodId }
        #expect(all.map(\.periodId) == ["2026-01", "2026-02"])
        let feb = try #require(all.first { $0.periodId == "2026-02" })
        #expect(feb.score == 74)
        #expect(feb.band == "HEALTHY")
        #expect(feb.componentsJson == "{\"SAVINGS\":74}")
    }

    // ── forward-compat: a pre-history backup imports cleanly ──────────────────────

    @Test func olderBackupWithoutHistoryImportsCleanly() throws {
        let ctx = try makeContext()
        let full = try BackupService.export(from: ctx)
        var obj = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        obj.removeValue(forKey: "wellbeingScores")
        let legacy = try JSONSerialization.data(withJSONObject: obj)

        let file = try BackupService.decode(legacy)
        #expect((file.wellbeingScores ?? []).isEmpty)
        try BackupService.restore(file, into: ctx, mode: .merge)
        #expect(try ctx.fetch(FetchDescriptor<WellbeingScoreEntity>()).isEmpty)
    }
}
