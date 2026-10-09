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
    /// Free-form tags (normalized names) carried by this row; persisted to the line item on save.
    var tags: [String]

    init(name: String, quantity: Int, price: Decimal, category: String, tags: [String] = []) {
        self.name = name; self.quantity = quantity; self.price = price; self.category = category
        self.tags = tags
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

    /// Re-entrancy latch: a draft is persisted exactly once. Once `persist` runs this stays true, so a
    /// second Save tap — in the beat after the first save completes but before the sheet finishes
    /// dismissing — can't insert a whole duplicate receipt (a new save mints a fresh `Date()` stamp
    /// below). Also drives the Save buttons' disabled state. Mirrors Android's `stage != REVIEW` guard
    /// in `UploadViewModel.finalizeUpload`.
    private(set) var hasSaved = false

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
            .map { DraftItem(name: $0.name, quantity: $0.quantity, price: $0.price, category: $0.category,
                             tags: $0.tags.map(\.name).sorted()) }
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

    /// A blank row. Its category starts EMPTY — the review card prompts "Select category" rather than
    /// pre-picking Groceries — and an unpicked row falls back to the default on save. Android parity:
    /// `UploadViewModel.addRow` / `ParsedTransaction(category = "")` resolved in `finalizeUpload`.
    func addItem() {
        items.append(DraftItem(name: "", quantity: 1, price: 0, category: ""))
    }

    func remove(_ item: DraftItem) { items.removeAll { $0.id == item.id } }

    /// Save as a real receipt. When editing, update in place (keeping the original upload moment);
    /// otherwise insert a new receipt with `createdAt` = now. Returns the upload moment the line items
    /// were stamped with (their `createdAt`; periods bucket by the printed `date` instead).
    @MainActor
    @discardableResult
    func persist(into context: ModelContext, isManual: Bool = false) -> Date {
        // Latch against a re-entrant save (see `hasSaved`): the edit path calls this directly, so the
        // guard lives here as well as in `ScanFlowView.save()`.
        guard !hasSaved else { return editing?.createdAt ?? .now }
        hasSaved = true
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
            let category = it.category.trimmingCharacters(in: .whitespaces)
            let li = LineItem(name: it.name, createdAt: stamp, price: it.price, quantity: it.quantity,
                              category: category.isEmpty ? Categories.defaultName : category)
            li.receipt = receipt
            context.insert(li)
            // Link the row's tags, creating any missing catalog rows. Editing deleted the old items
            // above (their links cascaded), so this re-creates them from what each row now carries.
            TagOps.setTags(context, on: li, names: it.tags)
        }
        try? context.save()
        return stamp
    }

    /// True when this draft creates a brand-new receipt (not an edit of an existing one). The save-time
    /// buying-limit nudge fires only for new receipts, so editing an old receipt that still matches a
    /// keyword doesn't re-nudge — mirrors Android's `if (editing == null)` guard.
    var isNewReceipt: Bool { editing == nil }
}
