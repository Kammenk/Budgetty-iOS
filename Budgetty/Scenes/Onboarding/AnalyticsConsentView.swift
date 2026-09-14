//
//  AnalyticsConsentView.swift
//  Budgetty
//
//  First-run telemetry consent gate (opt-in). Shown once — after onboarding, auth and the setup
//  quiz, immediately before RootView (see `BudgettyApp`) — until the user decides. Both toggles start
//  OFF and are deliberately LOCAL state, never seeded from stored preferences, so the screen can
//  never present a pre-ticked opt-in. Continue applies whatever the two switches are set to; Not now
//  is the express "don't share" path (both off). Either choice writes the two prefs, pushes them
//  straight to the SDKs, and sets `analyticsConsentDecided`, which recomposes the app past this gate.
//  Android parity: `AnalyticsConsentScreen`. Liquid Glass idioms match `ScanConsentSheet` /
//  `OnboardingView` (grouped-background canvas, glass content cards, the signature `ctaPill`).
//

import SwiftUI

struct AnalyticsConsentView: View {
    /// Persisted telemetry choices (device-global, opt-in). Written on Continue / Not now — never read
    /// to seed the toggles below.
    @AppStorage(SettingsKey.analytics) private var analyticsPref = false
    @AppStorage(SettingsKey.crashReporting) private var crashPref = false
    /// The gate flag. Flipping it recomposes `BudgettyApp` past this screen.
    @AppStorage(SettingsKey.analyticsConsentDecided) private var decided = false

    // Local, never seeded from stored settings — the screen must never present a pre-ticked opt-in.
    @State private var analyticsOn = false
    @State private var crashOn = false
    @State private var detailExpanded = false

    /// Indigo / orange icon-tile hues, matching the mockup (and the Account row glyphs).
    private let analyticsTile = Color(argb: 0xFF5856D6)
    private let crashTile = Color(argb: 0xFFFF9500)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                    .padding(.bottom, 4)
                togglesCard
                collectAndNeverCard
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { footer }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.tint)
                .frame(width: 76, height: 76)
                .overlay(
                    Image(systemName: "receipt")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: Palette.tint.opacity(0.35), radius: 12, y: 6)
            Text("Help improve Budgetty")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Palette.label)
                .multilineTextAlignment(.center)
            Text("Two things you can share, if you want to. Both are off until you turn them on.")
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.top, 8)
    }

    // MARK: - Toggle card

    private var togglesCard: some View {
        VStack(spacing: 0) {
            toggleRow(
                isOn: $analyticsOn,
                icon: "chart.bar.fill",
                tile: analyticsTile,
                title: "Usage analytics",
                subtitle: "Anonymous data about which features you use, so we can improve Budgetty. Never your receipts, amounts, or personal info."
            )
            Rectangle().fill(Palette.separator).frame(height: 0.5)
                .padding(.leading, 66)
            toggleRow(
                isOn: $crashOn,
                icon: "exclamationmark.triangle.fill",
                tile: crashTile,
                title: "Crash & diagnostics",
                subtitle: "Automatic crash reports and performance data so we can fix problems faster."
            )
        }
        .contentCard(cornerRadius: 18)
    }

    private func toggleRow(isOn: Binding<Bool>, icon: String, tile: Color,
                           title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tile)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.label)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Palette.good)
        .padding(16)
    }

    // MARK: - "What we collect, and never"

    private var collectAndNeverCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { detailExpanded.toggle() }
            } label: {
                HStack {
                    Text("What we collect, and never")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Palette.label)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondaryLabel)
                        .rotationEffect(.degrees(detailExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if detailExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        detailColumn(header: "Collected", tint: Palette.good, glyph: "checkmark",
                                     items: ["Which screens you open", "Which features you use",
                                             "Crash reports", "App speed and errors",
                                             "Device model, OS version"])
                        detailColumn(header: "Never", tint: Palette.bad, glyph: "xmark",
                                     items: ["Your receipts", "Any amounts", "Your income",
                                             "Your categories", "Your identity"])
                    }
                    Text("Reports are tied to a random ID, not to you or your account, and you can turn either one off at any time in Settings.")
                        .font(.caption2)
                        .foregroundStyle(Palette.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .contentCard(cornerRadius: 16)
    }

    private func detailColumn(header: LocalizedStringKey, tint: Color, glyph: String,
                              items: [LocalizedStringKey]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(header)
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .kerning(0.6)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item)
                    .font(.caption)
                    .foregroundStyle(Palette.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            reassuranceBand
            Link("Privacy Policy", destination: Legal.privacyPolicy)
                .font(.subheadline)
                .foregroundStyle(Palette.tint)
            Button(action: accept) {
                Text("Continue").font(.headline).ctaPill(height: 54)
            }
            Button("Not now", action: decline)
                .font(.subheadline)
                .foregroundStyle(Palette.tint)
        }
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .background(.bar)
    }

    private var reassuranceBand: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.tint)
            Text("No financial data ever leaves your device.")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(Palette.tint)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.tintSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Actions

    /// Continue: apply whatever the two switches are set to, push to the SDKs immediately, then record
    /// the decision (which dismisses the gate).
    private func accept() {
        analyticsPref = analyticsOn
        crashPref = crashOn
        Analytics.setEnabled(analyticsOn)
        CrashReporting.setEnabled(crashOn)
        decided = true
    }

    /// Not now: the express opt-out — force both off regardless of the switches, apply, record.
    private func decline() {
        analyticsPref = false
        crashPref = false
        Analytics.setEnabled(false)
        CrashReporting.setEnabled(false)
        decided = true
    }
}

#Preview {
    AnalyticsConsentView()
}
