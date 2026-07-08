//
//  NotificationsView.swift
//  Budgetty
//
//  Notification preferences + a simple alerts inbox. Reached from Account → Notifications.
//

import SwiftUI

struct NotificationsView: View {
    @AppStorage("pref.notif.budget") private var budgetAlerts = true
    @AppStorage("pref.notif.weekly") private var weeklySummary = true
    @AppStorage("pref.notif.large") private var largePurchase = false
    @AppStorage("pref.notif.tips") private var tips = false

    var body: some View {
        List {
            Section("Alerts") {
                toggle("Budget alerts", "When you near or pass a budget", "bell.badge.fill", Palette.bad, $budgetAlerts)
                toggle("Weekly summary", "A recap every Monday", "calendar", Color(argb: 0xFFFF9500), $weeklySummary)
                toggle("Large purchases", "Flag unusually big receipts", "exclamationmark.circle.fill", Color(argb: 0xFF007AFF), $largePurchase)
                toggle("Tips & news", "Occasional product updates", "sparkles", Palette.tint, $tips)
            }

            Section("Inbox") {
                ContentUnavailableView("You're all caught up",
                                       systemImage: "checkmark.circle",
                                       description: Text("New alerts will show up here."))
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ title: String, _ subtitle: String, _ symbol: String, _ tint: Color,
                        _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, background: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
