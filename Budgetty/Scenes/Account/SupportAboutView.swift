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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // One row, because one inbox. "FAQ" pointed at a page that has no FAQ on it — the
                // hosted document is a privacy policy and nothing else — and "Suggest a feature" was
                // a second mail row with a different subject. Android already settled this: a single
                // "Contact us" whose subtitle names all three reasons to write (PARITY.md §4a), which
                // is also why the subject line is neutral.
                sectionHeader("Help")
                VStack(spacing: 0) {
                    link("Contact us", "envelope.fill", Color(argb: 0xFF007AFF),
                         subtitle: "Report an issue, suggest a feature, or just say hello",
                         url: Legal.supportMail)
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                sectionHeader("Legal")
                VStack(spacing: 0) {
                    link("Privacy Policy", "hand.raised.fill", Color(argb: 0xFF34C759),
                         url: Legal.privacyPolicy)
                    divider
                    link("Terms of Service", "doc.text.fill", Color(argb: 0xFF8E8E93),
                         url: Legal.terms)
                }
                .contentCard(cornerRadius: 14)
                .padding(.bottom, 24)

                // ⚠️ BOTH STILL INERT, and not for want of a string: each needs the App Store id,
                // which doesn't exist in this repo and can't until there's a public listing (Rate
                // wants the write-review URL, Share wants the listing URL). Wire them from
                // App Store Connect › App Information › General › Apple ID once the app is live —
                // pointing them anywhere before that just sends people to a 404.
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

    /// ⚠️ `url` stays optional only for Rate and Share, the two rows still blocked on an App Store
    /// id. Every other row on this screen is wired; a row without a URL draws the same outward arrow
    /// and does nothing, so don't add one without a destination.
    private func link(_ title: LocalizedStringKey, _ symbol: String, _ tint: Color,
                      subtitle: LocalizedStringKey? = nil, url: URL? = nil) -> some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 12) {
                SettingsIcon(symbol: symbol, background: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Palette.label)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Palette.secondaryLabel)
                    }
                }
                Spacer()
                // Only where there's something to open. The arrow is the affordance that promises a
                // destination, and Rate/Share have none yet — drawing it anyway is what made this
                // screen feel broken rather than unfinished.
                if url != nil {
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.tertiaryLabel)
                }
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
