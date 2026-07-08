//
//  BudgetAmountSheet.swift
//  Budgetty
//
//  Set (or clear) a budget limit for a given key — the overall Monthly/Weekly budget or a
//  per-category budget (CAT:<name>).
//

import SwiftUI
import SwiftData

struct BudgetAmountSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let title: String
    let budgetKey: String
    /// The existing budget, if any (enables "Remove budget").
    var existing: Budget?

    @State private var amount: Decimal = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Remove budget", role: .destructive) { remove() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0)
                }
            }
            .onAppear { if let e = existing { amount = e.amount } }
        }
    }

    private func save() {
        if let e = existing {
            e.amount = amount
        } else {
            context.insert(Budget(key: budgetKey, amount: amount))
        }
        try? context.save()
        dismiss()
    }

    private func remove() {
        if let e = existing { context.delete(e); try? context.save() }
        dismiss()
    }
}
