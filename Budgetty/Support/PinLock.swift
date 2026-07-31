//
//  PinLock.swift
//  Budgetty
//
//  App-lock PIN storage — a per-install salted SHA-256 digest kept in the Keychain (Android's PinHash
//  + SettingsStore PIN methods). The PIN itself is never stored. The lock is a convenience gate, not
//  the app's data-at-rest protection.
//

import Foundation
import CryptoKit
import Security

enum PinLock {
    static let length = 4
    private static let service = "com.budgetty.Budgetty.applock"
    private static let account = "pin-hash"

    static var hasPin: Bool { loadHash() != nil }

    /// Store "saltHex:hashHex" for `pin`.
    static func setPin(_ pin: String) {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        let hash = digest(salt: salt, pin: pin)
        saveHash(hex(salt) + ":" + hex(hash))
    }

    static func verify(_ pin: String) -> Bool {
        guard let stored = loadHash() else { return false }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let salt = bytes(parts[0]) else { return false }
        return constantTimeEquals(hex(digest(salt: salt, pin: pin)), parts[1])
    }

    static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    // MARK: - Hashing

    private static func digest(salt: [UInt8], pin: String) -> [UInt8] {
        var hasher = SHA256()
        hasher.update(data: Data(salt))
        hasher.update(data: Data(pin.utf8))
        return Array(hasher.finalize())
    }
    private static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
    private static func bytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var out: [UInt8] = []; var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            out.append(b); idx = next
        }
        return out
    }
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        for (x, y) in zip(a.utf8, b.utf8) { result |= x ^ y }
        return result == 0
    }

    // MARK: - Keychain

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    private static func saveHash(_ value: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
    private static func loadHash() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
