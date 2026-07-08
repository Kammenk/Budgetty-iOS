//
//  StoreManager.swift
//  Budgetty
//
//  StoreKit 2 subscription handling. Loads the Premium products, runs purchases/restores, and
//  listens for transaction updates. The single source of truth for entitlement is StoreKit
//  (`Transaction.currentEntitlements`); we mirror the result into the `pref.premium` UserDefaults
//  flag that the rest of the app already reads via @AppStorage, OR'd with the tester unlock so the
//  hidden 11-tap tester path keeps working.
//
//  App Store Connect setup (done separately, by the account owner): a subscription group with two
//  auto-renewing products whose IDs match `productIDs` below.
//

import StoreKit
import SwiftUI

@MainActor
@Observable
final class StoreManager {
    /// Must match the product IDs created in App Store Connect (and the local Budgetty.storekit).
    static let yearlyID = "com.budgetty.premium.yearly"
    static let monthlyID = "com.budgetty.premium.monthly"
    static var productIDs: [String] { [yearlyID, monthlyID] }

    private(set) var products: [Product] = []
    private(set) var purchasedIDs: Set<String> = []
    private(set) var loadFailed = false

    /// True when the user holds any active Premium entitlement from StoreKit.
    var isSubscribed: Bool { !purchasedIDs.isEmpty }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = observeTransactionUpdates()
        Task { await load() }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    /// Fetch products and refresh entitlements. Products come back empty on a Simulator that has no
    /// StoreKit configuration selected — the paywall falls back to its static prices in that case.
    func load() async {
        do {
            products = try await Product.products(for: Self.productIDs)
            loadFailed = false
        } catch {
            products = []
            loadFailed = true
        }
        await refreshEntitlements()
    }

    /// Returns true if the purchase completed (verified), false if cancelled/pending.
    @discardableResult
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await refreshEntitlements()
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                owned.insert(transaction.productID)
            }
        }
        purchasedIDs = owned
        syncPremiumFlag()
    }

    /// Mirror entitlement into the app-wide `premium` flag, preserving the tester unlock.
    private func syncPremiumFlag() {
        let tester = UserDefaults.standard.bool(forKey: SettingsKey.testerPremium)
        UserDefaults.standard.set(isSubscribed || tester, forKey: SettingsKey.premium)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? await self.checkVerified(update) {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified: throw StoreError.failedVerification
        }
    }

    enum StoreError: Error { case failedVerification }
}
