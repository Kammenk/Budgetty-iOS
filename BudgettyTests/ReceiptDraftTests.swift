//
//  ReceiptDraftTests.swift
//  BudgettyTests
//
//  The editable draft's money math: subtotal, on-top charges, and the paid `total`. Pure computed
//  properties — no ModelContext needed (persist() is the only part that touches SwiftData).
//

import Testing
import Foundation
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
        #expect(d.items[0].category == Categories.defaultName)
        d.remove(d.items[0])
        #expect(d.items.isEmpty)
    }
}
