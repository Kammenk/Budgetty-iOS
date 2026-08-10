//
//  SavingsSheets.swift
//  Budgetty
//
//  The savings-goal sheets: log a contribution / withdrawal, create or edit a goal, and pick a goal
//  emoji. Ports of Android's SavingsContributionSheet / SavingsGoalEditSheet — Form-based like the
//  app's RecurringSheet, so they stay native and consistent.
//

import SwiftUI
import SwiftData

// MARK: - Add to savings / Withdraw

struct SavingsContributionSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let goal: SavingsGoal
    let isWithdraw: Bool

    @State private var amount: Decimal = 0
    @State private var note = ""
    @State private var date = Date.now

    private var saved: Decimal { SavingsMath.saved(goal.contributions) }
    private var newSaved: Decimal { isWithdraw ? saved - amount : saved + amount }
    private var newPct: Int {
        goal.targetAmount > 0
            ? Int(((newSaved as NSDecimalNumber).doubleValue / (goal.targetAmount as NSDecimalNumber).doubleValue) * 100)
            : 0
    }

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
                    TextField("What was it for?", text: $note)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                if amount > 0 {
                    // Pre-format the percent so the string catalog key is "…· %@" (a plain string arg),
                    // not a literal-percent format the ported Android translation would fight.
                    let pctText = "\(newPct)%"
                    Section {
                        Text("New total \(newSaved.formatMoney()) of \(goal.targetAmount.formatMoney()) · \(pctText)")
                            .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                if isWithdraw {
                    Section {
                        Text("Withdrawals lower your saved total. The goal stays where it is.")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
            .navigationTitle(isWithdraw ? "Withdraw" : "Add to savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { save() }.disabled(amount <= 0)
                }
            }
        }
    }

    private var confirmTitle: LocalizedStringKey {
        isWithdraw ? "Withdraw \(amount.formatMoney())" : "Add \(amount.formatMoney())"
    }

    private func save() {
        let signed = isWithdraw ? -amount : amount
        let c = SavingsContribution(amount: signed, note: note.trimmingCharacters(in: .whitespaces),
                                    date: date, goal: goal)
        context.insert(c)
        try? context.save()
        dismiss()
    }
}

// MARK: - Create / edit goal

struct SavingsGoalEditSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new goal; non-nil = edit.
    var existing: SavingsGoal?

    @State private var emoji = "🎯"
    @State private var name = ""
    @State private var target: Decimal = 0
    @State private var hasDate = false
    @State private var targetDate = Date.now
    @State private var showEmoji = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showEmoji = true } label: {
                        HStack {
                            Text("Goal emoji").foregroundStyle(Palette.label)
                            Spacer()
                            Text(emoji).font(.title2)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.tertiaryLabel)
                        }
                    }
                    TextField("Japan trip", text: $name)
                        .textInputAutocapitalization(.sentences)
                    HStack {
                        Text("Target amount")
                        Spacer()
                        TextField("0", value: $target, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Toggle("Target date", isOn: $hasDate).tint(Palette.tint)
                    if hasDate {
                        DatePicker("Pick a date", selection: $targetDate, displayedComponents: .date)
                    } else {
                        Text("Adds a monthly pace to the card")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                if existing == nil {
                    Section {
                        Text("Free plan: 1 goal. Premium adds as many as you like.")
                            .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create goal" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || target <= 0)
                }
            }
            .sheet(isPresented: $showEmoji) { EmojiPickerSheet(selection: $emoji) }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let e = existing else { return }
        emoji = e.emoji; name = e.name; target = e.targetAmount
        if let d = e.targetDate { hasDate = true; targetDate = d }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let date = hasDate ? targetDate : nil
        if let e = existing {
            e.name = trimmed; e.emoji = emoji; e.targetAmount = target; e.targetDate = date
        } else {
            context.insert(SavingsGoal(name: trimmed, emoji: emoji, targetAmount: target, targetDate: date))
        }
        try? context.save()
        dismiss()
    }
}

// MARK: - Emoji picker

/// A compact searchable emoji grid over the shared `EmojiCatalog` (the same source the category
/// picker uses), for choosing a goal's emoji.
struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var results: [EmojiCatalog.Entry] { EmojiCatalog.search(query) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.isEmpty {
                    ForEach(EmojiCatalog.sections, id: \.title) { section in
                        HStack {
                            Text(section.title).font(.caption).fontWeight(.semibold)
                                .foregroundStyle(Palette.secondaryLabel).textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.top, 10)
                        grid(section.entries)
                    }
                } else {
                    grid(results)
                }
            }
            .navigationTitle("Goal emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .searchable(text: $query)
        }
    }

    private func grid(_ entries: [EmojiCatalog.Entry]) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(entries, id: \.emoji) { entry in
                Button { selection = entry.emoji; dismiss() } label: {
                    Text(entry.emoji).font(.system(size: 26))
                        .frame(width: 40, height: 40)
                        .background(entry.emoji == selection ? Palette.tintSoft : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }
}
