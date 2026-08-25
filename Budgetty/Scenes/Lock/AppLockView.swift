//
//  AppLockView.swift
//  Budgetty
//
//  App lock — an optional PIN + biometric gate on cold start and on resume after the auto-lock delay
//  (Android's AppLockGate / LockScreen / SetPinScreen). Evolves the old Face-ID-only lock: the PIN is
//  the fallback, biometrics (the existing Face ID setting) an optional shortcut. Free feature.
//

import SwiftUI
import LocalAuthentication

extension EnvironmentValues {
    /// True while the app-lock gate is covering content (cold start locked, or re-locked on resume).
    /// The end-of-period recap interstitial waits for this to clear so it never presents over the lock.
    @Entry var appLocked: Bool = false
}

// MARK: - Gate

struct AppLockGate<Content: View>: View {
    @AppStorage(SettingsKey.appLockEnabled) private var appLockEnabled = false
    @AppStorage(SettingsKey.autoLockMinutes) private var autoLockMinutes = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var locked: Bool
    @State private var backgroundedAt: Date?
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        // A fresh process always locks when the lock is on.
        _locked = State(initialValue: UserDefaults.standard.bool(forKey: SettingsKey.appLockEnabled))
    }

    var body: some View {
        content()
            .environment(\.appLocked, locked && appLockEnabled)
            .overlay {
                if locked && appLockEnabled {
                    LockScreenView { locked = false }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: backgroundedAt = Date()
                case .active:
                    if appLockEnabled, let bg = backgroundedAt {
                        let idle = Date().timeIntervalSince(bg)
                        if autoLockMinutes == 0 || idle >= Double(autoLockMinutes) * 60 { locked = true }
                    }
                default: break
                }
            }
            // Turning the lock off (Account toggle / Forgot PIN) drops the gate so nobody is stranded.
            .onChange(of: appLockEnabled) { _, enabled in if !enabled { locked = false } }
    }
}

// MARK: - Lock screen

struct LockScreenView: View {
    var onUnlocked: () -> Void
    @Environment(AuthModel.self) private var auth
    @AppStorage(SettingsKey.faceID) private var biometricEnabled = false
    @AppStorage(SettingsKey.appLockEnabled) private var appLockEnabled = false
    @State private var entered = ""
    @State private var isError = false
    @State private var errorNonce = 0

    private var showBiometric: Bool { biometricEnabled && BiometricAuth.isAvailable }
    private var biometricAction: (() -> Void)? {
        guard showBiometric else { return nil }
        return authenticate
    }

    var body: some View {
        PinScaffold(
            title: "Budgetty is locked",
            subtitle: "Enter your PIN",
            filled: entered.count, isError: isError, errorNonce: errorNonce,
            errorText: "Wrong PIN. Try again.",
            showError: isError,
            onDigit: onDigit,
            onBackspace: onBackspace,
            onBiometric: biometricAction,
            footer: { forgotButton }
        )
        .onAppear { if showBiometric { authenticate() } }
    }

    private var forgotButton: some View {
        Button("Forgot PIN?") { forgot() }
            .font(.subheadline).foregroundStyle(Palette.tint)
    }
    private func onBackspace() {
        isError = false
        if !entered.isEmpty { entered.removeLast() }
    }

    private func onDigit(_ d: Int) {
        guard entered.count < PinLock.length else { return }
        isError = false
        entered += "\(d)"
        if entered.count == PinLock.length {
            if PinLock.verify(entered) { onUnlocked() }
            else { isError = true; errorNonce += 1; clearAfterShake() }
        }
    }
    private func clearAfterShake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { entered = ""; isError = false }
    }
    private func authenticate() {
        BiometricAuth.authenticate(reason: String(localized: "Unlock Budgetty")) { onUnlocked() }
    }
    /// "Forgot PIN": the user is always signed in, so recovery = disable the lock and sign out to
    /// re-authenticate (Android's forgotPin).
    private func forgot() {
        PinLock.clear(); appLockEnabled = false
        try? auth.signOut()
    }
}

// MARK: - Set / change PIN

struct SetPinView: View {
    @Environment(\.dismiss) private var dismiss
    /// Called after a PIN is set, so the caller can flip the app-lock toggle on.
    var onDone: () -> Void

    @State private var confirming = false
    @State private var firstPin = ""
    @State private var entered = ""
    @State private var isError = false
    @State private var errorNonce = 0

    var body: some View {
        NavigationStack {
            PinScaffold(
                title: confirming ? "Confirm your PIN" : "Set a PIN",
                subtitle: confirming ? "Re-enter your PIN to confirm" : "Choose a 4-digit PIN to lock the app",
                filled: entered.count, isError: isError, errorNonce: errorNonce,
                errorText: "PINs didn't match. Try again.",
                showError: isError,
                onDigit: onDigit,
                onBackspace: { isError = false; if !entered.isEmpty { entered.removeLast() } },
                onBiometric: nil,
                footer: { EmptyView() }
            )
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func onDigit(_ d: Int) {
        guard entered.count < PinLock.length else { return }
        isError = false
        entered += "\(d)"
        guard entered.count == PinLock.length else { return }
        if !confirming {
            firstPin = entered; entered = ""; confirming = true
        } else if entered == firstPin {
            PinLock.setPin(firstPin); onDone(); dismiss()
        } else {
            isError = true; errorNonce += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                confirming = false; firstPin = ""; entered = ""; isError = false
            }
        }
    }
}

// MARK: - Shared scaffold + components

/// The shared lock/set-PIN layout: brand mark, title/subtitle, PIN dots (shaking on error), an error
/// slot, the keypad, and an optional footer.
private struct PinScaffold<Footer: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let filled: Int
    let isError: Bool
    let errorNonce: Int
    let errorText: LocalizedStringKey
    let showError: Bool
    let onDigit: (Int) -> Void
    let onBackspace: () -> Void
    let onBiometric: (() -> Void)?
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LockMark()
            Text(title).font(.title3).fontWeight(.bold).padding(.top, 24)
            Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 32)
            PinDots(filled: filled, isError: isError)
                .modifier(Shake(animatableData: CGFloat(errorNonce)))
                .padding(.top, 28)
            Text(showError ? errorText : " ")
                .font(.caption).foregroundStyle(Palette.bad)
                .frame(height: 34).padding(.top, 6)
            PinKeypad(onDigit: onDigit, onBackspace: onBackspace, onBiometric: onBiometric)
            footer().padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .animation(.default, value: errorNonce)
    }
}

private struct LockMark: View {
    var body: some View {
        Circle().fill(Palette.tintSoft).frame(width: 72, height: 72)
            .overlay(Image(systemName: "lock.fill").font(.system(size: 30)).foregroundStyle(Palette.tint))
    }
}

struct PinDots: View {
    let filled: Int
    var isError = false
    var total = PinLock.length
    var body: some View {
        HStack(spacing: 20) {
            ForEach(0..<total, id: \.self) { i in
                Circle().frame(width: 16, height: 16)
                    .foregroundStyle(i < filled ? (isError ? Palette.bad : Palette.tint) : .clear)
                    .overlay(Circle().strokeBorder(i < filled ? .clear : Palette.tertiaryLabel, lineWidth: 1.5))
            }
        }
    }
}

struct PinKeypad: View {
    let onDigit: (Int) -> Void
    let onBackspace: () -> Void
    let onBiometric: (() -> Void)?
    private let keySize: CGFloat = 72

    var body: some View {
        VStack(spacing: 16) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9]], id: \.first) { row in
                HStack(spacing: 24) { ForEach(row, id: \.self) { digit($0) } }
            }
            HStack(spacing: 24) {
                if let onBiometric {
                    iconKey("faceid", label: "Use Face ID / Touch ID", action: onBiometric)
                } else {
                    Color.clear.frame(width: keySize, height: keySize)
                }
                digit(0)
                iconKey("delete.left", label: "Delete", action: onBackspace)
            }
        }
    }

    private func digit(_ d: Int) -> some View {
        Button { onDigit(d) } label: {
            Text("\(d)").font(.title).fontWeight(.regular).foregroundStyle(Palette.label)
                .frame(width: keySize, height: keySize)
                .background(Palette.fill, in: Circle())
        }
        .buttonStyle(.plain)
    }
    private func iconKey(_ system: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 24)).foregroundStyle(Palette.secondaryLabel)
                .frame(width: keySize, height: keySize).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A horizontal shake keyed on a changing value (wrong PIN).
struct Shake: GeometryEffect {
    var travel: CGFloat = 10
    var shakes: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes), y: 0))
    }
}

// MARK: - Biometrics

enum BiometricAuth {
    static var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    static func authenticate(reason: String, onSuccess: @escaping () -> Void) {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
            if ok { DispatchQueue.main.async(execute: onSuccess) }
        }
    }
}
