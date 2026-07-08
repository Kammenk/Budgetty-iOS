//
//  AuthModel.swift
//  Budgetty
//
//  Observable wrapper around Firebase email/password auth — the same account model as Android (no
//  anonymous sessions). Drives the login gate and the Account profile / sign-out.
//

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
    var email: String { user?.email ?? "" }

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
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func deleteAccount() async throws {
        try await user?.delete()
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
