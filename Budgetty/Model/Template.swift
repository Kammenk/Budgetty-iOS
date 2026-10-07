//
//  Template.swift
//  Budgetty
//
//  Android's `TemplateEntity` — a saved "regular" the user logs in one tap from the Add sheet. A
//  template never posts by itself (that's a recurring bill): tapping it pre-fills the manual-entry
//  review screen, which the user confirms. An `askAmount` template leaves the amount blank so a
//  variable regular (e.g. groceries) prompts for the price each time.
//

import Foundation
import SwiftData

@Model
final class Template {
    var emoji: String
    var name: String
    var amount: Decimal
    var category: String
    var store: String
    /// Leave the amount blank on prefill, so a variable regular asks for the price each time.
    var askAmount: Bool
    /// Orders the Add-sheet strip and the Manage list (oldest-added first), like Android's `createdAt`.
    var createdAt: Date

    init(emoji: String = "", name: String = "", amount: Decimal = 0, category: String = "",
         store: String = "", askAmount: Bool = false, createdAt: Date = .now) {
        self.emoji = emoji
        self.name = name
        self.amount = amount
        self.category = category
        self.store = store
        self.askAmount = askAmount
        self.createdAt = createdAt
    }

    /// The amount a prefill should use: blank (0) for an ask-amount template, else the saved amount.
    var prefillAmount: Decimal { askAmount ? 0 : amount }
}
