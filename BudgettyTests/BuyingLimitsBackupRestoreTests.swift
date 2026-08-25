//
//  BuyingLimitsBackupRestoreTests.swift
//  BudgettyTests
//
//  Guards the buying-limits half of backup restore — the "restore silently dropped my buying limits"
//  gap, and (crucially) that a backup made *before* this feature still imports. Runs the export → wipe
//  → import round-trip against a real in-memory store and asserts every field survives, including the
//  timeframe enum and the normalized (Cyrillic-safe) keywords. Port of Android's
//  BuyingLimitsBackupRestoreTest.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct BuyingLimitsBackupRestoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func exportThenWipeThenImportRestoresEveryLimitAndField() throws {
        let ctx = try makeContext()
        ctx.insert(BuyingLimit(emoji: "🥤", label: "Fizzy drinks",
                               keywords: BuyingLimit.normalizedKeywords(["Coke", "cola"]),
                               timeframe: .monthly, count: 3,
                               createdAt: Date(timeIntervalSince1970: 1)))
        ctx.insert(BuyingLimit(emoji: "", label: "",
                               keywords: BuyingLimit.normalizedKeywords(["кока"]),
                               timeframe: .weekly, count: 1,
                               createdAt: Date(timeIntervalSince1970: 2)))
        try ctx.save()

        // Export, then wipe and restore from the JSON — exactly what Account → Export / Import does.
        let data = try BackupService.export(from: ctx)
        for l in try ctx.fetch(FetchDescriptor<BuyingLimit>()) { ctx.delete(l) }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<BuyingLimit>()).isEmpty)

        let file = try BackupService.decode(data)
        try BackupService.restore(file, into: ctx, mode: .merge)

        let limits = try ctx.fetch(FetchDescriptor<BuyingLimit>())
        #expect(limits.count == 2)

        let fizzy = try #require(limits.first { $0.label == "Fizzy drinks" })
        #expect(fizzy.emoji == "🥤")
        #expect(fizzy.timeframe == .monthly)
        #expect(fizzy.count == 3)
        // Keywords survive as the normalized, de-duplicated list ("Coke" -> "coke").
        #expect(fizzy.keywords == ["coke", "cola"])

        let cyrillic = try #require(limits.first { $0.label.isEmpty })
        #expect(cyrillic.emoji.isEmpty)
        #expect(cyrillic.timeframe == .weekly)
        #expect(cyrillic.count == 1)
        #expect(cyrillic.keywords == ["кока"])
    }

    @Test func olderBackupWithoutBuyingLimitsImportsCleanly() throws {
        let ctx = try makeContext()
        // A realistic pre-buying-limits backup: a full BackupFile JSON with the field stripped out
        // (Swift's synthesized Decodable throws on a missing non-optional key, so this proves the
        // field is optional and its absence tolerated).
        let full = try BackupService.export(from: ctx)
        var obj = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        obj.removeValue(forKey: "buyingLimits")
        let legacy = try JSONSerialization.data(withJSONObject: obj)

        let file = try BackupService.decode(legacy)
        #expect((file.buyingLimits ?? []).isEmpty)
        try BackupService.restore(file, into: ctx, mode: .merge)
        #expect(try ctx.fetch(FetchDescriptor<BuyingLimit>()).isEmpty)
    }
}
