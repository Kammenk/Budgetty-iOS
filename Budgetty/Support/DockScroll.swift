//
//  DockScroll.swift
//  Budgetty
//
//  Plumbing between the iPhone shell's floating chrome (Scan pill + glass dock) and the tab roots
//  that scroll underneath it. Two jobs, both driven from a tab root's outermost ScrollView:
//
//   • the scroll-driven hide (the custom-chrome stand-in for the system tab bar's
//     `tabBarMinimizeBehavior(.onScrollDown)`) — the scroll view reports its vertical offset up to
//     the shell, which hides the dock while scrolling down and reveals it on scroll up;
//   • the bottom inset — the scroll view reserves the chrome's height below its content, so a page
//     scrolled to the end rests with its last row above the pill instead of buried under it.
//
//  The inset has to be applied here, per scroll view, rather than left to the shell's
//  `safeAreaInset`: every tab root wraps its ScrollView in a `NavigationStack`, which reads the
//  window's safe area and so never sees the inset its ancestor injected. If a future SwiftUI
//  release does propagate it, this padding would start double-counting and should be dropped.
//

import SwiftUI

extension EnvironmentValues {
    /// Callback the iPhone shell injects so tab-root scroll views can drive the dock's hide.
    /// nil wherever there is no dock to drive (iPad shell, sheets, previews) — reporting is a no-op.
    @Entry var dockScrollReporter: ((CGFloat) -> Void)?

    /// Measured height of the iPhone shell's floating chrome (Scan pill + gap + dock). 0 wherever
    /// there is no chrome to clear (iPad shell, previews), which zeroes the bottom inset.
    @Entry var dockChromeHeight: CGFloat = 0
}

extension View {
    /// Wire a scroll view that sits under the floating chrome: reserve the chrome's height below
    /// its content, and — for a tab root — report its offset to drive the dock's hide. Attach
    /// directly to the outermost vertical scroll container.
    ///
    /// Pushed screens (Account, Support, a receipt's detail …) keep the dock on screen too, so they
    /// need the inset; they pass `reportingScroll: false` so only a tab's own scrolling minimizes
    /// the dock.
    func underFloatingDock(reportingScroll: Bool = true) -> some View {
        modifier(FloatingDockScroll(reportingScroll: reportingScroll))
    }

    /// Lift a view that is pinned to the bottom (the paywall's footer CTA) clear of the chrome.
    /// `underFloatingDock` insets scrollable content; it can't move a `safeAreaInset` sibling, so
    /// bottom-pinned chrome asks for the clearance itself.
    func aboveFloatingDock() -> some View {
        modifier(FloatingDockClearance())
    }

    /// Mark presented content that draws over the dock — a sheet or full-screen cover. Sheets
    /// inherit the presenter's environment, so without this a screen that is *sometimes* pushed
    /// under the dock and sometimes presented modally (a receipt's detail, the paywall) would
    /// reserve space for chrome the presentation is already covering. Attach to the presented root.
    ///
    /// `\.isPresented` can't stand in for this: it is also true for a plain navigation push (that
    /// is how `dismiss()` pops), which is exactly the case that *does* need the clearance.
    func coversFloatingDock() -> some View {
        environment(\.dockChromeHeight, 0)
    }
}

/// Bottom clearance the floating chrome needs: its height plus breathing room, so content clears
/// the chrome rather than sitting flush against it (screens that already pad their own content just
/// get a little more). Zero wherever `dockChromeHeight` is — no chrome on screen, or a presentation
/// that covers it (see `coversFloatingDock`).
private func dockClearance(_ chromeHeight: CGFloat) -> CGFloat {
    chromeHeight > 0 ? chromeHeight + Dimens.spaceS : 0
}

private struct FloatingDockScroll: ViewModifier {
    let reportingScroll: Bool

    @Environment(\.dockScrollReporter) private var report
    @Environment(\.dockChromeHeight) private var chromeHeight

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, dockClearance(chromeHeight))
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top // 0 at rest at the top
            } action: { _, y in
                if reportingScroll { report?(y) }
            }
    }
}

private struct FloatingDockClearance: ViewModifier {
    @Environment(\.dockChromeHeight) private var chromeHeight

    func body(content: Content) -> some View {
        content.padding(.bottom, dockClearance(chromeHeight))
    }
}
