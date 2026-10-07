//
//  PlannersView.swift
//  Budgetty
//
//  Account → Planners: a small landing with the two free financial tools — the Debt payoff planner and
//  the Loan calculator. Nothing here is linked to an account. Android parity: `PlannersScreen`.
//

import SwiftUI

/// The currency symbol for the planner fields' trailing unit (reads the live currency preference).
var plannerCurrencySymbol: String {
    CurrencyOption.symbol(UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EUR")
}

struct PlannersView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Free tools to plan ahead — nothing here is linked to an account.")
                    .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                    .padding(.horizontal, 2).padding(.vertical, 4)
                HStack(spacing: 12) {
                    NavigationLink { DebtPayoffView() } label: {
                        PlannerTile(emoji: "🏔️", title: "Debt payoff",
                                    subtitle: "Snowball or avalanche to a debt-free date")
                    }.buttonStyle(.plain)
                    NavigationLink { LoanCalculatorView() } label: {
                        PlannerTile(emoji: "🏦", title: "Loan calculator",
                                    subtitle: "Monthly payment and total interest")
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            .underFloatingDock()
        }
        .background(Palette.groupedBackground)
        .navigationTitle("Planners").navigationBarTitleDisplayMode(.large)
    }
}

private struct PlannerTile: View {
    let emoji: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 26))
            Text(title).font(.headline).foregroundStyle(Palette.label)
            Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(16).contentCard(cornerRadius: 22)
    }
}
