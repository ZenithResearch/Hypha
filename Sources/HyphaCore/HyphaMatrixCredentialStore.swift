import Foundation
import Security

public struct HyphaMatrixCredentialDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let username: String
    public let homeserverURL: String

    public init(id: String, username: String, homeserverURL: String) {
        self.id = id
        self.username = username
        self.homeserverURL = homeserverURL
    }
}

public protocol HyphaMatrixCredentialStore: Sendable {
    func credentials() throws -> [HyphaMatrixCredentialDescriptor]
    func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String?
    @discardableResult
    func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor
    func delete(_ credential: HyphaMatrixCredentialDescriptor) throws
    func finalizeAuthenticatedMigration(_ credential: HyphaMatrixCredentialDescriptor) throws
}

public extension HyphaMatrixCredentialStore {
    func finalizeAuthenticatedMigration(_ credential: HyphaMatrixCredentialDescriptor) throws {}
}

protocol HyphaLegacyCredentialMigrationTracking: Sendable {
    func markLegacyCredentialMigrationPending(
        credentialID: String,
        originProcessIdentity: String
    ) throws
    func authorizeLegacyCredentialCleanup(
        credentialID: String,
        verifierProcessIdentity: String
    ) throws -> Bool
}

private enum HyphaCredentialProcessIdentity {
    static let current = UUID().uuidString
}

/// Non-destructively stages legacy per-account Keychain passwords into the
/// encrypted Hypha keystore when an account is actually selected. Legacy
/// records remain available until a separately verified restart cleanup.
public final class HyphaMigratingCredentialStore: HyphaMatrixCredentialStore, @unchecked Sendable {
    private let primary: any HyphaMatrixCredentialStore
    private let legacy: any HyphaMatrixCredentialStore
    private let processIdentity: String
    private let lock = NSRecursiveLock()

    public convenience init(
        primary: any HyphaMatrixCredentialStore,
        legacy: any HyphaMatrixCredentialStore
    ) {
        self.init(
            primary: primary,
            legacy: legacy,
            processIdentity: HyphaCredentialProcessIdentity.current
        )
    }

    init(
        primary: any HyphaMatrixCredentialStore,
        legacy: any HyphaMatrixCredentialStore,
        processIdentity: String
    ) {
        self.primary = primary
        self.legacy = legacy
        self.processIdentity = processIdentity
    }

    public func credentials() throws -> [HyphaMatrixCredentialDescriptor] {
        try synchronized {
            let combined = try primary.credentials() + legacy.credentials()
            var byID: [String: HyphaMatrixCredentialDescriptor] = [:]
            for credential in combined {
                if let existing = byID[credential.id], existing != credential {
                    throw MatrixChatServiceError.recoveryRequired
                }
                byID[credential.id] = credential
            }
            return byID.values.sorted { $0.id < $1.id }
        }
    }

    public func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String? {
        try synchronized {
            if let password = try primary.password(for: credential) {
                if try legacy.credentials().contains(credential) {
                    try markMigrationPendingIfSupported(credentialID: credential.id)
                }
                return password
            }
            guard let password = try legacy.password(for: credential),
                  let homeserver = URL(string: credential.homeserverURL) else { return nil }
            let staged = try primary.savePassword(
                password,
                username: credential.username,
                homeserver: homeserver
            )
            guard staged == credential else { throw MatrixChatServiceError.recoveryRequired }
            try markMigrationPendingIfSupported(credentialID: credential.id)
            return password
        }
    }

    @discardableResult
    public func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor {
        try synchronized {
            let saved = try primary.savePassword(password, username: username, homeserver: homeserver)
            if try legacy.credentials().contains(saved) {
                try markMigrationPendingIfSupported(credentialID: saved.id)
            }
            return saved
        }
    }

    public func finalizeAuthenticatedMigration(_ credential: HyphaMatrixCredentialDescriptor) throws {
        try synchronized {
            guard try primary.password(for: credential) != nil,
                  let tracker = primary as? any HyphaLegacyCredentialMigrationTracking,
                  try tracker.authorizeLegacyCredentialCleanup(
                      credentialID: credential.id,
                      verifierProcessIdentity: processIdentity
                  ) else { return }
            try legacy.delete(credential)
        }
    }

    public func delete(_ credential: HyphaMatrixCredentialDescriptor) throws {
        try synchronized {
            try primary.delete(credential)
            try legacy.delete(credential)
        }
    }

    private func markMigrationPendingIfSupported(credentialID: String) throws {
        guard let tracker = primary as? any HyphaLegacyCredentialMigrationTracking else { return }
        try tracker.markLegacyCredentialMigrationPending(
            credentialID: credentialID,
            originProcessIdentity: processIdentity
        )
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

protocol HyphaPasswordStorage: Sendable {
    func readSecret(service: String, account: String) throws -> Data?
    func writeSecret(
        _ secret: Data,
        service: String,
        account: String,
        label: String,
        description: String,
        metadata: Data
    ) throws
    func delete(service: String, account: String) throws
    func itemMetadata(service: String, accountPrefix: String) throws -> [Data]
}

public final class HyphaMatrixKeychainCredentialStore: HyphaMatrixCredentialStore, @unchecked Sendable {
    private static let service = "Hypha"
    private static let accountPrefix = "matrix-password:"

    private let storage: any HyphaPasswordStorage
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public convenience init() {
        self.init(storage: SecurityHyphaPasswordStorage())
    }

    init(storage: any HyphaPasswordStorage) {
        self.storage = storage
    }

    public func credentials() throws -> [HyphaMatrixCredentialDescriptor] {
        let metadata = try storage.itemMetadata(
            service: Self.service,
            accountPrefix: Self.accountPrefix
        )
        let decoded: [HyphaMatrixCredentialDescriptor]
        do {
            decoded = try metadata.map { try decoder.decode(HyphaMatrixCredentialDescriptor.self, from: $0) }
        } catch {
            throw MatrixChatServiceError.recoveryRequired
        }
        guard Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy(Self.isValidCredential) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return decoded.sorted { $0.id < $1.id }
    }

    public func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String? {
        guard Self.isValidCredential(credential) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        guard let data = try storage.readSecret(
            service: Self.service,
            account: Self.accountPrefix + credential.id
        ) else { return nil }
        guard let password = String(data: data, encoding: .utf8), !password.isEmpty else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return password
    }

    @discardableResult
    public func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty, !password.isEmpty else {
            throw MatrixChatServiceError.invalidCredentials
        }
        let id = MatrixRustSDKChatService.accountKey(
            username: normalizedUsername,
            homeserver: homeserver
        )
        let credential = HyphaMatrixCredentialDescriptor(
            id: id,
            username: normalizedUsername,
            homeserverURL: homeserver.absoluteString
        )
        guard Self.isValidCredential(credential) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        let metadata: Data
        do { metadata = try encoder.encode(credential) }
        catch { throw MatrixChatServiceError.recoveryRequired }
        try storage.writeSecret(
            Data(password.utf8),
            service: Self.service,
            account: Self.accountPrefix + id,
            label: "Hypha Zenith — \(normalizedUsername)",
            description: "Matrix password for \(homeserver.host ?? homeserver.absoluteString)",
            metadata: metadata
        )
        return credential
    }

    public func delete(_ credential: HyphaMatrixCredentialDescriptor) throws {
        guard Self.isValidCredential(credential) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        try storage.delete(
            service: Self.service,
            account: Self.accountPrefix + credential.id
        )
    }

    static func isValidCredential(_ credential: HyphaMatrixCredentialDescriptor) -> Bool {
        guard !credential.id.isEmpty,
              credential.id.utf8.count <= 128,
              !credential.username.isEmpty,
              let homeserver = URL(string: credential.homeserverURL),
              homeserver.scheme?.lowercased() == "https",
              homeserver.host != nil else { return false }
        return MatrixRustSDKChatService.accountKey(
            username: credential.username,
            homeserver: homeserver
        ) == credential.id
    }
}

final class SecurityHyphaPasswordStorage: HyphaPasswordStorage, @unchecked Sendable {
    func readSecret(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to read saved Hypha credentials")
        }
        return data
    }

    func writeSecret(
        _ secret: Data,
        service: String,
        account: String,
        label: String,
        description: String,
        metadata: Data
    ) throws {
        let query = baseQuery(service: service, account: account)
        let values: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrLabel as String: label,
            kSecAttrDescription as String: description,
            kSecAttrGeneric as String: metadata,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to update saved Hypha credentials")
        }
        var item = query
        values.forEach { item[$0.key] = $0.value }
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to save Hypha credentials")
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to delete saved Hypha credentials")
        }
    }

    func itemMetadata(service: String, accountPrefix: String) throws -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to list saved Hypha credentials")
        }
        let dictionaries: [[String: Any]]
        if let values = result as? [[String: Any]] {
            dictionaries = values
        } else if let value = result as? [String: Any] {
            dictionaries = [value]
        } else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return try dictionaries.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(accountPrefix) else { return nil }
            guard let metadata = item[kSecAttrGeneric as String] as? Data else {
                throw MatrixChatServiceError.recoveryRequired
            }
            return metadata
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }
}
