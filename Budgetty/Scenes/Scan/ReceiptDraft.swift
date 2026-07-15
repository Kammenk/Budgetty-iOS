//
//  ReceiptDraft.swift
//  Budgetty
//
//  The editable in-memory receipt shown on the Review screen before it's saved. Seeded from an
//  `ExtractionResult` (scan) or empty (manual). Persisting converts it to a `Receipt` + `LineItem`s.
//

import Foundation
import SwiftData

@Observable
final class DraftItem: Identifiable {
    let id = UUID()
    var name: String
    var quantity: Int
    var price: Decimal
    var category: String

    init(name: String, quantity: Int, price: Decimal, category: String) {
        self.name = name; self.quantity = quantity; self.price = price; self.category = category
    }

    var lineTotal: Decimal { price * Decimal(quantity) }
}

@Observable
final class ReceiptDraft: Identifiable {
    let id = UUID()
    var store: String
    var date: Date
    var discount: Decimal
    var tax: Decimal
    var taxOnTop: Bool
    var extraCharges: Decimal
    var items: [DraftItem]
    /// The scanned receipt's printed subtotal (lifted by materialized charge rows) — the anchor the
    /// review screen's mismatch checks compare the live item sum against. nil for manual/edited drafts.
    var printedSubtotal: Decimal?

    /// When set, saving updates this existing receipt in place instead of inserting a new one.
    private var editing: Receipt?

    /// Seed from a saved receipt to edit it.
    init(editing receipt: Receipt) {
        editing = receipt
        store = receipt.store
        date = receipt.date
        discount = receipt.discount
        tax = receipt.tax
        taxOnTop = receipt.taxOnTop
        extraCharges = receipt.extraCharges
        items = receipt.items
            .sorted { $0.name < $1.name }
            .map { DraftItem(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category) }
    }

    init(from r: ExtractionResult) {
        store = r.store
        date = r.date
        discount = r.discount
        tax = r.tax
        taxOnTop = r.taxOnTop
        extraCharges = r.extraCharges
        printedSubtotal = r.printedSubtotal
        items = r.items.map { DraftItem(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category) }
    }

    init() {
        store = ""; date = .now; discount = 0; tax = 0; taxOnTop = false; extraCharges = 0
        items = []
    }

    var subtotal: Decimal { items.reduce(.zero) { $0 + $1.lineTotal } }
    var additiveCharges: Decimal { (taxOnTop ? tax : .zero) + extraCharges }
    /// What will be recorded as paid: net items − discount + on-top charges.
    var total: Decimal { subtotal - discount + additiveCharges }

    func addItem() {
        items.append(DraftItem(name: "", quantity: 1, price: 0, category: Categories.defaultName))
    }

    func remove(_ item: DraftItem) { items.removeAll { $0.id == item.id } }

    /// Save as a real receipt. When editing, update in place (keeping the original upload moment);
    /// otherwise insert a new receipt with `createdAt` = now.
    @MainActor
    func persist(into context: ModelContext, isManual: Bool = false) {
        let cleanStore = store.isEmpty ? "Unknown" : store
        let receipt: Receipt
        let stamp: Date

        if let existing = editing {
            receipt = existing
            stamp = existing.createdAt
            receipt.store = cleanStore
            receipt.date = date
            receipt.discount = discount
            receipt.tax = tax
            receipt.taxOnTop = taxOnTop
            receipt.extraCharges = extraCharges
            for old in receipt.items { context.delete(old) }
            receipt.items = []
        } else {
            stamp = Date()
            receipt = Receipt(createdAt: stamp, store: cleanStore, date: date, discount: discount,
                              isManual: isManual, tax: tax, taxOnTop: taxOnTop, extraCharges: extraCharges)
            context.insert(receipt)
        }

        for it in items where !it.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let li = LineItem(name: it.name, createdAt: stamp, price: it.price, quantity: it.quantity,
                              category: it.category)
            li.receipt = receipt
            context.insert(li)
        }
        try? context.save()
    }
}
