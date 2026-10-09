//
//  LineItem.swift
//  Budgetty
//
//  Android's TransactionEntity — a single purchased product line. Named `LineItem` (not
//  `Transaction`) to avoid clashing with SwiftUI's own `Transaction` type in every view file.
//

import Foundation
import SwiftData

@Model
final class LineItem {
    /// Product name as printed on the receipt.
    var name: String

    /// The upload moment, denormalized from the receipt (its `createdAt`). Creation-time only —
    /// recency ordering, never period bucketing: periods and windows go by `purchaseDate`.
    var createdAt: Date

    /// Unit price. The line total shown to the user is `price × quantity` (see `lineTotal`).
    var price: Decimal

    /// Quantity; identical products from one store are merged, so this can exceed 1.
    var quantity: Int

    /// Spending category name (see `Categories`). Defaults to Groceries when an upload leaves it blank.
    var category: String

    /// The receipt this line belongs to. Deleting the receipt cascades to its items.
    var receipt: Receipt?

    /// Free-form tags carried by this line item (Android's `transaction_tags` join). Orthogonal to
    /// `category`; empty by default. The inverse lives on `Tag.items`; deleting this item nullifies the
    /// links, deleting a tag nullifies them the other way — neither deletes the other side.
    @Relationship var tags: [Tag]

    init(
        name: String,
        createdAt: Date,
        price: Decimal,
        quantity: Int,
        category: String = Categories.defaultName,
        receipt: Receipt? = nil,
        tags: [Tag] = []
    ) {
        self.name = name
        self.createdAt = createdAt
        self.price = price
        self.quantity = quantity
        self.category = category
        self.receipt = receipt
        self.tags = tags
    }

    /// Price × quantity — the amount this line contributes to spend.
    var lineTotal: Decimal { price.times(quantity) }

    /// When this was bought: the parent receipt's printed `date` (falling back to the upload moment
    /// for an orphan row). What every period / window filter buckets an item by, so a receipt dated
    /// in June but scanned in October counts in June, and editing a receipt's date moves its items.
    /// Android parity: `TransactionEntity.timestamp` (the receipt's made-date).
    var purchaseDate: Date { receipt?.date ?? createdAt }
}
