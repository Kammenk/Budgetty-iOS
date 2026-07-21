//
//  CategoryRuleTests.swift
//  BudgettyTests
//
//  The learned-rule match key. Android had a bug where Cyrillic keys didn't fold correctly, so the
//  Unicode-aware lowercasing is the important thing to pin down here.
//

import Testing
@testable import Budgetty

struct CategoryRuleTests {
    @Test func keyTrimsAndLowercasesAscii() {
        #expect(CategoryRule.key("  Milk  ") == "milk")
        #expect(CategoryRule.key("MILK") == "milk")
        #expect(CategoryRule.key("Chicken Breast") == "chicken breast")
    }

    @Test func keyFoldsCyrillic() {
        // The Android bug class: a Cyrillic name must lower-case so "remember" matches next time.
        #expect(CategoryRule.key("Мляко") == "мляко")
        #expect(CategoryRule.key("  ХЛЯБ ") == "хляб")
    }

    @Test func keyIsIdempotent() {
        let once = CategoryRule.key("  Мляко Прясно ")
        #expect(CategoryRule.key(once) == once)
    }

    @Test func keyStripsNewlines() {
        #expect(CategoryRule.key("Milk\n") == "milk")
    }
}
