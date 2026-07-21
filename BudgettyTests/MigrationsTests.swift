//
//  MigrationsTests.swift
//  BudgettyTests
//
//  Pins the data fix-ups in `Migrations`. The category name IS the stored reference (there is no
//  id), so a rename has to repoint every table that holds one — this is the iOS counterpart of
//  Android's instrumented MigrationTest for `MIGRATION_17_18`.
//

import Foundation
import SwiftData
import Testing
@testable import Budgetty

@MainActor
struct MigrationsTests {
    /// An in-memory store holding every model, so a migration can be run against real rows.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private let old = "Subscriptions & Services"
    private let new = "Subscriptions"

    @Test func repointsEveryTableAndTheBudgetKey() throws {
        let context = try makeContext()
        context.insert(Budgetty.Category(name: old, colorArgb: 0xFFBF9559, icon: "🔁"))
        context.insert(LineItem(name: "Netflix", createdAt: .now, price: 9.99, quantity: 1, category: old))
        context.insert(Recurring(label: "Spotify", amount: 9.99, isIncome: false, category: old))
        context.insert(CategoryRule(name: "netflix", category: old))
        context.insert(Budget(key: Budget.categoryKey(old), amount: 120))

        Migrations.splitSubscriptionsAndServices(context)

        #expect(try context.fetch(FetchDescriptor<Budgetty.Category>()).map(\.name) == [new])
        #expect(try context.fetch(FetchDescriptor<LineItem>()).allSatisfy { $0.category == new })
        #expect(try context.fetch(FetchDescriptor<Recurring>()).allSatisfy { $0.category == new })
        #expect(try context.fetch(FetchDescriptor<CategoryRule>()).allSatisfy { $0.category == new })
        #expect(try context.fetch(FetchDescriptor<Budget>()).map(\.key) == [Budget.categoryKey(new)])
    }

    /// The renamed row keeps its identity — that is the whole reason the split reuses the old slot
    /// in `defs` instead of deleting and re-seeding.
    @Test func renamePreservesTheExistingRow() throws {
        let context = try makeContext()
        context.insert(Budgetty.Category(name: old, colorArgb: 0xFFBF9559, icon: "🔁"))

        Migrations.splitSubscriptionsAndServices(context)

        let category = try #require(try context.fetch(FetchDescriptor<Budgetty.Category>()).first)
        #expect(category.name == new)
        #expect(category.colorArgb == 0xFFBF9559)
        #expect(category.icon == "🔁")
    }

    /// A scan can return "Subscriptions" as soon as the Cloud Function's list is deployed — before
    /// this build ever launches — so both names can already exist. `Category.name` is unique, so the
    /// stale row is dropped rather than colliding (Android's `UPDATE OR REPLACE`).
    @Test func collidingNewCategoryDropsTheStaleRow() throws {
        let context = try makeContext()
        context.insert(Budgetty.Category(name: old, colorArgb: 0xFFBF9559, icon: "🔁"))
        context.insert(Budgetty.Category(name: new, colorArgb: 0xFF123456, icon: "🔁"))
        context.insert(Budget(key: Budget.categoryKey(old), amount: 120))
        context.insert(Budget(key: Budget.categoryKey(new), amount: 80))

        Migrations.splitSubscriptionsAndServices(context)

        let categories = try context.fetch(FetchDescriptor<Budgetty.Category>())
        #expect(categories.map(\.name) == [new])
        #expect(categories.first?.colorArgb == 0xFF123456) // the surviving row is the new one
        #expect(try context.fetch(FetchDescriptor<Budget>()).map(\.amount) == [80])
    }

    /// Idempotent: it matches on the old value, so a second run has nothing left to do.
    @Test func rerunIsANoOp() throws {
        let context = try makeContext()
        context.insert(Budgetty.Category(name: new, colorArgb: 0xFFBF9559, icon: "🔁"))
        context.insert(LineItem(name: "Netflix", createdAt: .now, price: 9.99, quantity: 1, category: new))

        Migrations.splitSubscriptionsAndServices(context)
        Migrations.splitSubscriptionsAndServices(context)

        #expect(try context.fetch(FetchDescriptor<Budgetty.Category>()).map(\.name) == [new])
        #expect(try context.fetch(FetchDescriptor<LineItem>()).count == 1)
    }
}
