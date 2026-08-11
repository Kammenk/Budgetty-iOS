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
    @AppStorage(SettingsKey.currency) private var currency = "EUR"

    let title: String
    let budgetKey: String
    /// The existing budget, if any (enables "Remove budget").
    var existing: Budget?

    @State private var amount: Decimal = 0
    /// The committed value at open, to detect unsaved edits. The overall budget commits only on an
    /// explicit Save (unlike live-saving category budgets), so a dropped edit is otherwise silent —
    /// this drives the dirty ring, the "Unsaved changes" cue, and the discard guard (Android parity).
    @State private var original: Decimal = 0
    @State private var loaded = false
    @State private var showDiscard = false

    /// The amount field differs from what's stored — an uncommitted edit.
    private var dirty: Bool { amount != original }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        // B4: currency symbol, matching the category sheet — unambiguous across our
                        // 9 currencies.
                        Text(CurrencyOption.symbol(currency)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    // Tinted ring while the amount is dirty — a persistent cue that the value hasn't
                    // been committed yet (it takes an explicit Save).
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(dirty ? Palette.tint : .clear, lineWidth: 1.5)
                    )
                } footer: {
                    if dirty {
                        Label("Unsaved changes", systemImage: "pencil.circle")
                            .font(.caption).foregroundStyle(Palette.tint)
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
            // Don't let a swipe-to-dismiss silently drop an unsaved amount — route it through the guard.
            .interactiveDismissDisabled(dirty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if dirty { showDiscard = true } else { dismiss() } }
                }
                // Persistent Save affordance; emphasized while there's an uncommitted edit to commit.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(amount <= 0)
                        .fontWeight(dirty ? .semibold : .regular)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let e = existing { amount = e.amount; original = e.amount }
            }
        }
    }

    private func save() {
        if let e = existing {
            e.amount = amount
        } else {
            context.insert(Budget(key: budgetKey, amount: amount))
        }
        try? context.save()
        original = amount   // committed — clears the dirty state before the sheet closes
        dismiss()
    }

    private func remove() {
        if let e = existing { context.delete(e); try? context.save() }
        dismiss()
    }
}
