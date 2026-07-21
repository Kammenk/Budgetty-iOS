//
//  NotificationsView.swift
//  Budgetty
//
//  Notification preferences + a simple alerts inbox — Liquid Glass v2 (iOS Notifications.dc.html):
//  glass section cards over the ambient canvas, colored icon tiles, inline toggles.
//  Reached from Account → Notifications.
//

import SwiftUI

struct NotificationsView: View {
    @AppStorage("pref.notif.budget") private var budgetAlerts = true
    @AppStorage("pref.notif.weekly") private var weeklySummary = true
    @AppStorage("pref.notif.large") private var largePurchase = false
    @AppStorage("pref.notif.tips") private var tips = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("Alerts")
                VStack(spacing: 0) {
                    toggle("Budget alerts", "When you near or pass a budget", "bell.badge.fill", Palette.bad, $budgetAlerts)
                    divider
                    toggle("Weekly summary", "A recap every Monday", "calendar", Color(argb: 0xFFFF9500), $weeklySummary)
                    divider
                    toggle("Large purchases", "Flag unusually big receipts", "exclamationmark.circle.fill", Color(argb: 0xFF007AFF), $largePurchase)
                    divider
                    toggle("Tips & news", "Occasional product updates", "sparkles", Palette.tint, $tips)
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                sectionHeader("Inbox")
                ContentUnavailableView("You're all caught up",
                                       systemImage: "checkmark.circle",
                                       description: Text("New alerts will show up here."))
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .contentCard(cornerRadius: 14)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
            .adaptiveReadableWidth()
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        .navigationTitle("Notifications")
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(Palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle().fill(Palette.separator).frame(height: 0.5)
    }

    private func toggle(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey, _ symbol: String, _ tint: Color,
                        _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, background: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(Palette.label)
                    Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
                }
            }
        }
        .tint(Palette.good)
        .padding(.vertical, 10).padding(.horizontal, 16)
    }
}
