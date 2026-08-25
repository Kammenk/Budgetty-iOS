//
//  PlannedHatch.swift
//  Budgetty
//
//  Budgetty's shared "planned, not yet real" visual language — one diagonal-hatch texture, so a
//  hatched fill reads as "planned recurring bills, not money I actually spent" identically on Home
//  (the spent-vs-planned strip) and in the Insights recurring-bills overlay (Android parity:
//  `PlannedHatch.kt` / `drawPlannedHatch`). The hatch is always drawn on the neutral muted `--plan`
//  token (`Palette.plan`), never a category hue or a status colour, so "planned" never reads as
//  "spent", "good" or "over".
//

import SwiftUI

/// Diagonal 135° stripe lines covering the given rect — the shared planned texture. Shared by Home's
/// `hatchedFill` (white stripes on the hero) and the Insights overlay (neutral `--plan` stripes); the
/// caller sets the colour + stroke width. Default `step` matches Home's shipped rhythm.
struct HatchStripes: Shape {
    var step: CGFloat = 4.5
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return p
    }
}

/// A small rounded-square legend key filled with the planned hatch on a `--plan` outline — the
/// leading icon on the Customize "Include recurring bills" row and the mark in the overlay sheets.
/// Android parity: `PlannedSwatch(hatched = true)`.
struct PlannedHatchSwatch: View {
    var size: CGFloat = 16
    var corner: CGFloat = 4
    var color: Color = Palette.plan

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape.fill(.clear)
            .overlay(HatchStripes(step: 3.2).stroke(color, lineWidth: 1.3).clipShape(shape))
            .overlay(shape.strokeBorder(color, lineWidth: 1))
            .frame(width: size, height: size)
    }
}

/// The quiet, tappable "Planned" badge shown in an Insights section header (Breakdown / Trend) when
/// the recurring-bills overlay is on. It doubles as the overlay's legend — a hatch swatch plus the
/// one-word label — and as the entry point to that section's read-only explainer sheet. Styled as a
/// muted status chip (the same fill as the period pill), NOT a prominent button, so it reads as a
/// legend rather than out-shouting the real controls. Android parity: `PlannedBadge`.
struct PlannedBadge: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                PlannedHatchSwatch(size: 9, corner: 2.5)
                Text("Planned")
                    .font(.caption).fontWeight(.medium)
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Palette.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Planned")
    }
}

extension View {
    /// Overlays the neutral planned hatch clipped to `shape`, over the view's own background, and adds
    /// a thin `--plan` rim — the "planned" tile / cap treatment in the overlay sheets (mockup's
    /// `repeating-linear-gradient(135deg, --plan …)` + `inset 0 0 0 1px --plan`).
    func plannedHatchOverlay<S: InsettableShape>(in shape: S, step: CGFloat = 5) -> some View {
        overlay(HatchStripes(step: step).stroke(Palette.plan, lineWidth: 1.2).clipShape(shape))
            .overlay(shape.strokeBorder(Palette.plan, lineWidth: 1))
    }
}
