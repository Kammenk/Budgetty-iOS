//
//  WellbeingBanner.swift
//  Budgetty
//
//  The compact live-teaser banner into the Wellbeing screen (Android's WellbeingBanner): a 40pt score
//  ring, "Wellbeing · {band}", one truncated top-tip line and a chevron. The lightest card on Home —
//  never a second hero. Takes a soft attention wash when the band is low or the top tip is an alert;
//  falls to first-run copy before there's a score. Wrapped in a NavigationLink by HomeView.
//

import SwiftUI

struct WellbeingBanner: View {
    let summary: WellbeingSummary

    var body: some View {
        let firstRun = !summary.hasScore
        let topTip = summary.monthlyTips.first
        let attention = !firstRun && (summary.score.band == .needsWork || topTip?.tone == .alert)
        let ringColor = attention ? Palette.bad : wbBandColor(summary.score.band)

        return HStack(spacing: 12) {
            ZStack {
                SavingsRing(fraction: firstRun ? 0 : Double(summary.score.score ?? 0) / 100,
                            color: ringColor, lineWidth: 4.4) {
                    (firstRun ? Text(verbatim: "—") : Text("\(summary.score.score ?? 0)"))
                        .font(.caption).fontWeight(.heavy)
                        .foregroundStyle(firstRun ? Palette.secondaryLabel : Palette.label)
                }
                .frame(width: 40, height: 40)
                // Unseen-tip dot — marks the tip, not the destination.
                if !firstRun, topTip != nil {
                    Circle().fill(Palette.tint).frame(width: 8, height: 8)
                        .overlay(Circle().strokeBorder(Palette.card, lineWidth: 1.5))
                        .offset(x: 15, y: -15)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("Wellbeing").font(.caption2).fontWeight(.semibold)
                        .foregroundStyle(Palette.secondaryLabel)
                    if !firstRun {
                        Text(verbatim: "·").font(.caption2).foregroundStyle(ringColor)
                        Text(wbBandWord(summary.score.band)).font(.caption2).fontWeight(.bold)
                            .foregroundStyle(ringColor)
                    }
                }
                bannerLine(firstRun: firstRun, tip: topTip)
                    .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.label)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.tertiaryLabel)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if attention {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.bad.opacity(0.12))
            }
        }
        .contentCard(cornerRadius: 20)
    }

    private func bannerLine(firstRun: Bool, tip: WellbeingTip?) -> Text {
        if firstRun { return Text("Set a budget to unlock it") }
        guard let tip else { return Text("See how you're doing") }
        let amt = (tip.amount ?? .zero).formatMoney()
        let label = tip.label ?? ""
        switch tip.type {
        case .categorySpike: return Text("\(label) is up \(tip.percent ?? 0)%")
        case .negativeCashflow: return Text("\(amt) more out than in")
        case .overBudget: return Text("Over budget this month")
        case .subscriptionCost: return Text("\(amt) a month on subscriptions")
        case .missingBudget: return Text("No budget on \(label)")
        case .noGoal: return Text("Start a savings goal")
        case .savingsWin: return Text("Saved \(tip.percent ?? 0)% this month")
        default: return Text("See how you're doing")
        }
    }
}
