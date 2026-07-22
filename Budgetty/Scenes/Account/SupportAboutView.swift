//
//  SupportAboutView.swift
//  Budgetty
//
//  Help, legal, and about — Liquid Glass v2 (iOS Support & About.dc.html): glass section cards over
//  the ambient canvas, plus the brand logo footer. Keeps the hidden tester-premium gesture (tap the
//  version row 11×), same as Android.
//

import SwiftUI

struct SupportAboutView: View {
    @AppStorage(SettingsKey.premium) private var premium = false
    @AppStorage(SettingsKey.testerPremium) private var testerUnlocked = false
    @State private var versionTaps = 0
    @Environment(\.openURL) private var openURL

    /// The hosted policy, same document the Android app links to (`URL_PRIVACY` in AccountScreen.kt)
    /// and the one the App Store listing points at. Section 1(f) is what discloses crash reporting,
    /// so this link is part of the Crashlytics shipping gate — an app that collects crash data has
    /// to give the user a way to read what that means.
    private static let privacyPolicy = URL(string: "https://budgetty-96a3d.web.app/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("Help")
                VStack(spacing: 0) {
                    link("FAQ", "questionmark.circle.fill", Palette.tint)
                    divider
                    link("Contact us", "envelope.fill", Color(argb: 0xFF007AFF))
                    divider
                    link("Suggest a feature", "lightbulb.fill", Color(argb: 0xFFFF9500))
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                sectionHeader("Legal")
                VStack(spacing: 0) {
                    link("Privacy Policy", "hand.raised.fill", Color(argb: 0xFF34C759),
                         url: Self.privacyPolicy)
                    divider
                    // ⚠️ Still inert, and not fixable by picking a URL: no terms document exists on
                    // either platform. Apple's standard EULA covers subscriptions by default, but
                    // which document this row points at is the owner's call.
                    link("Terms of Service", "doc.text.fill", Color(argb: 0xFF8E8E93))
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                sectionHeader("About")
                VStack(spacing: 0) {
                    link("Rate Budgetty", "star.fill", Color(argb: 0xFFFFD700))
                    divider
                    link("Share Budgetty", "square.and.arrow.up.fill", Palette.tint)
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 36)

                // Brand footer (mockup: logo tile + name + tagline); the version line doubles as the
                // hidden tester-premium unlock.
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Palette.heroGradient)
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "doc.text.fill").font(.system(size: 30)).foregroundStyle(.white))
                    .shadow(color: Palette.tint.opacity(0.35), radius: 12, y: 6)
                    .padding(.bottom, 12)
                Text("Budgetty").font(.headline).foregroundStyle(Palette.label)
                Button {
                    versionTaps += 1
                    if versionTaps >= 11 {
                        premium = true
                        testerUnlocked = true
                        // Widgets enforce their own cap in another process — tell them too, or a
                        // tester's locked widgets would stay locked.
                        WidgetSharing.premiumDidChange()
                    }
                } label: {
                    Text(testerUnlocked ? "Budgetty 1.0 · Premium unlocked ✓" : "Budgetty 1.0 · Made with 💜")
                        .font(.caption).foregroundStyle(Palette.secondaryLabel)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 40)
            .adaptiveReadableWidth()
        }
        .underFloatingDock(reportingScroll: false)
        .screenCanvas()
        .navigationTitle("Support & About")
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

    /// ⚠️ `url` is optional only because most of this screen's rows have never been wired to
    /// anything — FAQ, Contact us, Suggest a feature, Rate and Share are all still no-ops that draw
    /// an outward arrow. Passing a URL is the fix; see the note on the Terms row for why that one
    /// isn't just a missing string.
    private func link(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color,
                      url: URL? = nil) -> some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, background: tint)
                Text(title).foregroundStyle(Palette.label)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.tertiaryLabel)
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
