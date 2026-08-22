//
//  BuyingLimitNudgeCard.swift
//  Budgetty
//
//  The save-time buying-limit nudge: a non-blocking floating card shown over the live app right after
//  a receipt pushes a keyword limit to/over its cap. No scrim — the receipt is already saved. "Got it"
//  dismisses; "View limits" opens the Buying limits screen. In-app only. Port of Android's
//  `BuyingLimitNudgeCard`.
//

import SwiftUI

struct BuyingLimitNudgeCard: View {
    let nudge: BuyingLimitNudge
    let monthStartDay: Int
    let onDismiss: () -> Void
    let onView: () -> Void

    private var period: String {
        String(localized: nudge.timeframe == .weekly ? "this week" : "this month")
    }
    private var reset: String {
        let next = BuyingLimitCounter.nextReset(nudge.timeframe, startDay: monthStartDay)
        if nudge.timeframe == .weekly {
            let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("EEE")
            return f.string(from: next)
        }
        return DateFormatOption.current.short(next)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.warn.opacity(0.16))
                .frame(width: 34, height: 34)
                .overlay {
                    if nudge.emoji.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 15))
                            .foregroundStyle(Palette.warn)
                    } else {
                        Text(nudge.emoji).font(.system(size: 18))
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text("Heads up — that's \(nudge.countAfter)× \(nudge.title) \(period) (limit \(nudge.limitCount)).")
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Receipt saved. Your \(nudge.title) limit resets \(reset).")
                    .font(.caption).foregroundStyle(Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Got it") { onDismiss() }
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Palette.secondaryLabel)
                    Button { onView() } label: {
                        Text("View limits").font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Palette.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(cornerRadius: 22)
    }
}
