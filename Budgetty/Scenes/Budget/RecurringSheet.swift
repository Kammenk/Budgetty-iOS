//
//  RecurringSheet.swift
//  Budgetty
//
//  Add / edit an income source or a recurring bill (they're the same primitive with opposite signs).
//  Income sits outside the spend categories; a bill carries a category.
//

import SwiftUI
import SwiftData

struct RecurringSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let isIncome: Bool
    /// When non-nil, we're editing an existing entry (enables Delete).
    var existing: Recurring?

    @State private var label = ""
    @State private var amount: Decimal = 0
    @State private var cadence: Cadence = .monthly
    @State private var dueDay = 1
    @State private var category = Categories.defaultName
    @State private var showCategory = false

    private var title: LocalizedStringKey { isIncome ? "Income" : "Recurring Payment" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isIncome ? "Source (e.g. Salary)" : "Name (e.g. Netflix)", text: $label)
                    HStack {
                        Text(isIncome ? "Amount" : "Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Picker("Repeats", selection: $cadence) {
                        Text("Monthly").tag(Cadence.monthly)
                        Text("Weekly").tag(Cadence.weekly)
                        Text("Yearly").tag(Cadence.yearly)
                        Text("Once").tag(Cadence.once)
                    }
                    if cadence == .weekly {
                        Picker("Day", selection: $dueDay) {
                            ForEach(1...7, id: \.self) { Text(Self.weekdayName($0)).tag($0) }
                        }
                    } else if cadence == .monthly || cadence == .yearly {
                        Picker("Day of month", selection: $dueDay) {
                            ForEach(1...31, id: \.self) { Text(Self.ordinal($0)).tag($0) }
                        }
                    }
                }

                if !isIncome {
                    Section("Category") {
                        Button {
                            showCategory = true
                        } label: {
                            HStack {
                                Text(Categories.emoji(for: category))
                                Text(Categories.displayName(category)).foregroundStyle(Palette.label)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.tertiaryLabel)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add \(title)" : "Edit \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCategory) { CategoryPickerSheet(selection: $category) }
            .onAppear(perform: loadExisting)
        }
    }

    private func loadExisting() {
        guard let e = existing else { return }
        label = e.label; amount = e.amount; cadence = e.cadence
        dueDay = e.dueDay; category = e.category.isEmpty ? Categories.defaultName : e.category
    }

    private func save() {
        let entry = existing ?? {
            let r = Recurring(label: "", amount: 0, isIncome: isIncome)
            context.insert(r)
            return r
        }()
        entry.label = label.trimmingCharacters(in: .whitespaces)
        entry.amount = amount
        entry.cadence = cadence
        entry.dueDay = dueDay
        entry.category = isIncome ? "" : category
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let e = existing { context.delete(e); try? context.save() }
        dismiss()
    }

    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func weekdayName(_ n: Int) -> String {
        // 1 = Monday … 7 = Sunday
        let symbols = DateFormatter().weekdaySymbols ?? ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]
        let idx = n % 7 // 7→0 (Sunday), 1→1 (Monday)…
        return symbols[idx]
    }
}
