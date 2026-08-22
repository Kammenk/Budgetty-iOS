//
//  FlowLayout.swift
//  Budgetty
//
//  A simple wrapping row layout (chips flow left→right, wrapping to a new line when they run out of
//  width) — the native `Layout` equivalent of Compose's `FlowRow`, used for the buying-limit keyword
//  chips. Native only; no third-party dependency.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    /// Vertical gap between wrapped lines; defaults to `spacing`.
    var lineSpacing: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let vGap = lineSpacing ?? spacing
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for (index, row) in rows.enumerated() {
            var rowWidth: CGFloat = 0
            var rowHeight: CGFloat = 0
            for i in row {
                let size = subviews[i].sizeThatFits(.unspecified)
                rowWidth += size.width
                rowHeight = max(rowHeight, size.height)
            }
            rowWidth += spacing * CGFloat(max(row.count - 1, 0))
            maxRowWidth = max(maxRowWidth, rowWidth)
            totalHeight += rowHeight + (index > 0 ? vGap : 0)
        }
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        let vGap = lineSpacing ?? spacing
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + vGap
        }
    }

    /// Group subview indices into rows that each fit within `maxWidth`.
    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for index in subviews.indices {
            let width = subviews[index].sizeThatFits(.unspecified).width
            let needsWrap = !rows[rows.count - 1].isEmpty && x + spacing + width > maxWidth
            if needsWrap {
                rows.append([index])
                x = width
            } else {
                if !rows[rows.count - 1].isEmpty { x += spacing }
                rows[rows.count - 1].append(index)
                x += width
            }
        }
        return rows
    }
}
