//
//  PlannerComponents.swift
//  Budgetty
//
//  Shared chrome for the planner screens (loan calculator + debt payoff): the filled, labelled numeric
//  field. Android parity: `ui/planners/PlannerComponents.kt` (`PlannerNumberField`).
//

import SwiftUI

/// A filled, labelled numeric input: a small label over the value, with an optional trailing unit
/// (e.g. "%" or the currency symbol). Decimal keyboard; the value is a text binding filtered to digits
/// and a dot by the caller (`numeric:` applies that filter).
struct PlannerNumberField: View {
    let label: LocalizedStringKey
    @Binding var value: String
    var labelColor: Color = Palette.secondaryLabel
    var trailing: String? = nil
    /// When true, keep only digits and a single-style decimal separator as the user types.
    var numeric: Bool = true
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).fontWeight(.bold).foregroundStyle(labelColor)
                .padding(.leading, 14).padding(.top, 8)
            HStack(spacing: 0) {
                TextField("", text: $value)
                    .font(.headline)
                    .keyboardType(numeric ? .decimalPad : .default)
                    .focused($focused)
                    .padding(.leading, 14).padding(.vertical, 4)
                    .onChange(of: value) { _, new in
                        if numeric { value = String(new.filter { $0.isNumber || $0 == "." }) }
                    }
                if let trailing {
                    Text(trailing).font(.headline).foregroundStyle(Palette.secondaryLabel).padding(.trailing, 14)
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tertiaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
