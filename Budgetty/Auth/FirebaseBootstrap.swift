//
//  FirebaseBootstrap.swift
//  Budgetty
//
//  The single file that imports Firebase. Configures the SDK, warms up anonymous sign-in, and wires
//  the real token provider + API-backed extractor into `AppServices`. If GoogleService-Info.plist is
//  missing, it no-ops so the app still runs (with the stub extractor on DEBUG).
//

import Foundation
import FirebaseCore
import FirebaseAuth

/// Supplies a fresh Firebase ID token for the signed-in user. Requires a real account (no anonymous
/// sessions — matches Android); throws if nobody is signed in.
struct FirebaseTokenProvider: TokenProvider {
    func idToken() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthError.notConfigured }
        return try await user.getIDToken()
    }
}

/// Account-comp entitlement — the server-granted `premium` custom claim (set by functions/tools/comp.js).
/// This is the friends-unlock mechanism on iOS: read the claim, cache it in `pref.comp`, and let
/// `StoreManager` OR it into Premium. Mirrors Android's `BillingManager.refreshComp`. There is no in-app
/// code field or hidden gesture — nothing for App Store review to flag; the entitlement simply exists on
/// the accounts the owner grants, and because it rides on the account it restores on any device.
enum CompEntitlement {
    /// Re-reads the `premium` claim for the signed-in user into `pref.comp`, forcing a token refresh so
    /// a revoke is picked up. Signed out clears it; a network failure keeps the cached value.
    static func refresh() async {
        guard let user = Auth.auth().currentUser else {
            UserDefaults.standard.set(false, forKey: SettingsKey.comp)
            return
        }
        guard let result = try? await user.getIDTokenResult(forcingRefresh: true) else { return }
        UserDefaults.standard.set((result.claims["premium"] as? Bool) == true, forKey: SettingsKey.comp)
    }
}

enum FirebaseBootstrap {
    /// Configure Firebase and route extraction through the real backend. Safe to call once at launch.
    @discardableResult
    static func configure() -> Bool {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Budgetty] Firebase not configured — GoogleService-Info.plist missing.")
            return false
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        // Point Crashlytics at the user's stored choice immediately after configure(), so collection
        // reflects an opt-out before any code that could crash runs. Default-on — see CrashReporting.
        CrashReporting.applyStoredPreference()
        // Same for product analytics: apply the persisted opt-out (separate toggle, default-on) to the
        // Analytics SDK at startup so collection follows the user's choice before any event fires (§0).
        Analytics.applyStoredPreference()

        // Migration: earlier builds used anonymous sessions, which are no longer supported. Sign out
        // any lingering anonymous user so they land on the login screen like Android.
        if Auth.auth().currentUser?.isAnonymous == true { try? Auth.auth().signOut() }

        let provider = FirebaseTokenProvider()
        AppServices.tokenProvider = provider

        // Use the real extractor unless a DEBUG run forces the stub (for offline UI checks).
        #if DEBUG
        let forceStub = LaunchFlags.isOn("USE_STUB_EXTRACTOR")
        #else
        let forceStub = false
        #endif
        if !forceStub {
            AppServices.receiptExtractor = APIReceiptExtractor(tokens: provider)
        }
        return true
    }
}
