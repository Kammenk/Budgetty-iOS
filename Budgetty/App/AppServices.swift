//
//  AppServices.swift
//  Budgetty
//
//  Tiny composition root. Holds the shared auth token provider and receipt extractor so views don't
//  construct their own. When the Firebase SDK + GoogleService-Info.plist land, set `tokenProvider` to
//  a `FirebaseTokenProvider` in BudgettyApp — the extractor picks it up automatically.
//

import Foundation

enum AppServices {
    /// Supplies Firebase ID tokens. Replaced with a real Firebase-backed provider once the SDK is in.
    static var tokenProvider: TokenProvider = UnconfiguredTokenProvider()

    /// Turns a receipt image into an editable draft. Stub on DEBUG so the flow works on the Simulator
    /// (no camera / no Firebase token); real API-backed extractor in release.
    static var receiptExtractor: ReceiptExtractor = {
        #if DEBUG
        return StubReceiptExtractor()
        #else
        return APIReceiptExtractor(tokens: tokenProvider)
        #endif
    }()
}
