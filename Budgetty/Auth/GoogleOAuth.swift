//
//  GoogleOAuth.swift
//  Budgetty
//
//  Google sign-in without the GoogleSignIn SDK: the standard OAuth 2.0 authorization-code flow with
//  PKCE, run through `ASWebAuthenticationSession`. Keeps the project dependency-free and, because
//  ASWebAuthenticationSession intercepts its own `callbackURLScheme`, needs no `CFBundleURLTypes` —
//  which matters here, as the app target has no physical Info.plist (`GENERATE_INFOPLIST_FILE`).
//
//  Only the ID token is used: Firebase mints its own session from it, and Android does the same
//  (`GoogleAuthProvider.getCredential(idToken, null)`), so neither app holds a Google access token.
//
//  iOS OAuth clients are *public* clients — there is no client secret to protect, which is exactly
//  why PKCE exists: the authorization code is useless without the verifier held only by this run.
//

import AuthenticationServices
import CryptoKit
import Foundation

enum GoogleOAuth {
    /// Runs the interactive flow and returns a Google ID token for Firebase to exchange.
    @MainActor
    static func idToken(presentingFrom anchor: ASPresentationAnchor?) async throws -> String {
        let config = try Config.fromBundle()
        let verifier = pkceVerifier()
        let state = pkceVerifier()

        let callback = try await authorize(config: config, verifier: verifier, state: state,
                                           anchor: anchor)
        let code = try authorizationCode(from: callback, expectedState: state)
        return try await exchange(code: code, verifier: verifier, config: config)
    }

    // MARK: - Step 1: the consent screen

    private static func authorize(
        config: Config, verifier: String, state: String, anchor: ASPresentationAnchor?
    ) async throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: config.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        guard let url = components.url else { throw GoogleSignInError.badConfiguration }

        let presenter = Presenter(anchor: anchor)
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: config.callbackScheme
            ) { callbackURL, error in
                // Keep the presenter alive until the callback fires — the session holds it weakly.
                _ = presenter
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    // Dismissing the sheet throws ASWebAuthenticationSessionError.canceledLogin,
                    // whose localizedDescription is the useless "The operation couldn't be
                    // completed. (…WebAuthenticationSession error 1.)". Normalise transport errors
                    // here so callers only ever see a GoogleSignInError.
                    continuation.resume(throwing: Self.normalised(error))
                }
            }
            session.presentationContextProvider = presenter
            // Deliberately NOT ephemeral: reusing the browser's Google session is the whole point of
            // "continue with Google" — an ephemeral one would demand a password every time.
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() { continuation.resume(throwing: GoogleSignInError.cannotPresent) }
        }
    }

    private static func normalised(_ error: Error?) -> GoogleSignInError {
        guard let error else { return .noCallback }
        if let sessionError = error as? ASWebAuthenticationSessionError,
           sessionError.code == .canceledLogin {
            return .cancelled
        }
        return .noCallback
    }

    /// Pulls `code` out of the redirect, rejecting a reply that doesn't match the `state` we sent.
    private static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw error == "access_denied" ? GoogleSignInError.cancelled
                                           : GoogleSignInError.provider(error)
        }
        guard value("state") == expectedState else { throw GoogleSignInError.stateMismatch }
        guard let code = value("code") else { throw GoogleSignInError.noCallback }
        return code
    }

    // MARK: - Step 2: code → ID token

    private static func exchange(code: String, verifier: String, config: Config) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form([
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String
        else { throw GoogleSignInError.tokenExchangeFailed }
        return idToken
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    // MARK: - PKCE

    /// High-entropy verifier, base64url with no padding (RFC 7636 §4.1).
    private static func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Config

    /// The OAuth client, read from the same GoogleService-Info.plist Firebase uses.
    private struct Config {
        let clientID: String
        /// Google's iOS convention: the reversed client id as a private-use scheme.
        var callbackScheme: String { reversedClientID }
        var redirectURI: String { "\(reversedClientID):/oauth2redirect" }
        private let reversedClientID: String

        static func fromBundle() throws -> Config {
            guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let plist = NSDictionary(contentsOfFile: path),
                  let clientID = plist["CLIENT_ID"] as? String,
                  let reversed = plist["REVERSED_CLIENT_ID"] as? String
            else { throw GoogleSignInError.badConfiguration }
            return Config(clientID: clientID, reversedClientID: reversed)
        }
    }

    /// `ASWebAuthenticationSession` asks what to present over; it holds this weakly.
    private final class Presenter: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor?
        init(anchor: ASPresentationAnchor?) { self.anchor = anchor }
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor ?? ASPresentationAnchor()
        }
    }
}

enum GoogleSignInError: LocalizedError {
    case badConfiguration
    case cancelled
    case cannotPresent
    case noCallback
    case stateMismatch
    case provider(String)
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .badConfiguration:
            "Google sign-in isn't configured for this build."
        case .cancelled:
            nil // the user backed out
        case .cannotPresent, .noCallback:
            "Google sign-in didn't complete. Please try again."
        case .stateMismatch:
            "Google sign-in failed a security check. Please try again."
        case .provider(let code):
            "Google refused the sign-in (\(code))."
        case .tokenExchangeFailed:
            "Couldn't finish signing in with Google. Please try again."
        }
    }
}
