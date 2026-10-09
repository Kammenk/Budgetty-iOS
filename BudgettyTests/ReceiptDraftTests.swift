//
//  ReceiptDraftTests.swift
//  BudgettyTests
//
//  The editable draft's money math: subtotal, on-top charges, and the paid `total` — pure computed
//  properties, no ModelContext needed — plus how `persist()` resolves an unpicked category.
//

import Testing
import Foundation
import SwiftData
@testable import Budgetty

struct ReceiptDraftTests {
    private func draft(items: [DraftItem]) -> ReceiptDraft {
        let d = ReceiptDraft()
        d.items = items
        return d
    }

    @Test func lineTotalIsPriceTimesQuantity() {
        let item = DraftItem(name: "Bananas", quantity: 2, price: Decimal(string: "1.05")!, category: "Fruits & Vegetables")
        #expect(item.lineTotal == Decimal(string: "2.10")!)
    }

    @Test func subtotalSumsLineTotals() {
        let d = draft(items: [
            DraftItem(name: "A", quantity: 1, price: Decimal(string: "1.29")!, category: "Bakery"),
            DraftItem(name: "B", quantity: 2, price: Decimal(string: "1.05")!, category: "Dairy"),
        ])
        #expect(d.subtotal == Decimal(string: "3.39")!)
    }

    @Test func totalSubtractsDiscount() {
        let d = draft(items: [DraftItem(name: "A", quantity: 1, price: Decimal(string: "10.00")!, category: "Bakery")])
        d.discount = Decimal(string: "3.20")!
        #expect(d.total == Decimal(string: "6.80")!)
    }

    @Test func taxCountsOnlyWhenOnTop() {
        let d = draft(items: [DraftItem(name: "A", quantity: 1, price: Decimal(string: "10.00")!, category: "Bakery")])
        d.tax = Decimal(string: "2.00")!

        d.taxOnTop = false
        #expect(d.additiveCharges == .zero)
        #expect(d.total == Decimal(string: "10.00")!)

        d.taxOnTop = true
        #expect(d.additiveCharges == Decimal(string: "2.00")!)
        #expect(d.total == Decimal(string: "12.00")!)
    }

    @Test func totalCombinesDiscountTaxAndExtraCharges() {
        let d = draft(items: [DraftItem(name: "A", quantity: 1, price: Decimal(string: "20.00")!, category: "Bakery")])
        d.discount = Decimal(string: "5.00")!
        d.tax = Decimal(string: "2.00")!
        d.taxOnTop = true
        d.extraCharges = Decimal(string: "1.50")!
        // 20 − 5 + (2 + 1.50)
        #expect(d.total == Decimal(string: "18.50")!)
    }

    @Test func addAndRemoveItem() {
        let d = ReceiptDraft()
        #expect(d.items.isEmpty)
        d.addItem()
        #expect(d.items.count == 1)
        // A fresh row pre-picks nothing — the card prompts "Select category" (Android parity).
        #expect(d.items[0].category.isEmpty)
        d.remove(d.items[0])
        #expect(d.items.isEmpty)
    }

    /// An unpicked category is never blocking: it saves as the default, exactly like Android's
    /// `finalizeUpload` (`category.ifBlank { Categories.DEFAULT }`); a picked one is kept as-is.
    @MainActor
    @Test func unpickedCategorySavesAsTheDefault() throws {
        let container = try ModelContainer(for: Schema(UserStore.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let d = draft(items: [
            DraftItem(name: "Taxi", quantity: 1, price: 12, category: ""),
            DraftItem(name: "Bread", quantity: 1, price: 2, category: "Bakery"),
        ])
        d.persist(into: ctx, isManual: true)
        let items = try ctx.fetch(FetchDescriptor<LineItem>(sortBy: [SortDescriptor(\.name)]))
        #expect(items.map(\.category) == ["Bakery", Categories.defaultName])
    }
}
