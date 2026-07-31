//
//  SavingsSection.swift
//  Budgetty
//
//  The Savings-goals section on the Budget tab — a port of Android's SavingsSection. Header (with a
//  count badge + total-saved once there are 2+) and an honesty subtitle, then the goals as quiet ring
//  cards with a "New goal" affordance, or the empty prompt, or the 1-goal free cap's locked row +
//  unlock nudge. Progress uses the app's positive green (amber when a dated goal is behind pace).
//

import SwiftUI
import SwiftData

/// Green for on-track / positive; amber when a dated goal is behind its required pace.
func savingsProgressColor(behind: Bool) -> Color { behind ? Palette.warn : Palette.good }

struct SavingsSectionView: View {
    @Query(sort: \SavingsGoal.createdAt) private var goals: [SavingsGoal]
    @Query private var contributions: [SavingsContribution]

    let isPremium: Bool
    let onGoalTap: (SavingsGoal) -> Void
    let onNewGoal: () -> Void
    let onUpgrade: () -> Void

    private func contributions(of goal: SavingsGoal) -> [SavingsContribution] {
        contributions.filter { $0.goal?.persistentModelID == goal.persistentModelID }
    }
    private func progress(_ goal: SavingsGoal) -> SavingsProgress {
        SavingsMath.progress(target: goal.targetAmount, targetDate: goal.targetDate,
                             contributions: contributions(of: goal))
    }
    private var atCap: Bool { !isPremium && goals.count >= SavingsQuota.freeLimit }
    private var totalSaved: Decimal { goals.reduce(Decimal.zero) { $0 + progress($1).saved } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Savings goals").font(.headline).foregroundStyle(Palette.label)
                if goals.count >= 2 {
                    Text("\(goals.count)").font(.caption2).fontWeight(.bold).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Palette.tint, in: Capsule())
                    Spacer()
                    Text("\(totalSaved.formatMoney()) saved")
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.good)
                } else {
                    Spacer()
                }
            }
            Text("You log what you set aside — Budgetty doesn't hold money.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
                .padding(.top, 2).padding(.bottom, 10)

            if goals.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        Button { onGoalTap(goal) } label: { goalCard(goal) }
                            .buttonStyle(.plain)
                    }
                    if atCap {
                        lockedRow
                        unlockCard
                    } else {
                        addRow
                    }
                }
            }
        }
    }

    // MARK: - Goal card

    private func goalCard(_ goal: SavingsGoal) -> some View {
        let p = progress(goal)
        let color = savingsProgressColor(behind: p.behind)
        return HStack(spacing: 12) {
            SavingsRing(fraction: p.fraction, color: color, lineWidth: 4.2) {
                Text("\(Int((p.fraction * 100).rounded()))%")
                    .font(.caption2).fontWeight(.bold).foregroundStyle(Palette.label)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    EmojiChip(goal.emoji, size: 22)
                    Text(goal.name).font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                        .lineLimit(1)
                }
                Text("\(p.saved.formatMoney()) of \(goal.targetAmount.formatMoney()) · \(p.remaining.formatMoney()) to go")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel).lineLimit(1)
                paceLine(goal, p, color)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 16)
    }

    /// The card's third line: "reached", or a monthly pace + on-track/behind hint, or nothing.
    @ViewBuilder
    private func paceLine(_ goal: SavingsGoal, _ p: SavingsProgress, _ color: Color) -> some View {
        if p.reached {
            Text("Goal reached! 🎉").font(.caption).fontWeight(.semibold).foregroundStyle(Palette.good)
        } else if let rate = p.monthlyRate, let date = goal.targetDate {
            (Text("\(rate.formatMoney())/mo to \(Self.shortMonth(date))").foregroundStyle(Palette.secondaryLabel)
             + Text(verbatim: " · ").foregroundStyle(Palette.secondaryLabel)
             + Text(p.behind ? "behind" : "on track").fontWeight(.semibold).foregroundStyle(color))
                .font(.caption).lineLimit(1)
        }
    }

    // MARK: - Empty / add / locked

    private var emptyCard: some View {
        VStack(spacing: 8) {
            EmojiChip("🎯", size: 44)
            Text("Set a savings goal").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("Name it, pick a target, and track what you put aside — a new laptop, a trip, a rainy-day fund.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel).multilineTextAlignment(.center)
            Button { onNewGoal() } label: {
                Label("New goal", systemImage: "plus").font(.subheadline).fontWeight(.bold)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .foregroundStyle(.white).background(Palette.scanCTA, in: Capsule())
            }
            .padding(.top, 4)
            Text("1 goal free · unlimited with Premium")
                .font(.caption2).foregroundStyle(Palette.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .contentCard(cornerRadius: 16)
    }

    private var addRow: some View {
        Button { onNewGoal() } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                Text("New goal").fontWeight(.semibold)
                Spacer()
            }
            .foregroundStyle(Palette.tint)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private var lockedRow: some View {
        Button { onUpgrade() } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.secondaryLabel)
                Text("New goal").fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                Spacer()
                Text("Premium").font(.caption).fontWeight(.bold).foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private var unlockCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unlock unlimited goals").font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
            Text("The free plan includes 1 savings goal. Premium adds as many as you like — plus unlimited scans and custom categories.")
                .font(.caption).foregroundStyle(Palette.secondaryLabel)
            Button { onUpgrade() } label: {
                Text("Go Premium").font(.subheadline).fontWeight(.bold).ctaPill(height: 46)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentCard(cornerRadius: 16)
    }

    static func shortMonth(_ date: Date) -> String {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM"); return f.string(from: date)
    }
}

// MARK: - Ring + emoji chip

/// A circular progress ring with centered content — the savings card / detail ring.
struct SavingsRing<Label: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 4.2
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Palette.fill, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.0001, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
    }
}

/// A small rounded emoji tile (the goal's emoji chip).
struct EmojiChip: View {
    let emoji: String
    let size: CGFloat
    init(_ emoji: String, size: CGFloat) { self.emoji = emoji; self.size = size }
    var body: some View {
        RoundedRectangle(cornerRadius: size / 3, style: .continuous)
            .fill(Palette.tintSoft)
            .frame(width: size, height: size)
            .overlay(Text(emoji).font(.system(size: size * 0.55)))
    }
}
