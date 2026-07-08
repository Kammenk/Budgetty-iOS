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
        VStack(spacing: 20) {
            Spacer()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Palette.tint)
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "lock.fill").font(.system(size: 38)).foregroundStyle(.white))
            Text("Budgetty is locked").font(.title2).fontWeight(.bold)
            Text("Unlock to view your spending").font(.subheadline).foregroundStyle(Palette.secondaryLabel)
            Spacer()
            Button(action: authenticate) {
                Label("Unlock with Face ID", systemImage: "faceid")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(Palette.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 28).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .onAppear(perform: authenticate)
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
