//
//  AdaptiveLayout.swift
//  Budgetty
//
//  Size-class helpers for iPad (regular width) layouts. The four main screens keep their exact
//  iPhone (compact) layout and add a `regularBody` that reflows the same card subviews into
//  multi-column arrangements. These utilities centralize the "cap the width" and "add columns on
//  iPad" logic so every screen behaves consistently.
//

import SwiftUI

/// Caps content to a readable width and centers it on regular-width (iPad) size classes; a no-op
/// on compact (iPhone) so phone layouts are untouched. Use for list/detail screens that shouldn't
/// stretch edge-to-edge in the iPad detail pane.
private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if hSize == .regular {
            content.frame(maxWidth: maxWidth, alignment: .center)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    /// On iPad (regular width) constrain to `maxWidth` and center; on iPhone do nothing.
    func adaptiveReadableWidth(_ maxWidth: CGFloat = Dimens.contentMaxWidth) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}

/// True when the horizontal size class is regular (iPad, or an iPhone in landscape split).
struct RegularWidthReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var hSize
    let content: (Bool) -> Content

    var body: some View {
        content(hSize == .regular)
    }
}

/// A set of equal, flexible grid columns whose count depends on the size class — e.g. 2 on iPhone,
/// 4 on iPad — for card grids that should gain columns on wider screens.
func adaptiveGridColumns(compact: Int, regular: Int, isRegular: Bool,
                         spacing: CGFloat = Dimens.regularColumnSpacing) -> [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: spacing), count: isRegular ? regular : compact)
}

/// Two top-aligned columns of equal width with standard spacing — the iPad dashboard idiom for
/// laying two stacks of cards side by side.
struct RegularColumns<Left: View, Right: View>: View {
    var spacing: CGFloat = Dimens.regularColumnSpacing
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: spacing) { left }.frame(maxWidth: .infinity)
            VStack(spacing: spacing) { right }.frame(maxWidth: .infinity)
        }
    }
}
