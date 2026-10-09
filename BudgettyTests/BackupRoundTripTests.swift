//
//  BackupRoundTripTests.swift
//  BudgettyTests
//
//  Guards the fields a backup used to drop and the state a `.replace` restore used to leave behind
//  (device-test bugs 4 + 8, 2026-10-09): Autopay and the mark-as-paid stamp on recurring bills, the
//  needs/wants bucket on custom categories and the overrides on built-ins, the tag catalog, ignored
//  subscriptions (now backed up, upserted by merchant), and that a replace wipes the budget carry-over
//  and the old ignored-subscription list. Each runs the real export → decode → restore path against an
//  in-memory store, plus a "pre-change backup still decodes" check for every new optional field.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

@MainActor
struct BackupRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    /// Restores into a throwaway defaults suite so a `.replace` never touches `.standard`.
    private func restore(_ file: BackupFile, into ctx: ModelContext, _ mode: BackupService.ImportMode) throws {
        let name = "BackupRoundTripTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try BackupService.restore(file, into: ctx, mode: mode, defaults: defaults)
    }

    /// Whole seconds — the backup encodes dates as ISO-8601, which drops sub-second precision.
    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    /// Strips `key` from every object in the top-level `collection` array, to fake an older backup.
    private func stripping(_ key: String, from collection: String, in data: Data) throws -> Data {
        var obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(obj[collection] as? [[String: Any]])
        obj[collection] = rows.map { var r = $0; r.removeValue(forKey: key); return r }
        return try JSONSerialization.data(withJSONObject: obj)
    }

    // MARK: - Bug 4: Autopay + paid state

    @Test func autopayAndPaidStampSurviveExportAndReplaceRestore() throws {
        let ctx = try makeContext()
        let loan = Recurring(label: "Car loan", amount: Decimal(string: "679.58")!, isIncome: false,
                             category: "Transport", cadence: .monthly, dueDay: 5, createdAt: at(1_780_000_000))
        loan.autoPay = true
        let rent = Recurring(label: "Rent", amount: 800, isIncome: false, cadence: .monthly, dueDay: 1,
                             createdAt: at(1_780_000_100))
        rent.lastPosted = at(1_790_000_000)
        ctx.insert(loan); ctx.insert(rent)
        try ctx.save()

        let file = try BackupService.decode(try BackupService.export(from: ctx))
        try restore(file, into: ctx, .replace)

        let rows = try ctx.fetch(FetchDescriptor<Recurring>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(rows.count == 2)
        #expect(rows[0].label == "Car loan" && rows[0].autoPay)
        #expect(rows[0].lastPosted == nil)
        #expect(rows[1].label == "Rent" && !rows[1].autoPay)
        #expect(rows[1].lastPosted == at(1_790_000_000))
    }

    @Test func autopayIsDroppedForAnIneligibleCadenceOnRestore() throws {
        let ctx = try makeContext()
        var file = BackupFile()
        file.recurring = [
            RecurringDTO(label: "Insurance", amount: 300, isIncome: false, category: "", cadenceRaw: "YEARLY",
                         dueDay: 1, createdAt: at(1_780_000_000), active: true, autoPay: true),
            RecurringDTO(label: "Salary", amount: 3200, isIncome: true, category: "", cadenceRaw: "MONTHLY",
                         dueDay: 1, createdAt: at(1_780_000_001), active: true, autoPay: true),
        ]
        try restore(file, into: ctx, .merge)
        #expect(try ctx.fetch(FetchDescriptor<Recurring>()).allSatisfy { !$0.autoPay })
    }

    @Test func preAutopayBackupStillDecodesWithAutopayOff() throws {
        let ctx = try makeContext()
        let bill = Recurring(label: "Gym", amount: 30, isIncome: false, cadence: .monthly, createdAt: at(1_780_000_000))
        bill.autoPay = true
        ctx.insert(bill)
        try ctx.save()
        var legacy = try stripping("autoPay", from: "recurring", in: try BackupService.export(from: ctx))
        legacy = try stripping("lastPosted", from: "recurring", in: legacy)
        legacy = try stripping("nextDue", from: "recurring", in: legacy)

        let file = try BackupService.decode(legacy)
        #expect(file.recurring.first?.autoPay == nil)
        try restore(file, into: ctx, .replace)
        let row = try #require(try ctx.fetch(FetchDescriptor<Recurring>()).first)
        #expect(!row.autoPay)
    }

    // MARK: - Category bucket + built-in overrides

    @Test func customBucketAndBuiltInOverridesRoundTrip() throws {
        let ctx = try makeContext()
        // Built-ins as the seed would leave them, two of them customised by the user.
        let groceries = Category(name: "Groceries", colorArgb: 1)
        groceries.bucket = CategoryBucket.want.rawValue
        let coffee = Category(name: "Coffee", colorArgb: 2)
        coffee.parent = "Groceries"
        let rent = Category(name: "Rent", colorArgb: 3)
        ctx.insert(groceries); ctx.insert(coffee); ctx.insert(rent)
        ctx.insert(Category(name: "Loan", colorArgb: 4, icon: "🏦", isCustom: true, createdAt: at(1_780_000_000),
                            parent: "Other", bucket: CategoryBucket.need.rawValue))
        try ctx.save()

        let file = try BackupService.decode(try BackupService.export(from: ctx))
        #expect(file.categories.map(\.name) == ["Loan"])
        #expect(Set(file.categoryOverrides?.map(\.name) ?? []) == ["Groceries", "Coffee"])

        // The device drifted after the backup: Rent re-bucketed, Groceries reset.
        rent.bucket = CategoryBucket.savings.rawValue
        groceries.bucket = nil
        try ctx.save()
        try restore(file, into: ctx, .replace)

        let byName = Dictionary(uniqueKeysWithValues: try ctx.fetch(FetchDescriptor<Budgetty.Category>()).map { ($0.name, $0) })
        #expect(byName["Loan"]?.bucket == "NEED")
        #expect(byName["Loan"]?.parent == "Other")
        #expect(byName["Groceries"]?.bucket == "WANT")
        #expect(byName["Coffee"]?.parent == "Groceries")
        #expect(byName["Rent"]?.bucket == nil)             // replace reproduces the backup exactly
        #expect(byName.values.filter(\.isCustom).count == 1)
    }

    @Test func mergeNeverOverridesTheDevicesOwnBuiltInChoices() throws {
        let ctx = try makeContext()
        let groceries = Category(name: "Groceries", colorArgb: 1)
        groceries.bucket = CategoryBucket.need.rawValue
        let coffee = Category(name: "Coffee", colorArgb: 2)
        ctx.insert(groceries); ctx.insert(coffee)
        try ctx.save()

        var file = BackupFile()
        file.categoryOverrides = [
            CategoryOverrideDTO(name: "Groceries", parent: nil, bucket: "WANT"),
            CategoryOverrideDTO(name: "Coffee", parent: nil, bucket: "WANT"),
            CategoryOverrideDTO(name: "Unknown", parent: "Other", bucket: "WANT"),
        ]
        try restore(file, into: ctx, .merge)

        #expect(groceries.bucket == "NEED")                 // device choice kept
        #expect(coffee.bucket == "WANT")                    // unset → filled
        #expect(try ctx.fetch(FetchDescriptor<Budgetty.Category>()).count == 2)   // never creates a built-in
    }

    // MARK: - Tag catalog

    @Test func unusedTagAndOriginalCreatedAtSurviveARestore() throws {
        let ctx = try makeContext()
        ctx.insert(Budgetty.Tag(name: "lisbon-2026", createdAt: at(1_780_000_000)))
        try ctx.save()

        let file = try BackupService.decode(try BackupService.export(from: ctx))
        try restore(file, into: ctx, .replace)

        let tags = try ctx.fetch(FetchDescriptor<Budgetty.Tag>())
        #expect(tags.map(\.name) == ["lisbon-2026"])
        #expect(tags.first?.createdAt == at(1_780_000_000))
    }

    // MARK: - Bug 8: replace clears rollover + ignored subscriptions; ignored subs are backed up

    @Test func replaceClearsBudgetCarryOverAndOldIgnoredSubscriptions() throws {
        let ctx = try makeContext()
        ctx.insert(BudgetRollover(key: "MONTHLY", carried: 1200, periodKey: "2026-10"))
        ctx.insert(IgnoredSubscription(merchant: "old gym", ignoredAt: at(1_780_000_000)))
        try ctx.save()

        var file = BackupFile()
        file.budgets = [BudgetDTO(key: "MONTHLY", amount: 650)]
        try restore(file, into: ctx, .replace)

        #expect(try ctx.fetch(FetchDescriptor<BudgetRollover>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<IgnoredSubscription>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Budget>()).map(\.amount) == [650])
    }

    @Test func mergeKeepsTheCarryOver() throws {
        let ctx = try makeContext()
        ctx.insert(BudgetRollover(key: "MONTHLY", carried: 1200, periodKey: "2026-10"))
        try ctx.save()
        try restore(BackupFile(), into: ctx, .merge)
        #expect(try ctx.fetch(FetchDescriptor<BudgetRollover>()).count == 1)
    }

    @Test func ignoredSubscriptionsRoundTripThroughReplace() throws {
        let ctx = try makeContext()
        ctx.insert(IgnoredSubscription(merchant: "netflix", ignoredAt: at(1_780_000_000)))
        ctx.insert(IgnoredSubscription(merchant: "spotify", ignoredAt: at(1_780_000_500)))
        try ctx.save()

        let data = try BackupService.export(from: ctx)
        // On-disk shape matches Android's: `ignoredSubscriptions: [{merchant, ignoredAt}]`.
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let rows = try #require(obj["ignoredSubscriptions"] as? [[String: Any]])
        #expect(Set(rows.compactMap { $0["merchant"] as? String }) == ["netflix", "spotify"])
        #expect(obj["app"] as? String == "Budgetty iOS")   // Android detects iOS files by this

        try restore(try BackupService.decode(data), into: ctx, .replace)
        let restored = try ctx.fetch(FetchDescriptor<IgnoredSubscription>(sortBy: [SortDescriptor(\.merchant)]))
        #expect(restored.map(\.merchant) == ["netflix", "spotify"])
        #expect(restored.first?.ignoredAt == at(1_780_000_000))
    }

    @Test func mergingIgnoredSubscriptionsNeverDuplicates() throws {
        let ctx = try makeContext()
        ctx.insert(IgnoredSubscription(merchant: "netflix", ignoredAt: at(1_780_000_000)))
        try ctx.save()

        var file = BackupFile()
        file.ignoredSubscriptions = [
            IgnoredSubscriptionDTO(merchant: "netflix", ignoredAt: at(1_790_000_000)),
            IgnoredSubscriptionDTO(merchant: "disney", ignoredAt: at(1_790_000_000)),
        ]
        try restore(file, into: ctx, .merge)
        try restore(file, into: ctx, .merge)   // twice: still no duplicates

        let rows = try ctx.fetch(FetchDescriptor<IgnoredSubscription>(sortBy: [SortDescriptor(\.merchant)]))
        #expect(rows.map(\.merchant) == ["disney", "netflix"])
    }

    @Test func backupWithoutIgnoredSubscriptionsKeyStillDecodes() throws {
        let ctx = try makeContext()
        let full = try BackupService.export(from: ctx)
        var obj = try #require(try JSONSerialization.jsonObject(with: full) as? [String: Any])
        for key in ["ignoredSubscriptions", "tags", "categoryOverrides"] { obj.removeValue(forKey: key) }
        let file = try BackupService.decode(try JSONSerialization.data(withJSONObject: obj))
        #expect(file.ignoredSubscriptions == nil)
        #expect(file.categoryOverrides == nil)
    }
}
