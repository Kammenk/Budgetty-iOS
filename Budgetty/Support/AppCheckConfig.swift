//
//  AppCheckConfig.swift
//  Budgetty
//
//  The one place that touches the Firebase App Check SDK — a sibling of `Analytics` and
//  `CrashReporting`, isolating the `FirebaseAppCheck` import to a single small surface. App Check
//  proves to the shared Firebase backend (`budgetty-96a3d`) that a request comes from a genuine,
//  unmodified build of this app on a real device, so off-app scripts and bots can't hammer Auth,
//  Firestore, Functions or Storage. This is infrastructure hardening — there is NO UI and NO user
//  setting; the client simply attaches an attestation token to Firebase requests.
//
//  ── MONITOR MODE ONLY ──────────────────────────────────────────────────────────────────────────
//  Installing the provider factory only makes the client *mint and attach* App Check tokens; it does
//  NOT enforce anything. Enforcement (rejecting unattested traffic) is a per-service switch in the
//  Firebase console and is intentionally left OFF here, so shipping this is fully non-breaking — the
//  app behaves exactly as before. The plan is to watch the console's "verified vs. unverified"
//  metrics for ~1 week, then enable enforcement per service. Matches the Android hardening effort.
//
//  ── PROVIDER SELECTION ─────────────────────────────────────────────────────────────────────────
//  • Release: `AppAttestProvider` (App Attest — Secure-Enclave-backed, iOS 14+, always available on
//    our iOS 26 deployment target) is the primary provider. `AppAttestProvider(app:)` returns nil on
//    the rare device where App Attest hardware is unavailable, so we fall back to `DeviceCheckProvider`
//    — the Firebase-recommended custom-factory pattern.
//  • DEBUG / simulator: `AppCheckDebugProviderFactory`. The simulator has no App Attest hardware, so a
//    debug build MUST use the debug provider or every attestation fails. The debug provider prints a
//    `FIRAppCheckDebugToken` to the console on first launch; register that token under
//    Firebase console → App Check → apps → Manage debug tokens so debug/simulator builds verify while
//    enforcement is on. See the register steps in the port brief / PR notes.
//
//  Order matters: `installProviderFactory()` MUST run before `FirebaseApp.configure()` (called from
//  `FirebaseBootstrap.configure()`), so the factory is registered when App Check initializes.
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

/// Release-build App Check provider factory: App Attest primary, DeviceCheck fallback.
///
/// App Attest is the modern attestation backed by the Secure Enclave and is available on iOS 14+ —
/// always present on this app's iOS 26 minimum, so no OS `@available` gate is needed. The nullable
/// `AppAttestProvider(app:)` still returns nil when a specific device can't perform App Attest; in
/// that case we hand back `DeviceCheckProvider` so the request is attested by DeviceCheck instead of
/// going unverified. Debug/simulator builds never reach this factory — see `installProviderFactory`.
final class BudgettyAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        // App Attest first; fall back to DeviceCheck only when App Attest is unavailable on the device.
        if let appAttest = AppAttestProvider(app: app) {
            return appAttest
        }
        return DeviceCheckProvider(app: app)
    }
}

enum AppCheckConfig {
    /// Register the App Check provider factory. **Call before `FirebaseApp.configure()`.**
    ///
    /// Monitor mode: this only causes the client to attach App Check tokens; it changes no server or
    /// console enforcement, so it is non-breaking. Enforcement is enabled later, per service, from the
    /// Firebase console once monitor metrics are clean.
    static func installProviderFactory() {
        #if DEBUG
        // Simulator/debug devices can't use App Attest; the debug provider exchanges a debug token
        // (registered in the console) for a valid App Check token so debug traffic verifies too.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(BudgettyAppCheckProviderFactory())
        #endif
    }
}
