//
//  TabSwitching.swift
//  Budgetty
//
//  Plumbing that lets a tab-root view switch the app's selected tab — e.g. Home's "See All" links
//  jump to History / Budget, mirroring Android where those cards navigate to their full screen.
//  The shell (RootView) injects the closure; it's nil in previews / contexts without a shell, where
//  switching is a harmless no-op.
//

import SwiftUI

extension EnvironmentValues {
    /// Switch the app's selected bottom-tab. nil wherever there is no tab shell to drive.
    @Entry var selectTab: ((AppTab) -> Void)?
}
