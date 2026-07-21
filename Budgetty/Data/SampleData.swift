//
//  SampleData.swift
//  Budgetty
//
//  DEBUG-only demo data so screens render against realistic content during development. Runs once,
//  only when the store has no receipts, and only in DEBUG builds — release builds start empty.
//  Remove this (and its call in BudgettyApp) before shipping.
//

#if DEBUG
import Foundation
import SwiftData

enum SampleData {
    @MainActor
    static func populateIfEmpty(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        guard existing.isEmpty else { return }

        // Budgets — overall + a few per-category (group) budgets for the History › Budgets tab.
        context.insert(Budget(key: Budget.monthlyKey, amount: 1200))
        context.insert(Budget(key: Budget.weeklyKey, amount: 300))
        context.insert(Budget(key: Budget.categoryKey("Groceries"), amount: 400))
        context.insert(Budget(key: Budget.categoryKey("Dining & Entertainment"), amount: 150))
        context.insert(Budget(key: Budget.categoryKey("Health & Wellness"), amount: 200))
        context.insert(Budget(key: Budget.categoryKey("Transportation"), amount: 120))

        let cal = Calendar.current
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: .now) ?? .now }

        // (store, dayOffset, discount, [ (name, qty, unitPrice, category) ])
        // Intentionally compact tuple shape for terse fixture rows; not worth named structs here.
        // swiftlint:disable:next large_tuple
        let demo: [(String, Int, Decimal, [(String, Int, Decimal, String)])] = [
            ("Kaufland", 1, 3.20, [
                ("Milk 1L", 2, 1.19, "Dairy"),
                ("Chicken breast", 1, 6.49, "Meat & Poultry"),
                ("Bananas", 1, 2.10, "Fruits & Vegetables"),
                ("Bread", 1, 1.89, "Bakery"),
            ]),
            ("Lidl", 3, 0, [
                ("Pasta 500g", 3, 0.89, "Grains & Pasta"),
                ("Tomato sauce", 2, 1.29, "Condiments & Sauces"),
                ("Sparkling water", 6, 0.45, "Beverages"),
            ]),
            ("dm drogerie", 5, 0, [
                ("Shampoo", 1, 3.95, "Personal Care"),
                ("Toothpaste", 2, 1.79, "Personal Care"),
            ]),
            ("Shell", 7, 0, [
                ("Fuel", 1, 90.00, "Fuel"),
            ]),
            ("La Trattoria", 8, 0, [
                ("Pizza Margherita", 2, 11.50, "Restaurant & Dining"),
                ("Tiramisu", 1, 6.50, "Restaurant & Dining"),
            ]),
        ]

        // Income + recurring bills for the Budget screen.
        let salary = Recurring(label: "Salary", amount: 3500, isIncome: true, cadence: .monthly, dueDay: 1)
        context.insert(salary)
        for (label, amount, day, category) in [
            ("Netflix", Decimal(15.99), 15, "Dining & Entertainment"),
            ("Spotify", Decimal(9.99), 20, "Dining & Entertainment"),
            ("Gym membership", Decimal(35.00), 1, "Health & Wellness"),
        ] {
            context.insert(Recurring(label: label, amount: amount, isIncome: false,
                                     category: category, cadence: .monthly, dueDay: day))
        }

        for (store, offset, discount, items) in demo {
            let date = day(offset)
            let receipt = Receipt(createdAt: date, store: store, date: date, discount: discount)
            context.insert(receipt)
            for (name, qty, price, category) in items {
                let li = LineItem(name: name, createdAt: date, price: price, quantity: qty, category: category)
                li.receipt = receipt
                context.insert(li)
            }
        }
        try? context.save()
    }
}
#endif
