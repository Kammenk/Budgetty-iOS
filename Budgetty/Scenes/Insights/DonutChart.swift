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
    /// Tapping the ring reports the slice under the touch (by angle).
    var onSelect: ((Int) -> Void)? = nil

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 0.0001) }
    /// Reserve room for the emphasised (thicker) stroke so it never clips at the frame edge.
    private var maxLineWidth: CGFloat { lineWidth + 4 }

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
            return (s.color, CGFloat(start), CGFloat(acc / total))
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
        let segs = bounds()
        for (i, s) in segs.enumerated() where f >= s.start && f < s.end { return i }
        return segs.indices.last
    }
}
