//
//  DockScroll.swift
//  Budgetty
//
//  Plumbing for the floating dock's scroll-driven hide (the custom-chrome stand-in for the system
//  tab bar's `tabBarMinimizeBehavior(.onScrollDown)`): each tab root's ScrollView reports its
//  vertical offset up to the iPhone shell, which hides the dock while scrolling down and reveals
//  it on scroll up.
//

import SwiftUI

extension EnvironmentValues {
    /// Callback the iPhone shell injects so tab-root scroll views can drive the dock's hide.
    /// nil wherever there is no dock to drive (iPad shell, sheets, previews) — reporting is a no-op.
    @Entry var dockScrollReporter: ((CGFloat) -> Void)?
}

extension View {
    /// Report this scroll view's vertical content offset to the floating dock. Attach directly to
    /// a tab root's outermost vertical ScrollView.
    func reportsDockScroll() -> some View {
        modifier(DockScrollReporting())
    }
}

private struct DockScrollReporting: ViewModifier {
    @Environment(\.dockScrollReporter) private var report

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top // 0 at rest at the top
        } action: { _, y in
            report?(y)
        }
    }
}
