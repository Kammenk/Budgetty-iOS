//
//  CategoriesTests.swift
//  BudgettyTests
//
//  The spending taxonomy. Ported 1:1 from Android's Categories.kt, so the structural invariants and
//  the pinned group colors double as a cross-platform parity check (the pie/tiles must render the
//  same hues on both platforms).
//

import Testing
@testable import Budgetty

struct CategoriesTests {
    @Test func canonicalCountAndGroups() {
        // 50 selectable categories (7 groups + subs + Other) across 8 top-level groups.
        #expect(Categories.predefined.count == 50)
        #expect(Categories.groups.count == 8)
    }

    @Test func namesAreUnique() {
        let names = Categories.predefined.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func everySubcategoryHasARealGroupParent() {
        let groupNames = Set(Categories.groups.map(\.name))
        for cat in Categories.predefined where cat.parent != nil {
            #expect(groupNames.contains(cat.parent!), "\(cat.name) → unknown parent \(cat.parent!)")
        }
    }

    @Test func groupOfRollsSubUpToParent() {
        #expect(Categories.groupOf("Bakery") == "Groceries")
        #expect(Categories.groupOf("Fuel") == "Transportation")
        // Delivery deliberately parents to the "Other" group.
        #expect(Categories.groupOf("Delivery") == "Other")
    }

    @Test func groupOfIsCaseInsensitive() {
        #expect(Categories.groupOf("bakery") == "Groceries")
        #expect(Categories.groupOf("BAKERY") == "Groceries")
    }

    @Test func groupOfReturnsGroupsAndUnknownsUnchanged() {
        #expect(Categories.groupOf("Groceries") == "Groceries")   // a group rolls up to itself
        #expect(Categories.groupOf("My Custom Cat") == "My Custom Cat") // unknown/custom unchanged
    }

    @Test func isPredefinedRecognisesBuiltins() {
        #expect(Categories.isPredefined("Dairy"))
        #expect(Categories.isPredefined("dairy"))
        #expect(!Categories.isPredefined("Totally Made Up"))
    }

    @Test func pinnedGroupColorsMatchDesign() {
        // These exact ARGB values are the parity anchor with Android's Insights pie.
        #expect(Categories.color(for: "Groceries") == 0xFF4FA85A)
        #expect(Categories.color(for: "Household & Personal") == 0xFFC77DB0)
        #expect(Categories.color(for: "Health & Wellness") == 0xFF5BB6A6)
        #expect(Categories.color(for: "Dining & Entertainment") == 0xFFE0795B)
        #expect(Categories.color(for: "Shopping & Lifestyle") == 0xFFAE72CC)
        #expect(Categories.color(for: "Transportation") == 0xFFD08A4A)
        #expect(Categories.color(for: "Services & Subscriptions") == 0xFF588AC7)
        #expect(Categories.color(for: "Other") == 0xFF9A93A6)
    }

    @Test func everyColorIsOpaque() {
        for cat in Categories.predefined {
            #expect((cat.colorArgb >> 24) & 0xFF == 0xFF, "\(cat.name) is not fully opaque")
        }
    }

    @Test func emojiFallsBackForUnknown() {
        #expect(Categories.emoji(for: "Bakery") == "🥖")
        #expect(Categories.emoji(for: "Totally Made Up") == "🧾")
    }

    @Test func displayNameFallsBackToIdentityForCustom() {
        // A name with no localization key returns unchanged (custom categories keep their given name).
        #expect(Categories.displayName("My Custom Cat") == "My Custom Cat")
    }
}
