//
//  FortnightSwitchSheet.swift
//  Budgetty
//
//  The one-time explainer before adopting the fortnightly budget cadence: it names the fortnight the
//  user lands in ("This fortnight · 6 Oct – 19 Oct") and what happens to the budget amount
//  ("650 € → 300 € / fortnight", monthly × 12 ÷ 26), and reassures that nothing is deleted. Replaces a
//  plain alert that showed neither. Android parity: `FortnightSwitchSheet` in BudgetScreen.kt — same
//  title, body, window row and budget row. Confirming applies the cadence straight away, as every other
//  cadence switch on the iOS Budget screen does.
//

import SwiftUI

struct FortnightSwitchSheet: View {
    /// What the switch does to the budget amount.
    enum BudgetChange: Equatable {
        /// A fortnightly budget is already set; the switch keeps it.
        case kept(Decimal)
        /// No fortnightly budget yet: the monthly one is prorated (× 12 ÷ 26) into it on confirm.
        case prorated(monthly: Decimal, fortnightly: Decimal)
    }

    /// Inclusive first / last day of the fortnight the switch lands in.
    let windowStart: Date
    let windowEnd: Date
    /// `nil` when there's no budget amount to carry (no row is shown).
    let budget: BudgetChange?
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.dateFormat) private var dateFormatRaw = DateFormatOption.system.rawValue
    /// The sheet sizes to its content (the body wraps to more lines in longer languages).
    @State private var contentHeight: CGFloat = 440

    private var dateFormat: DateFormatOption { DateFormatOption(rawValue: dateFormatRaw) ?? .system }

    private var windowText: String {
        String(localized: "This fortnight · \(dateFormat.short(windowStart)) – \(dateFormat.short(windowEnd))")
    }

    private var budgetText: String? {
        switch budget {
        case .kept(let amount):
            String(localized: "\(amount.formatMoney()) / fortnight")
        case .prorated(let monthly, let fortnightly):
            String(localized: "\(monthly.formatMoney()) → \(fortnightly.formatMoney()) / fortnight")
        case nil:
            nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Switch to fortnightly?").font(.title3).fontWeight(.bold)
            Text("Your budget and bills keep their monthly figures — Budgetty just shows them per fortnight. Nothing is deleted, and past periods stay as they were.")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                infoRow("Your first fortnight", windowText)
                if let budgetText { infoRow("Budget", budgetText) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(cornerRadius: 16)

            VStack(spacing: 0) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Use fortnightly").font(.headline).ctaPill(height: 50)
                }
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Palette.tint).padding(.vertical, 14)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 20).padding(.top, 28)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    /// A tinted label over its value — the Android sheet's `SwitchInfoRow`.
    private func infoRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundStyle(Palette.tint)
            Text(value).font(.body).fontWeight(.semibold).foregroundStyle(Palette.label)
        }
    }
}
