//
//  Receipt.swift
//  Budgetty
//
//  Android's ReceiptEntity, plus the Android join (transactions grouped by upload) modeled here
//  as a proper SwiftData relationship. Money add-on model (tax / taxOnTop / extraCharges) is ported
//  faithfully so per-receipt spend anchors on the printed grand total.
//

import Foundation
import SwiftData

@Model
final class Receipt {
    /// The upload moment, shared with this receipt's line items (Android's `timestamp` PK).
    var createdAt: Date

    /// Store name.
    var store: String

    /// The receipt's own printed date.
    var date: Date

    /// Total savings printed on the receipt.
    var discount: Decimal

    /// True when entered manually (no scan) — drives the edit-screen "Add receipt" action.
    var isManual: Bool

    /// The receipt's tax/VAT. When `taxOnTop` is false it is *contained in* the line prices (a normal
    /// tax-inclusive receipt) and already sits inside the item sum; when true it is *added on top* of
    /// the (net) line prices — a tax-exclusive receipt (US sales tax, EU net invoice). Either way it's
    /// shown as an "incl. VAT" line. 0 when the receipt reports no tax.
    var tax: Decimal

    /// True when `tax` is added ON TOP of the net line prices rather than contained within them.
    var taxOnTop: Bool

    /// Money paid that isn't a line item, discount, or on-top tax — delivery & service fees, a courier
    /// tip, an uncaptured deposit. The gap by which the printed total exceeds what items reconcile to.
    var extraCharges: Decimal

    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt)
    var items: [LineItem]

    init(
        createdAt: Date,
        store: String,
        date: Date,
        discount: Decimal = .zero,
        isManual: Bool = false,
        tax: Decimal = .zero,
        taxOnTop: Bool = false,
        extraCharges: Decimal = .zero,
        items: [LineItem] = []
    ) {
        self.createdAt = createdAt
        self.store = store
        self.date = date
        self.discount = discount
        self.isManual = isManual
        self.tax = tax
        self.taxOnTop = taxOnTop
        self.extraCharges = extraCharges
        self.items = items
    }

    /// Summed net line totals (Σ price × quantity).
    var itemsSum: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.lineTotal }
    }

    /// Charges added ON TOP of the net line prices to reach what was paid — on-top tax (only when
    /// tax-exclusive) plus extra charges. Mirrors Android's `additiveChargesOf`.
    var additiveCharges: Decimal {
        (taxOnTop ? tax : .zero) + extraCharges
    }

    /// What was actually paid for this receipt: net items − discount + on-top charges.
    var paidTotal: Decimal {
        itemsSum - discount + additiveCharges
    }
}
