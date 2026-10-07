//
//  HideAmounts.swift
//  Budgetty
//
//  The "Hide amounts" privacy UI: the approved frosted-pill mask (`MoneyText`) and the nav-bar eye
//  toggle (`HideAmountsEye`). Android parity: `MoneyText.kt` + `HideAmountsEye.kt`. Both read the one
//  flag in `MoneyVisibility.shared`, so flipping the eye re-masks every amount on screen.
//

import SwiftUI

/// Renders a monetary `amount` as text, or — while "Hide amounts" is on — as a fixed-width frosted
/// pill that leaks neither the figure's magnitude nor its sign (€22 and €1,962 look identical). Use
/// for prominent amounts (heroes, row totals); the long tail of amounts spliced into strings uses the
/// plain `formatMoney` text mask ("•••• €") instead. Pass `hero: true` over the gradient hero card for
/// the white-alpha pill variant (mockup `.hero .m`).
struct MoneyText: View {
    let amount: Decimal
    var size: CGFloat = 17
    var weight: Font.Weight = .regular
    var color: Color = Palette.label
    var hero = false

    var body: some View {
        if MoneyVisibility.shared.hidden {
            Capsule()
                .fill(pillGradient)
                .frame(width: size * 2.9, height: size * 0.8)
                .blur(radius: 0.4)
                .accessibilityLabel("Amount hidden")
        } else {
            Text(amount.formatMoneyRaw())
                .font(.system(size: size, weight: weight))
                .foregroundStyle(color)
        }
    }

    private var pillGradient: LinearGradient {
        let stops: [Color] = hero
            ? [.white.opacity(0.5), .white.opacity(0.24), .white.opacity(0.5)]
            : [Palette.tertiaryLabel, Palette.fill, Palette.tertiaryLabel]
        return LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing)
    }
}

/// The nav-bar "Hide amounts" toggle (mockup 1a/1b): a glass circle with an eye while amounts show,
/// filled with the tint and an eye-with-a-slash while hidden, so the active state reads at a glance.
/// Self-contained — it reads and flips `MoneyVisibility.shared`, so it drops into any screen header.
struct HideAmountsEye: View {
    var body: some View {
        let hidden = MoneyVisibility.shared.hidden
        Button { MoneyVisibility.shared.toggle() } label: {
            Image(systemName: hidden ? "eye.slash.fill" : "eye")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(hidden ? .white : Palette.tint)
                .frame(width: 36, height: 36)
                .background {
                    if hidden {
                        Circle().fill(Palette.tint)
                    } else {
                        Circle().fill(Palette.glassFill)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.glassBorder, lineWidth: 0.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hidden ? "Show amounts" : "Hide amounts")
    }
}
