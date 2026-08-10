import Foundation

public struct MatrixPlatformStorageIdentity: Equatable, Sendable {
    public let bundleIdentifier: String
    public let keychainService: String
    public let vaultRoot: String
    public let cryptoRoot: String
    public let homeserverDefaultsKey: String
    public let pendingPasswordResetDefaultsKey: String
    public let completedInitialPasswordChangeDefaultsKey: String
    public let loggerSubsystem: String
    public let legacyKeychainService: String?
    public let legacyCryptoRoot: String?
    public let legacyHomeserverDefaultsKey: String?
    public let legacyPendingPasswordResetDefaultsKey: String?
    public let legacyDefaultsSuite: String?

    public var legacyMigrationEnabled: Bool {
        legacyKeychainService != nil || legacyCryptoRoot != nil || legacyHomeserverDefaultsKey != nil
            || legacyPendingPasswordResetDefaultsKey != nil
    }

    public var namespaces: [String] {
        [bundleIdentifier, keychainService, vaultRoot, cryptoRoot, homeserverDefaultsKey, loggerSubsystem]
    }

    public var legacyNamespaces: [String] {
        [legacyKeychainService, legacyCryptoRoot, legacyHomeserverDefaultsKey,
         legacyPendingPasswordResetDefaultsKey, legacyDefaultsSuite].compactMap { $0 }
    }

    public static let macOS = MatrixPlatformStorageIdentity(
        bundleIdentifier: "ca.zenithresearch.macos.client",
        keychainService: "ca.zenithresearch.macos.client.matrix",
        vaultRoot: "ca.zenithresearch.macos.client/MatrixSessionVault-v1",
        cryptoRoot: "ZenithMacOSClient/Matrix",
        homeserverDefaultsKey: "ca.zenithresearch.macos.client.matrix.homeserver",
        pendingPasswordResetDefaultsKey: "ca.zenithresearch.macos.client.pending-initial-password-reset-account-keys",
        completedInitialPasswordChangeDefaultsKey: "ca.zenithresearch.macos.client.completed-initial-password-change-account-keys",
        loggerSubsystem: "ca.zenithresearch.macos.client",
        legacyKeychainService: ["ca", "zenith-research", "mobile-macos", "matrix"].joined(separator: "."),
        legacyCryptoRoot: ["Zenith", "Mobile", "MacOS"].joined() + "/Matrix",
        legacyHomeserverDefaultsKey: ["ca", "zenith-research", "mobile-macos", "matrix", "homeserver"].joined(separator: "."),
        legacyPendingPasswordResetDefaultsKey: "ca.zenithresearch.hypha.pending-initial-password-reset-account-keys",
        legacyDefaultsSuite: ["ca", "zenithresearch", "mobile", "macos"].joined(separator: ".")
    )

    public static let iOS = MatrixPlatformStorageIdentity(
        bundleIdentifier: "ca.zenithresearch.ios.client",
        keychainService: "ca.zenithresearch.ios.client.matrix",
        vaultRoot: "ca.zenithresearch.ios.client/MatrixSessionVault-v1",
        cryptoRoot: "ZenithIOSClient/Matrix",
        homeserverDefaultsKey: "ca.zenithresearch.ios.client.matrix.homeserver",
        pendingPasswordResetDefaultsKey: "ca.zenithresearch.ios.client.pending-initial-password-reset-account-keys",
        completedInitialPasswordChangeDefaultsKey: "ca.zenithresearch.ios.client.completed-initial-password-change-account-keys",
        loggerSubsystem: "ca.zenithresearch.ios.client",
        legacyKeychainService: nil,
        legacyCryptoRoot: nil,
        legacyHomeserverDefaultsKey: nil,
        legacyPendingPasswordResetDefaultsKey: nil,
        legacyDefaultsSuite: nil
    )

    public static var current: MatrixPlatformStorageIdentity {
        #if os(iOS)
        .iOS
        #else
        .macOS
        #endif
    }
}
