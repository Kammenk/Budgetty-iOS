//
//  StartTripSheet.swift
//  Budgetty
//
//  The "Start a trip" form sheet (mockup 3b). Only the name is required; the tag derives from it +
//  the start year (shown live). Dates and budget are optional switches; with a start date set, a
//  backfill option tags the expenses already added since then. Android parity: `TripsScreen` start
//  sheet + `TripsViewModel.start`.
//

import SwiftUI
import SwiftData

struct StartTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var hasDates = false
    @State private var startDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var endDate: Date = Calendar.current.startOfDay(for: .now).addingTimeInterval(6 * 86_400)
    @State private var hasBudget = false
    @State private var budget: Decimal = 0
    @State private var backfill = true
    @FocusState private var focusedField: Field?

    private enum Field { case name, amount }

    private var tag: String { TripOps.tripTag(name, hasDates ? startDate : nil) }
    private var canStart: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var backfillCount: Int {
        guard hasDates else { return 0 }
        return TripOps.itemsSince(context, Calendar.current.startOfDay(for: startDate)).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("✈️").font(.system(size: 44)).padding(.top, 6)
                    detailsCard
                    Text("Optional. With dates set, the trip ends itself after the last day.")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
                    budgetCard
                    autoTagExplainer
                    if hasDates && backfillCount > 0 { backfillRow }
                }
                .padding(20)
            }
            .background(Palette.groupedBackground)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New trip").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.fontWeight(.semibold).disabled(!canStart)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Name").foregroundStyle(Palette.label)
                TextField("Trip name", text: $name).multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words).focused($focusedField, equals: .name)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().padding(.leading, 16)
            Toggle("Dates", isOn: $hasDates.animation()).tint(Palette.good)
                .padding(.horizontal, 16).padding(.vertical, 6)
            if hasDates {
                Divider().padding(.leading, 16)
                HStack { Text("From").foregroundStyle(Palette.label); Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden() }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                Divider().padding(.leading, 16)
                HStack { Text("To").foregroundStyle(Palette.label); Spacer()
                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date).labelsHidden() }
                    .padding(.horizontal, 16).padding(.vertical, 6)
            }
        }
        .contentCard(cornerRadius: 18)
    }

    private var budgetCard: some View {
        VStack(spacing: 0) {
            Toggle("Trip budget", isOn: $hasBudget.animation()).tint(Palette.good)
                .padding(.horizontal, 16).padding(.vertical, 6)
            if hasBudget {
                Divider().padding(.leading, 16)
                HStack {
                    Text("Amount").foregroundStyle(Palette.label)
                    Spacer()
                    AmountField(value: $budget).multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140).focused($focusedField, equals: .amount)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        }
        .contentCard(cornerRadius: 18)
    }

    private var autoTagExplainer: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("✈️").font(.body)
            // One interpolated literal so the #tag bolds via markdown.
            Text("New expenses will auto-tag **#\(tag)** until you end the trip. You can remove it from any single expense.")
                .font(.subheadline).foregroundStyle(Palette.label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var backfillRow: some View {
        Button { backfill.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: backfill ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(backfill ? Palette.tint : Palette.tertiaryLabel)
                Text("Also tag the \(backfillCount) expense\(backfillCount == 1 ? "" : "s") already added since the start date")
                    .font(.subheadline).foregroundStyle(Palette.label)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func start() {
        TripOps.start(context, name: name,
                      startDate: hasDates ? startDate : nil,
                      endDate: hasDates ? endDate : nil,
                      budget: hasBudget && budget > 0 ? budget : nil,
                      backfill: hasDates && backfill)
        dismiss()
    }
}
