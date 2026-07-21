//
//  UserStore.swift
//  Budgetty
//
//  Android's `UserDatabaseManager`, ported. Every signed-in Firebase user gets their own SwiftData
//  store file, so two accounts sharing a device never see each other's receipts; signed-out access
//  reads an empty scratch store instead.
//
//  Containers are cached per file and stay open across account switches: sign-out tears the UI down
//  asynchronously, so a straggling view may still hold the previous context, and closing it under
//  them buys nothing (at most a couple of accounts are ever open on a real device). The one teardown
//  path is `deleteData(for:)` — the account-deletion wipe.
//

import Foundation
import SwiftData

@MainActor
enum UserStore {
    /// Every persisted model. Declared once so the per-account containers can't drift apart.
    static let models: [any PersistentModel.Type] = [
        LineItem.self, Receipt.self, Category.self, Budget.self, Recurring.self, CategoryRule.self,
    ]

    private static var containers: [String: ModelContainer] = [:]

    /// The signed-in user's store; an empty scratch store when signed out.
    static func container(for uid: String?) -> ModelContainer {
        let name = fileName(for: uid)
        if let cached = containers[name] { return cached }

        if uid != nil { adoptLegacyStore(into: name) }
        let configuration = ModelConfiguration(url: storeURL(name))
        do {
            let container = try ModelContainer(
                for: Schema(models), configurations: configuration
            )
            containers[name] = container
            return container
        } catch {
            // Matches the previous single-container behaviour: without a store there is no app.
            fatalError("Failed to create ModelContainer for \(name): \(error)")
        }
    }

    /// Irreversibly deletes `uid`'s store — the account-deletion wipe. Drops the cached container
    /// first so nothing writes the file back out from memory.
    static func deleteData(for uid: String) {
        let name = fileName(for: uid)
        containers[name] = nil
        let url = storeURL(name)
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    // MARK: - Files

    /// "budgetty-u-<uid>.store" per account; a scratch file for signed-out access.
    private static func fileName(for uid: String?) -> String {
        uid.map { "budgetty-u-\($0).store" } ?? "budgetty-anon.store"
    }

    private static func storeURL(_ name: String) -> URL {
        URL.applicationSupportDirectory.appending(path: name)
    }

    /// Adopts the pre-account-separation store: the first signed-in account to open its store after
    /// this update takes the legacy file over — in practice whoever was signed in when the update
    /// installed, i.e. the data's owner. `default.store` is the name SwiftData gives a container
    /// created without an explicit configuration, which is what every build before this one used.
    /// The WAL sidecars move too, so un-checkpointed writes survive.
    private static func adoptLegacyStore(into targetName: String) {
        let fm = FileManager.default
        let legacy = storeURL("default.store")
        guard fm.fileExists(atPath: legacy.path) else { return }
        let target = storeURL(targetName)
        guard !fm.fileExists(atPath: target.path) else { return }

        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            try? fm.moveItem(at: from, to: URL(fileURLWithPath: target.path + suffix))
        }
    }
}
