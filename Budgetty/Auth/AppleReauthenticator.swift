//
//  AppleReauthenticator.swift
//  Budgetty
//
//  Runs a one-off Sign in with Apple authorization so account deletion can obtain a fresh
//  authorization code and revoke the user's Apple token (App Review 5.1.1(v)) — Firebase's
//  `user.delete()` alone leaves Budgetty listed under the user's Apple ID. Retains itself and the
//  controller for the lifetime of the request via the continuation.
//

import AuthenticationServices
import UIKit

@MainActor
final class AppleReauthenticator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    // Held for the request's lifetime; ASAuthorizationController is otherwise deallocated the moment
    // `authorize` suspends, before the delegate can fire.
    private var controller: ASAuthorizationController?

    /// Presents the Apple sheet and returns its credential. `nonceSHA256` is the hashed nonce whose
    /// raw value the caller keeps, exactly as the sign-in path does, so Firebase can verify the token.
    func authorize(nonceSHA256: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonceSHA256
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
        }
        continuation = nil
        self.controller = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.controller = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
