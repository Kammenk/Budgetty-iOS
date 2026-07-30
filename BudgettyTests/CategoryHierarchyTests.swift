//
//  CategoryHierarchyTests.swift
//  BudgettyTests
//
//  Sub-categories (Category & Insights v2): the DB-aware group resolution in `Categories` and the
//  reference cascades in `CategoryOps`. `Categories` keeps a process-global override cache, so this
//  suite is `.serialized` and resets it after each test; the overrides it sets use only *custom*
//  names, never a predefined one, so it can't disturb the parallel `CategoriesTests`.
//

import Foundation
import SwiftData
import Testing
@testable import Budgetty

@MainActor
@Suite(.serialized)
struct CategoryHierarchyTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(UserStore.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    // MARK: - groupOf / parentOf / childNames with overrides

    @Test func customChildFoldsIntoItsParent() {
        defer { Categories.setStored([]) }
        Categories.setStored([
            Budgetty.Category(name: "Coffee Runs", colorArgb: 0xFFC8893A, icon: "☕",
                              isCustom: true, parent: "Dining & Entertainment"),
        ])
        #expect(Categories.parentOf("Coffee Runs") == "Dining & Entertainment")
        #expect(Categories.groupOf("Coffee Runs") == "Dining & Entertainment")
        #expect(Categories.childNames(of: "Dining & Entertainment").contains("Coffee Runs"))
    }

    @Test func topLevelCustomIsItsOwnGroup() {
        defer { Categories.setStored([]) }
        Categories.setStored([
            Budgetty.Category(name: "Gadgets", colorArgb: 0xFF4AA3C7, icon: "🎧", isCustom: true, parent: nil),
        ])
        #expect(Categories.parentOf("Gadgets") == nil)
        #expect(Categories.groupOf("Gadgets") == "Gadgets")
    }

    @Test func customColourAndEmojiResolveFromStore() {
        defer { Categories.setStored([]) }
        Categories.setStored([
            Budgetty.Category(name: "Gadgets", colorArgb: 0xFF123456, icon: "🎧", isCustom: true),
        ])
        #expect(Categories.color(for: "Gadgets") == 0xFF123456)
        #expect(Categories.emoji(for: "Gadgets") == "🎧")
    }

    // MARK: - CategoryOps cascades (isolated context; assert on the DB rows)

    @Test func renameCascadesToReferencesAndChildren() throws {
        defer { Categories.setStored([]) }
        let ctx = try makeContext()
        ctx.insert(Budgetty.Category(name: "Food", colorArgb: 0, icon: "🍎", isCustom: true))
        ctx.insert(Budgetty.Category(name: "Snacks", colorArgb: 0, icon: "🍫", isCustom: true, parent: "Food"))
        ctx.insert(LineItem(name: "Apple", createdAt: .now, price: 1, quantity: 1, category: "Food"))
        ctx.insert(Budget(key: Budget.categoryKey("Food"), amount: 50))
        try ctx.save()

        let food = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Food" })).first)
        CategoryOps.saveCustom(ctx, editing: food, name: "Meals", emoji: "🍎", colorArgb: 0, parent: nil)

        #expect(try ctx.fetch(FetchDescriptor<LineItem>()).allSatisfy { $0.category == "Meals" })
        let snacks = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Snacks" })).first)
        #expect(snacks.parent == "Meals")   // child follows the rename
        #expect(try ctx.fetch(FetchDescriptor<Budget>()).map(\.key) == [Budget.categoryKey("Meals")])
    }

    @Test func deletePromotesChildrenAndFallsBackToOther() throws {
        defer { Categories.setStored([]) }
        let ctx = try makeContext()
        ctx.insert(Budgetty.Category(name: "Food", colorArgb: 0, icon: "🍎", isCustom: true))
        ctx.insert(Budgetty.Category(name: "Snacks", colorArgb: 0, icon: "🍫", isCustom: true, parent: "Food"))
        ctx.insert(LineItem(name: "Apple", createdAt: .now, price: 1, quantity: 1, category: "Food"))
        ctx.insert(Budget(key: Budget.categoryKey("Food"), amount: 50))
        try ctx.save()

        let food = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Food" })).first)
        CategoryOps.deleteCustom(ctx, food)

        #expect(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Food" })).isEmpty)
        let snacks = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Snacks" })).first)
        #expect(snacks.parent == nil)   // child promoted to top-level
        #expect(try ctx.fetch(FetchDescriptor<LineItem>()).allSatisfy { $0.category == Categories.other })
        #expect(try ctx.fetch(FetchDescriptor<Budget>()).isEmpty)   // its category budget removed
    }

    @Test func nestingReleasesOwnChildren() throws {
        defer { Categories.setStored([]) }
        let ctx = try makeContext()
        ctx.insert(Budgetty.Category(name: "Food", colorArgb: 0, icon: "🍎", isCustom: true))
        ctx.insert(Budgetty.Category(name: "Snacks", colorArgb: 0, icon: "🍫", isCustom: true, parent: "Food"))
        try ctx.save()

        // Nest "Food" under a group → its own child "Snacks" is released back to top-level.
        CategoryOps.setParent(ctx, name: "Food", to: "Groceries")

        let food = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Food" })).first)
        let snacks = try #require(try ctx.fetch(FetchDescriptor<Budgetty.Category>(
            predicate: #Predicate { $0.name == "Snacks" })).first)
        #expect(food.parent == "Groceries")
        #expect(snacks.parent == nil)
    }
}
