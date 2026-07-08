//
//  AuthService.swift
//  Budgetty
//
//  Auth abstraction. The receipt-extract endpoint needs a Firebase ID token; this protocol lets the
//  rest of the app depend on "give me a token" without importing FirebaseAuth. When the Firebase SDK
//  + GoogleService-Info.plist land, add a `FirebaseTokenProvider` conforming to this and swap it in
//  `AppServices` — nothing else changes.
//

import Foundation

protocol TokenProvider {
    /// A fresh Firebase ID token, or throws if not available / not configured.
    func idToken() async throws -> String
}

enum AuthError: LocalizedError {
    case notConfigured
    var errorDescription: String? {
        "Sign-in isn't set up yet (Firebase not configured on this build)."
    }
}

/// Placeholder used until the Firebase SDK is wired. Always throws, so the real API call fails fast
/// with a clear message rather than sending an invalid token.
struct UnconfiguredTokenProvider: TokenProvider {
    func idToken() async throws -> String { throw AuthError.notConfigured }
}
