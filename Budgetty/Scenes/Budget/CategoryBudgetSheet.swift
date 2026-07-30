//
//  CategoryBudgetSheet.swift
//  Budgetty
//
//  Set a category's overall budget together with per-subcategory budgets in one sheet. Each amount is
//  stored as its own Budget row keyed "CAT:<name>" (an amount of 0 removes the row), mirroring
//  Android's sub-budget model. Opened from a category card on the Budget tab.
//

import SwiftUI
import SwiftData

struct CategoryBudgetSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.currency) private var currency = "EUR"
    /// The pay day the financial month starts on; the "spent" figures match the Budget screen's bars.
    @AppStorage(SettingsKey.monthStartDay) private var monthStartDay = 1

    @Query private var budgets: [Budget]
    @Query(sort: \Receipt.createdAt, order: .reverse) private var receipts: [Receipt]

    /// Top-level category (group) name.
    let group: String

    /// Editable amounts, keyed by Budget key. 0 means "no budget".
    @State private var amounts: [String: Decimal] = [:]
    @State private var loaded = false

    /// Effective children by name — includes custom sub-categories and re-homed built-ins, not just
    /// the built-in taxonomy, so a custom primary's sub-budgets show here too.
    private var subNames: [String] { Categories.childNames(of: group) }
    private var groupKey: String { Budget.categoryKey(group) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category budget") {
                    amountRow(title: "Amount", key: groupKey)
                }
                if !subNames.isEmpty {
                    Section("Subcategories") {
                        ForEach(subNames, id: \.self) { subRow($0) }
                    }
                }
            }
            .navigationTitle("\(Categories.emoji(for: group)) \(Categories.displayName(group))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save() } }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: - Rows

    private func amountRow(title: LocalizedStringKey, key: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: binding(for: key), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            Text(CurrencyOption.symbol(currency)).foregroundStyle(.secondary)
        }
    }

    private func subRow(_ name: String) -> some View {
        let key = Budget.categoryKey(name)
        let sp = spent(name)
        let amt = amounts[key] ?? 0
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text(Categories.displayName(name))
                Spacer()
                Text(sp > 0 ? "\(sp.formatMoney()) spent" : "No spend")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("0", value: binding(for: key), format: .number)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 56)
                Text(CurrencyOption.symbol(currency)).font(.caption).foregroundStyle(.secondary)
            }
            if amt > 0 {
                let frac = HomeView.fraction(sp, of: amt)
                let color: Color = frac >= 1 ? Palette.bad : (frac >= 0.85 ? Palette.warn : Palette.good)
                ProgressBarView(fraction: frac, color: color, height: 4)
            }
        }
    }

    // MARK: - Data

    private func binding(for key: String) -> Binding<Decimal> {
        Binding(get: { amounts[key] ?? 0 }, set: { amounts[key] = $0 })
    }

    private func spent(_ name: String) -> Decimal {
        let window = PayCycle.monthInterval(startDay: monthStartDay)
        return receipts.flatMap(\.items)
            .filter { window.contains($0.createdAt) }
            .filter { $0.category.caseInsensitiveCompare(name) == .orderedSame }
            .reduce(.zero) { $0 + $1.lineTotal }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        var m: [String: Decimal] = [:]
        m[groupKey] = budgets.first { $0.key == groupKey }?.amount ?? 0
        for name in subNames {
            let k = Budget.categoryKey(name)
            m[k] = budgets.first { $0.key == k }?.amount ?? 0
        }
        amounts = m
    }

    private func save() {
        for (key, amount) in amounts {
            let existing = budgets.first { $0.key == key }
            if amount > 0 {
                if let e = existing { e.amount = amount }
                else { context.insert(Budget(key: key, amount: amount)) }
            } else if let e = existing {
                context.delete(e)
            }
        }
        try? context.save()
        dismiss()
    }
}
