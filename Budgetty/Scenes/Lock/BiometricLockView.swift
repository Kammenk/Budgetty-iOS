//
//  BiometricLockView.swift
//  Budgetty
//
//  Face ID app-lock screen + the gate that wraps the app when the Face ID setting is on. Uses
//  LocalAuthentication; auto-prompts on appear.
//

import SwiftUI
import LocalAuthentication

struct BiometricLockView: View {
    var onUnlock: () -> Void
    @State private var failed = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // Brand logo tile (mockup: the receipt glyph on the hero gradient, not a padlock).
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Palette.heroGradient)
                .frame(width: 92, height: 92)
                .overlay(Image(systemName: "doc.text.fill").font(.system(size: 38)).foregroundStyle(.white))
                .shadow(color: Palette.tint.opacity(0.35), radius: 16, y: 8)
                .padding(.bottom, 24)
            Text("Budgetty is locked").font(.title2).fontWeight(.bold)
            Text("Use Face ID to continue")
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel).padding(.top, 6)

            Image(systemName: "faceid")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.top, 56)

            // Neutral dark-glass pill (mockup), not the violet CTA.
            Button(action: authenticate) {
                Text("Unlock with Face ID")
                    .font(.headline).foregroundStyle(Palette.label)
                    .padding(.horizontal, 36).frame(height: 56)
                    .glassControl(cornerRadius: 28)
            }
            .buttonStyle(.plain)
            .padding(.top, 44)

            Spacer()
            Button("Enter Passcode", action: authenticate)
                .font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
        // The lock screen is always dark in the mockup. The app root sets preferredColorScheme from
        // the Appearance setting (which wins over a nested preference), so force the trait directly.
        .environment(\.colorScheme, .dark)
        .onAppear {
            #if DEBUG
            // Screenshot hook shows the lock UI itself — don't cover it with the system prompt.
            if ProcessInfo.processInfo.environment["SHOW_SCREEN"] == "lock" { return }
            #endif
            authenticate()
        }
    }

    private func authenticate() {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onUnlock(); return // no biometrics available (e.g. Simulator) → don't lock the user out
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Budgetty") { success, _ in
            DispatchQueue.main.async {
                if success { onUnlock() } else { failed = true }
            }
        }
    }
}

/// Wraps content and shows the lock screen once per launch when Face ID is enabled.
struct LockGate<Content: View>: View {
    @AppStorage(SettingsKey.faceID) private var faceID = false
    @State private var unlocked = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        if faceID && !unlocked {
            BiometricLockView { unlocked = true }
        } else {
            content()
        }
    }
}
