//
//  SupportAboutView.swift
//  Budgetty
//
//  Help, legal, and about — plus the hidden tester-premium gesture (tap the version row 11×), same
//  as Android.
//

import SwiftUI

struct SupportAboutView: View {
    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.testerPremium) private var testerUnlocked = false
    @State private var versionTaps = 0

    var body: some View {
        List {
            Section("Help") {
                link("FAQ", "questionmark.circle.fill", Palette.tint)
                link("Contact us", "envelope.fill", Color(argb: 0xFF007AFF))
                link("Suggest a feature", "lightbulb.fill", Color(argb: 0xFFFF9500))
            }

            Section("Legal") {
                link("Privacy Policy", "hand.raised.fill", Color(argb: 0xFF34C759))
                link("Terms of Service", "doc.text.fill", Color(argb: 0xFF8E8E93))
            }

            Section {
                link("Rate Budgetty", "star.fill", Color(argb: 0xFFFFD700))
                link("Share Budgetty", "square.and.arrow.up.fill", Palette.tint)
            } footer: {
                Button {
                    versionTaps += 1
                    if versionTaps >= 11 { premium = true; testerUnlocked = true }
                } label: {
                    Text(testerUnlocked ? "Budgetty 1.0 · Premium unlocked ✓" : "Budgetty 1.0 · Made with ❤️")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Support & About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, _ symbol: String, _ tint: Color) -> some View {
        Button {} label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, background: tint)
                Text(title).foregroundStyle(Palette.label)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.tertiaryLabel)
            }
        }
    }
}
