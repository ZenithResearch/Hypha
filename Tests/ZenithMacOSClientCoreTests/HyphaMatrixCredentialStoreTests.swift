import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class HyphaMatrixCredentialStoreTests: XCTestCase {
    func testMigratingStoreStagesSelectedLegacyPasswordWithoutDeletingLegacyRecord() throws {
        let primary = MemoryCredentialStore()
        let legacy = MemoryCredentialStore()
        let homeserver = URL(string: "https://matrix.example.org")!
        let credential = try legacy.savePassword(
            "legacy-password",
            username: "peachpraline",
            homeserver: homeserver
        )
        let store = HyphaMigratingCredentialStore(primary: primary, legacy: legacy)

        XCTAssertEqual(try store.credentials(), [credential])
        XCTAssertEqual(try store.password(for: credential), "legacy-password")
        XCTAssertEqual(try primary.password(for: credential), "legacy-password")
        XCTAssertEqual(try legacy.password(for: credential), "legacy-password")
    }

    func testAuthenticatedCredentialCleanupRequiresAProcessAfterTheStagingProcess() throws {
        let primary = TrackingMemoryCredentialStore()
        let legacy = MemoryCredentialStore()
        let homeserver = URL(string: "https://matrix.example.org")!
        let credential = try legacy.savePassword(
            "legacy-password",
            username: "peachpraline",
            homeserver: homeserver
        )
        _ = try primary.savePassword(
            "legacy-password",
            username: credential.username,
            homeserver: homeserver
        )
        let stagingProcess = HyphaMigratingCredentialStore(
            primary: primary,
            legacy: legacy,
            processIdentity: "staging-process"
        )

        XCTAssertEqual(try stagingProcess.password(for: credential), "legacy-password")
        try stagingProcess.finalizeAuthenticatedMigration(credential)
        XCTAssertEqual(try legacy.password(for: credential), "legacy-password")

        let restartedProcess = HyphaMigratingCredentialStore(
            primary: primary,
            legacy: legacy,
            processIdentity: "restarted-process"
        )
        try restartedProcess.finalizeAuthenticatedMigration(credential)

        XCTAssertEqual(try primary.password(for: credential), "legacy-password")
        XCTAssertNil(try legacy.password(for: credential))
    }

    func testPasswordIsStoredUnderHumanReadableHyphaServiceAndUsernameDescriptor() throws {
        let storage = MemoryHyphaPasswordStorage()
        let store = HyphaMatrixKeychainCredentialStore(storage: storage)

        let credential = try store.savePassword(
            "correct horse battery staple",
            username: "peachpraline",
            homeserver: URL(string: "https://matrix.example.org")!
        )

        XCTAssertEqual(storage.lastWrite?.service, "Hypha")
        XCTAssertEqual(storage.lastWrite?.label, "Hypha Zenith — peachpraline")
        XCTAssertEqual(storage.lastWrite?.secret, Data("correct horse battery staple".utf8))
        XCTAssertTrue(storage.lastWrite?.account.hasPrefix("matrix-password:") == true)
        XCTAssertEqual(try store.password(for: credential), "correct horse battery staple")
        XCTAssertEqual(try store.credentials(), [credential])
    }

    func testSameUsernameOnDifferentHomeserversProducesDistinctCredentials() throws {
        let storage = MemoryHyphaPasswordStorage()
        let store = HyphaMatrixKeychainCredentialStore(storage: storage)
        let first = try store.savePassword(
            "first-password",
            username: "alice",
            homeserver: URL(string: "https://one.example.org")!
        )
        let second = try store.savePassword(
            "second-password",
            username: "alice",
            homeserver: URL(string: "https://two.example.org")!
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.credentials(), [first, second].sorted { $0.id < $1.id })
        XCTAssertEqual(try store.password(for: first), "first-password")
        XCTAssertEqual(try store.password(for: second), "second-password")
    }

    func testSavingAgainReplacesOnlyThatUsernamePassword() throws {
        let storage = MemoryHyphaPasswordStorage()
        let store = HyphaMatrixKeychainCredentialStore(storage: storage)
        let homeserver = URL(string: "https://matrix.example.org")!
        let alice = try store.savePassword("old", username: "alice", homeserver: homeserver)
        let bob = try store.savePassword("bob-password", username: "bob", homeserver: homeserver)

        _ = try store.savePassword("new", username: "alice", homeserver: homeserver)

        XCTAssertEqual(try store.password(for: alice), "new")
        XCTAssertEqual(try store.password(for: bob), "bob-password")
        XCTAssertEqual(try store.credentials().count, 2)
    }

    func testDeleteRemovesOnlySelectedCredential() throws {
        let storage = MemoryHyphaPasswordStorage()
        let store = HyphaMatrixKeychainCredentialStore(storage: storage)
        let homeserver = URL(string: "https://matrix.example.org")!
        let alice = try store.savePassword("alice-password", username: "alice", homeserver: homeserver)
        let bob = try store.savePassword("bob-password", username: "bob", homeserver: homeserver)

        try store.delete(alice)

        XCTAssertNil(try store.password(for: alice))
        XCTAssertEqual(try store.password(for: bob), "bob-password")
        XCTAssertEqual(try store.credentials(), [bob])
    }

    func testEmptyUsernameOrPasswordFailsClosed() throws {
        let store = HyphaMatrixKeychainCredentialStore(storage: MemoryHyphaPasswordStorage())
        let homeserver = URL(string: "https://matrix.example.org")!

        XCTAssertThrowsError(try store.savePassword("", username: "alice", homeserver: homeserver))
        XCTAssertThrowsError(try store.savePassword("password", username: "", homeserver: homeserver))
    }
}

private final class MemoryCredentialStore: HyphaMatrixCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: (HyphaMatrixCredentialDescriptor, String)] = [:]

    func credentials() throws -> [HyphaMatrixCredentialDescriptor] {
        lock.withLock { values.values.map(\.0).sorted { $0.id < $1.id } }
    }

    func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String? {
        lock.withLock { values[credential.id]?.1 }
    }

    @discardableResult
    func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor {
        let credential = HyphaMatrixCredentialDescriptor(
            id: MatrixRustSDKChatService.accountKey(username: username, homeserver: homeserver),
            username: username,
            homeserverURL: homeserver.absoluteString
        )
        lock.withLock { values[credential.id] = (credential, password) }
        return credential
    }

    func delete(_ credential: HyphaMatrixCredentialDescriptor) throws {
        _ = lock.withLock { values.removeValue(forKey: credential.id) }
    }
}

private final class TrackingMemoryCredentialStore: HyphaMatrixCredentialStore, HyphaLegacyCredentialMigrationTracking, @unchecked Sendable {
    private let backing = MemoryCredentialStore()
    private let lock = NSLock()
    private var migrations: [String: (origin: String, verified: String?)] = [:]

    func credentials() throws -> [HyphaMatrixCredentialDescriptor] { try backing.credentials() }
    func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String? {
        try backing.password(for: credential)
    }
    @discardableResult
    func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor {
        try backing.savePassword(password, username: username, homeserver: homeserver)
    }
    func delete(_ credential: HyphaMatrixCredentialDescriptor) throws { try backing.delete(credential) }

    func markLegacyCredentialMigrationPending(credentialID: String, originProcessIdentity: String) throws {
        lock.withLock {
            if migrations[credentialID] == nil {
                migrations[credentialID] = (originProcessIdentity, nil)
            }
        }
    }

    func authorizeLegacyCredentialCleanup(credentialID: String, verifierProcessIdentity: String) throws -> Bool {
        lock.withLock {
            guard var migration = migrations[credentialID] else { return false }
            if migration.verified == nil {
                guard migration.origin != verifierProcessIdentity else { return false }
                migration.verified = verifierProcessIdentity
                migrations[credentialID] = migration
            }
            return true
        }
    }
}

private final class MemoryHyphaPasswordStorage: HyphaPasswordStorage, @unchecked Sendable {
    struct Write {
        let service: String
        let account: String
        let label: String
        let description: String
        let metadata: Data
        let secret: Data
    }

    private let lock = NSLock()
    private var values: [String: Write] = [:]
    private(set) var lastWrite: Write?

    func readSecret(service: String, account: String) throws -> Data? {
        lock.withLock { values["\(service)|\(account)"]?.secret }
    }

    func writeSecret(
        _ secret: Data,
        service: String,
        account: String,
        label: String,
        description: String,
        metadata: Data
    ) throws {
        lock.withLock {
            let write = Write(
                service: service,
                account: account,
                label: label,
                description: description,
                metadata: metadata,
                secret: secret
            )
            values["\(service)|\(account)"] = write
            lastWrite = write
        }
    }

    func delete(service: String, account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: "\(service)|\(account)") }
    }

    func itemMetadata(service: String, accountPrefix: String) throws -> [Data] {
        lock.withLock {
            values.values
                .filter { $0.service == service && $0.account.hasPrefix(accountPrefix) }
                .sorted { $0.account < $1.account }
                .map(\.metadata)
        }
    }
}
