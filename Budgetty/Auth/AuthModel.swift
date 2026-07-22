//
//  AuthModel.swift
//  Budgetty
//
//  Observable wrapper around Firebase auth — email/password plus Sign in with Apple. No anonymous
//  sessions, matching Android. Drives the login gate and the Account profile / sign-out.
//
//  Third-party providers: Apple (native AuthenticationServices) and Google (native OAuth + PKCE,
//  see GoogleOAuth — no SDK). App Review 4.8 requires Apple wherever Google is offered.
//

import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
@Observable
final class AuthModel {
    private(set) var user: User?
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        user = Auth.auth().currentUser
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            self?.user = u
        }
    }

    var isSignedIn: Bool { user != nil }

    /// Firebase uid of the signed-in account; nil when signed out. Keys the per-account
    /// local store (see `UserStore`) so callers don't need FirebaseAuth themselves.
    var uid: String? { user?.uid }
    /// The signed-in account's address.
    ///
    /// `DEMO_EMAIL` substitutes a stand-in when there is no Firebase user, which is the case under
    /// `SKIP_AUTH`. Without it `email` is empty, `initials` falls back to "?", and the avatar renders
    /// a question mark — invisible in a debug run, but wrong in an App Store screenshot. DEBUG only,
    /// and it never overrides a real session, so it can't mask who is actually signed in.
    var email: String {
        #if DEBUG
        if user == nil, let demo = LaunchFlags.value("DEMO_EMAIL") { return demo }
        #endif
        return user?.email ?? ""
    }

    /// Up to two initials from the email local part (e.g. "alex.rivera@…" → "AR").
    var initials: String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        let parts = local.split(whereSeparator: { ".-_ ".contains($0) }).filter { !$0.isEmpty }
        let names: [String] = parts.count >= 2 ? [String(parts[0]), String(parts[1])] : [local]
        let letters = names.compactMap { $0.first }
        let s = String(letters.prefix(2)).uppercased()
        return s.isEmpty ? "?" : s
    }

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
        armSetupQuiz()
    }

    // MARK: - Sign in with Apple

    /// The raw nonce for the in-flight Apple request. Apple signs the SHA-256 of it into the identity
    /// token; Firebase re-hashes the raw value to prove the token was minted for *this* request, so
    /// it has to survive from `prepareAppleRequest` until the credential exchange.
    private var appleNonce: String?

    /// Configures the request the `SignInWithAppleButton` is about to make.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Exchanges an Apple credential for a Firebase session.
    ///
    /// Apple returns the name and email **only on the very first authorisation** for an app, so a
    /// new account's display name has to be taken here or not at all — a second run returns nils
    /// even after deleting the Firebase user (revoke it in Settings › Apple Account to retest).
    func signInWithApple(_ authorization: ASAuthorization) async throws {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8)
        else { throw AppleSignInError.missingIdentityToken }
        guard let nonce = appleNonce else { throw AppleSignInError.missingNonce }
        appleNonce = nil

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken, rawNonce: nonce, fullName: credential.fullName
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)

        // Android arms the setup quiz for third-party sign-UPS too, not just email (`e328102`) —
        // `isNewUser` is the only way to tell a first authorisation from a returning one.
        if result.additionalUserInfo?.isNewUser == true {
            armSetupQuiz()
            if let name = credential.fullName, let display = PersonNameComponentsFormatter()
                .string(from: name).nilIfBlank {
                let change = result.user.createProfileChangeRequest()
                change.displayName = display
                try? await change.commitChanges()
            }
        }
    }

    // MARK: - Sign in with Google

    /// Runs the Google consent flow and exchanges the resulting ID token for a Firebase session.
    /// Mirrors Android, which also passes the ID token alone
    /// (`GoogleAuthProvider.getCredential(idToken, null)`) and arms the quiz off `isNewUser`.
    func signInWithGoogle(presentingFrom anchor: ASPresentationAnchor?) async throws {
        let idToken = try await GoogleOAuth.idToken(presentingFrom: anchor)
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: "")
        let result = try await Auth.auth().signIn(with: credential)
        if result.additionalUserInfo?.isNewUser == true { armSetupQuiz() }
    }

    /// Arms the one-time post-signup Insights setup quiz (skipped for returning sign-ins).
    private func armSetupQuiz() {
        UserDefaults.standard.set(true, forKey: SettingsKey.quizPending)
    }

    /// Cryptographically random nonce; the character set is Apple's from their sample.
    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset[Int.random(in: 0..<charset.count)] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func deleteAccount() async throws {
        // Captured first: once the Firebase user is gone there is no uid left to find its store by.
        let uid = user?.uid
        try await user?.delete()
        // The lifetime free-scan counter and the rating-prompt history clear only on account
        // deletion (Android parity).
        ScanQuota.reset()
        ReviewGate.reset()
        // Wipe this account's local receipts too — the store outlives the Firebase user otherwise,
        // and a later account could adopt the file (Android `deleteDataFor`).
        if let uid { UserStore.deleteData(for: uid) }
    }
}

/// Simple password strength for the sign-up meter.
enum PasswordStrength: Int {
    case none = 0, weak = 1, fair = 2, strong = 4

    static func of(_ password: String) -> PasswordStrength {
        if password.isEmpty { return .none }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { score += 1 }
        if password.rangeOfCharacter(from: CharacterSet.punctuationCharacters.union(.symbols)) != nil { score += 1 }
        if password.count >= 12 { score += 1 }
        switch score {
        case 0, 1: return password.count >= 6 ? .fair : .weak
        case 2, 3: return .fair
        default: return .strong
        }
    }

    var bars: Int { self == .strong ? 4 : rawValue }
    var label: String {
        switch self {
        case .none: "Enter a password"
        case .weak: "Weak — add numbers & symbols"
        case .fair: "Fair — try a longer password"
        case .strong: "Strong password ✓"
        }
    }
    var color: Color {
        switch self {
        case .none: Palette.fill
        case .weak: Palette.bad
        case .fair: Palette.warn
        case .strong: Palette.good
        }
    }
}

/// Failure modes of the Apple exchange that aren't Firebase's to report.
enum AppleSignInError: LocalizedError {
    case missingIdentityToken
    case missingNonce

    var errorDescription: String? {
        switch self {
        case .missingIdentityToken: "Apple didn't return an identity token. Please try again."
        case .missingNonce: "That sign-in request expired. Please try again."
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
