#!/usr/bin/env swift
import AppKit
import Foundation
import Security

private let legacyBundleID = ["ca", "zenithresearch", "mobile", "macos"].joined(separator: ".")
private let renamedBundleID = "ca.zenithresearch.macos.client"
private let legacyService = ["ca", "zenith-research", "mobile-macos", "matrix"].joined(separator: ".")
private let renamedService = "ca.zenithresearch.macos.client.matrix"
private let legacyDefaultsKey = ["ca", "zenith-research", "mobile-macos", "matrix", "homeserver"].joined(separator: ".")
private let renamedDefaultsKey = "ca.zenithresearch.macos.client.matrix.homeserver"

private func fail(_ message: String) -> Never {
    fputs("Migration failed: \(message)\n", stderr)
    exit(1)
}

for bundleID in [legacyBundleID, renamedBundleID] where !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
    fail("quit both the legacy and renamed clients before running this tool")
}

let manager = FileManager.default
let home = manager.homeDirectoryForCurrentUser
let containers = home.appendingPathComponent("Library/Containers", isDirectory: true)
let legacyLibrary = containers
    .appendingPathComponent(legacyBundleID, isDirectory: true)
    .appendingPathComponent("Data/Library", isDirectory: true)
let renamedLibrary = containers
    .appendingPathComponent(renamedBundleID, isDirectory: true)
    .appendingPathComponent("Data/Library", isDirectory: true)
let legacyStore = legacyLibrary
    .appendingPathComponent("Application Support", isDirectory: true)
    .appendingPathComponent(["Zenith", "Mobile", "MacOS"].joined(), isDirectory: true)
    .appendingPathComponent("Matrix", isDirectory: true)
let renamedStore = renamedLibrary
    .appendingPathComponent("Application Support/ZenithMacOSClient/Matrix", isDirectory: true)

if manager.fileExists(atPath: legacyStore.path), !manager.fileExists(atPath: renamedStore.path) {
    do {
        try manager.createDirectory(at: renamedStore.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: legacyStore, to: renamedStore)
    } catch {
        fail("unable to copy the encrypted Matrix store")
    }
}
print("ENCRYPTED_STORE_READY=\(manager.fileExists(atPath: renamedStore.path))")

let legacyPreferences = legacyLibrary
    .appendingPathComponent("Preferences", isDirectory: true)
    .appendingPathComponent("\(legacyBundleID).plist")
let renamedPreferences = renamedLibrary
    .appendingPathComponent("Preferences", isDirectory: true)
    .appendingPathComponent("\(renamedBundleID).plist")
if let legacyDictionary = NSDictionary(contentsOf: legacyPreferences) as? [String: Any],
   let homeserver = legacyDictionary[legacyDefaultsKey] as? String,
   !homeserver.isEmpty {
    var renamedDictionary = (NSDictionary(contentsOf: renamedPreferences) as? [String: Any]) ?? [:]
    renamedDictionary[renamedDefaultsKey] = homeserver
    do {
        try manager.createDirectory(at: renamedPreferences.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: renamedDictionary, format: .binary, options: 0)
        try data.write(to: renamedPreferences, options: .atomic)
    } catch {
        fail("unable to migrate the homeserver preference")
    }
}
print("HOMESERVER_PREFERENCE_READY=\(manager.fileExists(atPath: renamedPreferences.path))")

let attributeQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: legacyService,
    kSecMatchLimit as String: kSecMatchLimitAll,
    kSecReturnAttributes as String: true,
]
var attributeResult: CFTypeRef?
let attributeStatus = SecItemCopyMatching(attributeQuery as CFDictionary, &attributeResult)
if attributeStatus != errSecSuccess && attributeStatus != errSecItemNotFound {
    fail("unable to enumerate legacy Keychain items (status \(attributeStatus))")
}
let items = (attributeResult as? [[String: Any]]) ?? []
var migratedItems = 0
for item in items {
    guard let account = item[kSecAttrAccount as String] as? String else {
        fail("legacy Keychain metadata is incomplete")
    }
    let sourceQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: legacyService,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var sourceResult: CFTypeRef?
    guard SecItemCopyMatching(sourceQuery as CFDictionary, &sourceResult) == errSecSuccess,
          let secretData = sourceResult as? Data else {
        fail("unable to read a legacy Keychain item")
    }
    let destinationQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: renamedService,
        kSecAttrAccount as String: account,
        kSecAttrSynchronizable as String: false,
    ]
    let updateStatus = SecItemUpdate(
        destinationQuery as CFDictionary,
        [kSecValueData as String: secretData] as CFDictionary
    )
    if updateStatus == errSecItemNotFound {
        var addition = destinationQuery
        addition[kSecValueData as String] = secretData
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(addition as CFDictionary, nil) == errSecSuccess else {
            fail("unable to create a renamed Keychain item")
        }
    } else if updateStatus != errSecSuccess {
        fail("unable to update a renamed Keychain item (status \(updateStatus))")
    }
    var verificationQuery = destinationQuery
    verificationQuery[kSecReturnData as String] = true
    verificationQuery[kSecMatchLimit as String] = kSecMatchLimitOne
    var verificationResult: CFTypeRef?
    guard SecItemCopyMatching(verificationQuery as CFDictionary, &verificationResult) == errSecSuccess,
          let verifiedData = verificationResult as? Data,
          verifiedData == secretData else {
        fail("renamed Keychain verification failed")
    }
    migratedItems += 1
}
print("KEYCHAIN_ITEMS_READY=\(migratedItems)")
print("Migration completed without deleting the rollback copy.")
