//
//  DonutChart.swift
//  Budgetty
//
//  A simple donut built from trimmed circles — one arc per slice, colored by category. Used on the
//  Insights Breakdown card.
//

import SwiftUI

struct DonutChart: View {
    /// (color, value) pairs; values need not be normalized.
    let slices: [(color: Color, value: Double)]
    var lineWidth: CGFloat = 18

    private var total: Double { max(slices.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        ZStack {
            ForEach(Array(bounds().enumerated()), id: \.offset) { _, b in
                Circle()
                    .trim(from: b.start, to: b.end)
                    .stroke(b.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
    }

    private func bounds() -> [(color: Color, start: CGFloat, end: CGFloat)] {
        var acc = 0.0
        return slices.map { s in
            let start = acc / total
            acc += s.value
            return (s.color, CGFloat(start), CGFloat(acc / total))
        }
    }
}
