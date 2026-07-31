//
//  SavingsGoalDetailView.swift
//  Budgetty
//
//  Goal detail, presented as a sheet from the Budget tab (Android's SavingsGoalDetailScreen): a hero
//  ring with saved / target / left, Add / Withdraw, the dated contribution history, and edit / delete.
//

import SwiftUI
import SwiftData

struct SavingsGoalDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var goal: SavingsGoal

    private enum Sheet: Identifiable { case add, withdraw, edit; var id: Int { hashValue } }
    @State private var sheet: Sheet?
    @State private var confirmDelete = false

    private var sortedContributions: [SavingsContribution] {
        goal.contributions.sorted { $0.date > $1.date }
    }
    private var progress: SavingsProgress {
        SavingsMath.progress(target: goal.targetAmount, targetDate: goal.targetDate,
                             contributions: goal.contributions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    actionButtons
                    contributionsSection
                    manageCard
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
                .adaptiveReadableWidth(Dimens.contentMaxWidth)
            }
            .screenCanvas()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        EmojiChip(goal.emoji, size: 24)
                        Text(goal.name).font(.headline).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .add: SavingsContributionSheet(goal: goal, isWithdraw: false)
            case .withdraw: SavingsContributionSheet(goal: goal, isWithdraw: true)
            case .edit: SavingsGoalEditSheet(existing: goal)
            }
        }
        .confirmationDialog("Delete goal", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { context.delete(goal); try? context.save(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete “\(goal.name)” and its contributions? This can't be undone.")
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        let p = progress
        let color = savingsProgressColor(behind: p.behind)
        return VStack(spacing: 14) {
            if p.reached {
                Text("Goal reached! 🎉").font(.headline).foregroundStyle(Palette.good)
            }
            SavingsRing(fraction: p.fraction, color: color, lineWidth: 8) {
                VStack(spacing: 2) {
                    if p.reached {
                        Image(systemName: "checkmark").font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Palette.good)
                    } else {
                        Text("\(Int((p.fraction * 100).rounded()))%")
                            .font(.system(size: 30, weight: .bold)).foregroundStyle(Palette.label)
                    }
                    Text("of \(goal.targetAmount.formatMoney())")
                        .font(.caption2).foregroundStyle(Palette.secondaryLabel)
                }
            }
            .frame(width: 132, height: 132)

            HStack(spacing: 0) {
                heroStat("Saved", p.saved.formatMoney(), Palette.good)
                statDivider
                heroStat("Target", goal.targetAmount.formatMoney(), Palette.label)
                statDivider
                heroStat("Left", p.remaining.formatMoney(), Palette.label)
            }
            if let pace = detailPace(p) {
                Divider().overlay(Palette.separator)
                Text(pace).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .contentCard(cornerRadius: 20)
    }

    private func heroStat(_ label: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(Palette.secondaryLabel)
            Text(value).font(.headline).fontWeight(.bold).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
    private var statDivider: some View {
        Rectangle().fill(Palette.separator).frame(width: 1, height: 34)
    }

    /// Detail pace line: "Reached on {date}", or "€X/month to reach by {date}", or nothing.
    private func detailPace(_ p: SavingsProgress) -> String? {
        guard let date = goal.targetDate else { return nil }
        let d = Self.dayMonth(date)
        if p.reached { return String(localized: "Reached on \(d)") }
        if let rate = p.monthlyRate { return String(localized: "\(rate.formatMoney())/month to reach by \(d)") }
        return nil
    }

    // MARK: - Actions

    private var actionButtons: some View {
        let reached = progress.reached
        return HStack(spacing: 10) {
            Button { sheet = reached ? .withdraw : .add } label: {
                Label(reached ? "Withdraw to spend" : "Add to savings",
                      systemImage: reached ? "arrow.down" : "plus")
                    .font(.subheadline).fontWeight(.bold).ctaPill(height: 50)
            }
            Button { sheet = reached ? .edit : .withdraw } label: {
                Text(reached ? "Edit target" : "Withdraw")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.tint)
                    .padding(.horizontal, 18).frame(height: 50)
                    .background(Palette.tintSoft, in: Capsule())
            }
        }
    }

    // MARK: - Contributions

    private var contributionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Contributions").font(.headline)
                Text("\(sortedContributions.count)").font(.caption).foregroundStyle(Palette.secondaryLabel)
                Spacer()
            }
            if !sortedContributions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(sortedContributions.enumerated()), id: \.element.persistentModelID) { idx, c in
                        contributionRow(c)
                        if idx < sortedContributions.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .contentCard(cornerRadius: 16)
            }
        }
    }

    private func contributionRow(_ c: SavingsContribution) -> some View {
        let deposit = c.amount >= 0
        let color = deposit ? Palette.good : Palette.secondaryLabel
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.fill)
                .frame(width: 28, height: 28)
                .overlay(Text(deposit ? "+" : "−").font(.body).fontWeight(.bold).foregroundStyle(color))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.note.isEmpty ? (deposit ? String(localized: "Contribution") : String(localized: "Withdrawal")) : c.note)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label).lineLimit(1)
                Text(Self.dayMonth(c.date)).font(.caption).foregroundStyle(Palette.secondaryLabel)
            }
            Spacer(minLength: 8)
            Text("\(deposit ? "+" : "−")\(abs(c.amount).formatMoney())")
                .font(.subheadline).fontWeight(.bold).foregroundStyle(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    // MARK: - Manage

    private var manageCard: some View {
        VStack(spacing: 0) {
            Button { sheet = .edit } label: {
                manageRow(icon: "pencil", label: "Edit goal", tint: Palette.label)
            }.buttonStyle(.plain)
            Divider().padding(.leading, 52)
            Button { confirmDelete = true } label: {
                manageRow(icon: "trash", label: "Delete goal", tint: Palette.bad)
            }.buttonStyle(.plain)
        }
        .contentCard(cornerRadius: 16)
    }

    private func manageRow(icon: String, label: LocalizedStringKey, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(tint).frame(width: 24)
            Text(label).font(.subheadline).fontWeight(.semibold).foregroundStyle(tint)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    static func dayMonth(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("d MMM"); return f.string(from: date)
    }
}
