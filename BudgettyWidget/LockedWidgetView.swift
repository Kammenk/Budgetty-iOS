//
//  LockedWidgetView.swift
//  BudgettyWidget
//
//  What a widget draws once it's past the free tier's `WidgetQuota.freeLimit`.
//
//  This is where the cap is actually enforced. iOS gives an app no way to refuse a placement — the
//  home-screen widget picker never runs our code, and there is no `requestPinAppWidget` equivalent —
//  so the in-app gallery's gate is a courtesy and *this* is the enforcement. Android lands in the
//  same place for the same reason.
//
//  Copy note: Android's locked card says "Tap to upgrade" because it deep-links straight to the
//  paywall. iOS can't — the app has no physical Info.plist, so no custom URL scheme is registered
//  (see the Google sign-in note in PARITY.md) and a tap just opens the app. So the second line states
//  what's on offer instead of promising what the tap does.
//

import SwiftUI
import WidgetKit

struct LockedWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: family == .systemSmall ? 8 : 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: family == .systemSmall ? 20 : 24, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text("Widget locked")
                    .font(family == .systemSmall ? .caption : .subheadline).bold()
                    .foregroundStyle(.primary)
                Text("Unlock more widgets")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(family == .systemSmall ? 10 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
