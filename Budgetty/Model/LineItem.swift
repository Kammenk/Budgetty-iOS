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

    /// The upload moment — what Home/History filter and group by (Android's `timestamp`).
    /// Denormalized onto the item (as well as the receipt) so date-range `@Query`s stay simple.
    var createdAt: Date

    /// Unit price. The line total shown to the user is `price × quantity` (see `lineTotal`).
    var price: Decimal

    /// Quantity; identical products from one store are merged, so this can exceed 1.
    var quantity: Int

    /// Spending category name (see `Categories`). Defaults to Groceries when an upload leaves it blank.
    var category: String

    /// The receipt this line belongs to. Deleting the receipt cascades to its items.
    var receipt: Receipt?

    init(
        name: String,
        createdAt: Date,
        price: Decimal,
        quantity: Int,
        category: String = Categories.defaultName,
        receipt: Receipt? = nil
    ) {
        self.name = name
        self.createdAt = createdAt
        self.price = price
        self.quantity = quantity
        self.category = category
        self.receipt = receipt
    }

    /// Price × quantity — the amount this line contributes to spend.
    var lineTotal: Decimal { price.times(quantity) }
}
