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

enum FirebaseBootstrap {
    /// Configure Firebase and route extraction through the real backend. Safe to call once at launch.
    @discardableResult
    static func configure() -> Bool {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("[Budgetty] Firebase not configured — GoogleService-Info.plist missing.")
            return false
        }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }

        // Migration: earlier builds used anonymous sessions, which are no longer supported. Sign out
        // any lingering anonymous user so they land on the login screen like Android.
        if Auth.auth().currentUser?.isAnonymous == true { try? Auth.auth().signOut() }

        let provider = FirebaseTokenProvider()
        AppServices.tokenProvider = provider

        // Use the real extractor unless a DEBUG run forces the stub (for offline UI checks).
        #if DEBUG
        let forceStub = ProcessInfo.processInfo.environment["USE_STUB_EXTRACTOR"] == "1"
        #else
        let forceStub = false
        #endif
        if !forceStub {
            AppServices.receiptExtractor = APIReceiptExtractor(tokens: provider)
        }
        return true
    }
}
