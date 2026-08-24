//
//  DonutChart.swift
//  Budgetty
//
//  A simple donut built from trimmed circles — one arc per slice, colored by category. Used on the
//  Insights Breakdown card. Optionally interactive: pass `selectedIndex` to emphasise one slice (the
//  rest recede) and `onSelect` to receive taps, mapping the tapped angle back to a slice.
//

import SwiftUI

struct DonutChart: View {
    /// (color, value) pairs; values need not be normalized.
    let slices: [(color: Color, value: Double)]
    var lineWidth: CGFloat = 18
    /// When set, that slice is emphasised (full opacity, a touch thicker) and the others recede.
    var selectedIndex: Int? = nil
    /// The planned recurring-bills overlay: the share of the ring — planned / (spend + planned) — given
    /// to a single hatched "Bills · planned" wedge appended after the category arcs. When set (> 0) the
    /// category arcs are compressed into the remaining `spend` share, so the ring reads spend + bills,
    /// but their percentages (owned by the caller's legend) stay a share of spend. `nil`/0 = off.
    var plannedFraction: CGFloat? = nil
    /// Tapping the ring reports the slice under the touch (by angle). Kept last so callers can pass it
    /// as a trailing closure after `plannedFraction`.
    var onSelect: ((Int) -> Void)? = nil

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 0.0001) }
    /// Reserve room for the emphasised (thicker) stroke so it never clips at the frame edge.
    private var maxLineWidth: CGFloat { lineWidth + 4 }
    /// The share of the ring the category arcs occupy — the whole ring when off, `1 − plannedFraction`
    /// when the overlay is on (the rest is the hatched planned wedge).
    private var spendScale: CGFloat { plannedFraction.map { max(0, min(1, 1 - $0)) } ?? 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    ForEach(Array(bounds().enumerated()), id: \.offset) { i, b in
                        Circle()
                            .trim(from: b.start, to: b.end)
                            .stroke(b.color.opacity(opacity(i)),
                                    style: StrokeStyle(lineWidth: width(i), lineCap: .butt))
                    }
                }
                .rotationEffect(.degrees(-90))
                .padding(maxLineWidth / 2)
                .animation(.easeInOut(duration: 0.18), value: selectedIndex)

                // The single hatched "Bills · planned" wedge filling the remainder of the ring. The
                // hatch itself is drawn un-rotated (so its 135° angle matches Home's planned texture);
                // only the ring-band mask is rotated to the 12-o'clock start the category arcs use.
                if let pf = plannedFraction, pf > 0 {
                    Rectangle()
                        .fill(Palette.plan.opacity(0.12))
                        .overlay(HatchStripes(step: 5).stroke(Palette.plan, lineWidth: 1.2))
                        .mask {
                            Circle()
                                .trim(from: spendScale, to: 1)
                                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                                .rotationEffect(.degrees(-90))
                                .padding(maxLineWidth / 2)
                        }
                        .opacity(selectedIndex == nil ? 1 : 0.28)
                        .animation(.easeInOut(duration: 0.18), value: selectedIndex)
                }

                // Un-rotated, full-area tap layer so the tap location stays in screen space (a tap
                // gesture doesn't block the surrounding ScrollView the way a 0-distance drag would).
                if onSelect != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture(coordinateSpace: .local).onEnded { v in
                            if let idx = sliceIndex(at: v.location, in: geo.size) { onSelect?(idx) }
                        })
                }
            }
        }
    }

    private func opacity(_ i: Int) -> Double {
        guard let sel = selectedIndex else { return 1 }
        return sel == i ? 1 : 0.28
    }

    private func width(_ i: Int) -> CGFloat {
        selectedIndex == i ? lineWidth + 4 : lineWidth
    }

    private func bounds() -> [(color: Color, start: CGFloat, end: CGFloat)] {
        var acc = 0.0
        return slices.map { s in
            let start = acc / total
            acc += s.value
            // Compress the category arcs into the `spend` share when the planned overlay is on.
            return (s.color, CGFloat(start) * spendScale, CGFloat(acc / total) * spendScale)
        }
    }

    /// Map a tap point to the slice under it. The ring starts at 12 o'clock and runs clockwise
    /// (`rotationEffect(-90°)` over a trim that begins at 3 o'clock), so fraction = (θ + 90) / 360.
    private func sliceIndex(at p: CGPoint, in size: CGSize) -> Int? {
        guard !slices.isEmpty else { return nil }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let deg = atan2(p.y - center.y, p.x - center.x) * 180 / .pi
        var f = (deg + 90) / 360
        f -= f.rounded(.down)                                    // wrap into [0, 1)
        // The hatched planned wedge (in [spendScale, 1)) is non-interactive — a tap there selects
        // nothing, matching Android (the per-bill makeup lives in the Breakdown sheet).
        if plannedFraction != nil, f >= spendScale { return nil }
        let segs = bounds()
        for (i, s) in segs.enumerated() where f >= s.start && f < s.end { return i }
        return segs.indices.last
    }
}
