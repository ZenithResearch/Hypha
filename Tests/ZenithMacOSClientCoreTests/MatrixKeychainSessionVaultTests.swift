import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class MatrixEncryptedSessionVaultTests: XCTestCase {
    func testCredentialsAndSessionsShareOneRootKeyWhilePasswordsStayEncryptedOnDisk() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let firstProcess = makeVault(storage: keychain, directory: directory)
        let homeserver = URL(string: "https://matrix.example.org")!
        let password = "encrypted-password-marker"

        let credential = try firstProcess.savePassword(
            password,
            username: "peachpraline",
            homeserver: homeserver
        )
        let session = fixtureRecord(accountKey: credential.id, userID: "@peachpraline:matrix.example.org")
        try firstProcess.saveStoreKey(Data(repeating: 0xA1, count: 32), accountKey: session.accountKey)
        try firstProcess.saveSession(session)

        XCTAssertEqual(keychain.accounts(service: service), ["matrix-vault-key-v1"])
        XCTAssertFalse(try allRegularFileData(in: directory).contains(Data(password.utf8)))

        let secondProcess = makeVault(storage: keychain, directory: directory)
        keychain.resetReadCounts()
        XCTAssertEqual(try secondProcess.credentials(), [credential])
        XCTAssertEqual(try secondProcess.password(for: credential), password)
        XCTAssertEqual(try secondProcess.loadSession(), session)
        XCTAssertEqual(keychain.readCount(service: service, account: "matrix-vault-key-v1"), 1)
    }

    func testCredentialDeletionDoesNotDeleteMatrixSessionOrStoreKey() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let vault = makeVault(storage: keychain, directory: directory)
        let credential = try vault.savePassword(
            "password",
            username: "alice",
            homeserver: URL(string: "https://example.org")!
        )
        let session = fixtureRecord(accountKey: credential.id, userID: "@alice:example.org")
        let storeKey = Data(repeating: 0xA1, count: 32)
        try vault.saveStoreKey(storeKey, accountKey: credential.id)
        try vault.saveSession(session)

        try vault.delete(credential)

        XCTAssertNil(try vault.password(for: credential))
        XCTAssertEqual(try vault.loadSession(), session)
        XCTAssertEqual(try vault.loadStoreKey(accountKey: credential.id), storeKey)
    }

    func testOneRootKeyUnlockSupportsAccountSwitchingWithoutMoreKeychainReads() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let firstProcess = makeVault(storage: keychain, directory: directory)
        let alice = fixtureRecord(accountKey: "account-alice", userID: "@alice:example.org")
        let peach = fixtureRecord(accountKey: "account-peach", userID: "@peach:example.org")

        try firstProcess.saveStoreKey(Data(repeating: 0xA1, count: 32), accountKey: alice.accountKey)
        try firstProcess.saveSession(alice)
        try firstProcess.saveStoreKey(Data(repeating: 0xB2, count: 32), accountKey: peach.accountKey)
        try firstProcess.saveSession(peach)

        XCTAssertEqual(keychain.accounts(service: service), ["matrix-vault-key-v1"])

        let secondProcess = makeVault(storage: keychain, directory: directory)
        keychain.resetReadCounts()
        XCTAssertEqual(try secondProcess.loadSession(), peach)
        try secondProcess.activateSession(accountKey: alice.accountKey)
        XCTAssertEqual(try secondProcess.loadSession(), alice)
        try secondProcess.activateSession(accountKey: peach.accountKey)
        XCTAssertEqual(try secondProcess.loadSession(), peach)

        XCTAssertEqual(keychain.readCount(service: service, account: "matrix-vault-key-v1"), 1)
        XCTAssertEqual(
            try secondProcess.storedSessions().map(\.userId).sorted(),
            [alice.userId, peach.userId].sorted()
        )
    }

    func testVaultFilesDoNotContainPlaintextSessionOrStoreSecrets() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let vault = makeVault(storage: keychain, directory: directory)
        let record = MatrixSDKSessionRecord(
            accessToken: "secret-access-token-marker",
            refreshToken: "secret-refresh-token-marker",
            userId: "@private-user:example.org",
            deviceId: "PRIVATE-DEVICE",
            homeserverURL: "https://example.org",
            oauthData: nil,
            slidingSyncVersion: "native",
            accountKey: "private-account"
        )
        let storeKey = Data("secret-store-key-marker-32-bytes!".utf8.prefix(32))

        try vault.saveStoreKey(storeKey, accountKey: record.accountKey)
        try vault.saveSession(record)

        let bytes = try allRegularFileData(in: directory)
        for forbidden in [
            record.accessToken,
            record.refreshToken ?? "",
            record.userId,
            record.deviceId,
            String(decoding: storeKey, as: UTF8.self),
        ] {
            XCTAssertFalse(bytes.range(of: Data(forbidden.utf8)) != nil, "Encrypted vault leaked plaintext")
        }
    }

    func testLegacyMigrationCleanupRequiresFreshProcessRestorationProof() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let record = fixtureRecord(accountKey: "legacy-account", userID: "@legacy:example.org")
        let storeKey = Data(repeating: 0x6D, count: 32)
        try keychain.write(JSONEncoder().encode(record), service: service, account: "current-session")
        try keychain.write(storeKey, service: service, account: "store-key:\(record.accountKey)")

        let migrationProcess = makeVault(
            storage: keychain,
            directory: directory,
            processIdentity: "migration-process"
        )

        XCTAssertEqual(try migrationProcess.loadSession(), record)
        XCTAssertEqual(try migrationProcess.loadStoreKey(accountKey: record.accountKey), storeKey)
        try migrationProcess.finalizeLegacyMigrationAfterRestore(accountKey: record.accountKey)
        XCTAssertTrue(keychain.accounts(service: service).contains("current-session"))
        XCTAssertTrue(keychain.accounts(service: service).contains("store-key:\(record.accountKey)"))

        let restartedProcess = makeVault(
            storage: keychain,
            directory: directory,
            processIdentity: "restarted-process"
        )
        XCTAssertEqual(try restartedProcess.loadSession(accountKey: record.accountKey), record)
        try restartedProcess.finalizeLegacyMigrationAfterRestore(accountKey: record.accountKey)

        XCTAssertEqual(keychain.accounts(service: service), ["matrix-vault-key-v1"])
        XCTAssertEqual(try restartedProcess.storedSessions(), [record])
    }

    func testLegacySessionWithoutItsSDKStoreKeyIsNotDeleted() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let record = fixtureRecord(accountKey: "legacy-account", userID: "@legacy:example.org")
        try keychain.write(JSONEncoder().encode(record), service: service, account: "current-session")
        let vault = makeVault(storage: keychain, directory: directory)

        XCTAssertThrowsError(try vault.loadSession()) { error in
            XCTAssertEqual(error as? MatrixChatServiceError, .recoveryRequired)
        }
        XCTAssertTrue(keychain.accounts(service: service).contains("current-session"))
    }

    func testDeletingActiveSessionPreservesItsSDKStoreKeyAndOtherAccounts() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let vault = makeVault(storage: keychain, directory: directory)
        let alice = fixtureRecord(accountKey: "account-alice", userID: "@alice:example.org")
        let peach = fixtureRecord(accountKey: "account-peach", userID: "@peach:example.org")
        let aliceStoreKey = Data(repeating: 0xA1, count: 32)
        let peachStoreKey = Data(repeating: 0xB2, count: 32)
        try vault.saveStoreKey(aliceStoreKey, accountKey: alice.accountKey)
        try vault.saveSession(alice)
        try vault.saveStoreKey(peachStoreKey, accountKey: peach.accountKey)
        try vault.saveSession(peach)

        try vault.deleteSession()

        XCTAssertNil(try vault.loadSession())
        XCTAssertEqual(try vault.storedSessions(), [alice])
        XCTAssertEqual(try vault.loadStoreKey(accountKey: alice.accountKey), aliceStoreKey)
        XCTAssertEqual(try vault.loadStoreKey(accountKey: peach.accountKey), peachStoreKey)
    }

    func testDeletingNamedInactiveSessionPreservesActiveSessionAndBothStoreKeys() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let vault = makeVault(storage: keychain, directory: directory)
        let alice = fixtureRecord(accountKey: "account-alice", userID: "@alice:example.org")
        let peach = fixtureRecord(accountKey: "account-peach", userID: "@peach:example.org")
        let aliceStoreKey = Data(repeating: 0xA1, count: 32)
        let peachStoreKey = Data(repeating: 0xB2, count: 32)
        try vault.saveStoreKey(aliceStoreKey, accountKey: alice.accountKey)
        try vault.saveSession(alice)
        try vault.saveStoreKey(peachStoreKey, accountKey: peach.accountKey)
        try vault.saveSession(peach)

        try vault.deleteSession(accountKey: alice.accountKey)

        XCTAssertEqual(try vault.loadSession(), peach)
        XCTAssertEqual(try vault.storedSessions(), [peach])
        XCTAssertEqual(try vault.loadStoreKey(accountKey: alice.accountKey), aliceStoreKey)
        XCTAssertEqual(try vault.loadStoreKey(accountKey: peach.accountKey), peachStoreKey)
    }

    func testAccountCiphertextCannotBeSubstitutedForAnotherAccount() throws {
        let keychain = CountingMemoryKeychainStorage()
        let directory = temporaryDirectory()
        let vault = makeVault(storage: keychain, directory: directory)
        let alice = fixtureRecord(accountKey: "account-alice", userID: "@alice:example.org")
        let peach = fixtureRecord(accountKey: "account-peach", userID: "@peach:example.org")
        try vault.saveSession(alice)
        try vault.saveSession(peach)

        let accounts = directory.appendingPathComponent("accounts", isDirectory: true)
        let peachCiphertext = try Data(contentsOf: accounts.appendingPathComponent("account-peach.enc"))
        try peachCiphertext.write(to: accounts.appendingPathComponent("account-alice.enc"), options: .atomic)
        XCTAssertThrowsError(try vault.activateSession(accountKey: alice.accountKey)) { error in
            XCTAssertEqual(error as? MatrixChatServiceError, .recoveryRequired)
        }
    }

    private let service = "ca.zenithresearch.macos.client.matrix"

    private func makeVault(
        storage: CountingMemoryKeychainStorage,
        directory: URL,
        processIdentity: String = UUID().uuidString
    ) -> MatrixEncryptedSessionVault {
        MatrixEncryptedSessionVault(
            storage: storage,
            vaultDirectory: directory,
            processIdentity: processIdentity,
            randomRootKey: { Data(repeating: 0x42, count: 32) }
        )
    }

    private func fixtureRecord(accountKey: String, userID: String) -> MatrixSDKSessionRecord {
        MatrixSDKSessionRecord(
            accessToken: "token-\(accountKey)",
            refreshToken: "refresh-\(accountKey)",
            userId: userID,
            deviceId: "DEVICE-\(accountKey)",
            homeserverURL: "https://example.org",
            oauthData: nil,
            slidingSyncVersion: "native",
            accountKey: accountKey
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("matrix-encrypted-vault-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func allRegularFileData(in root: URL) throws -> Data {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return Data() }
        var result = Data()
        for case let fileURL as URL in enumerator {
            if try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result.append(try Data(contentsOf: fileURL))
            }
        }
        return result
    }
}

private final class CountingMemoryKeychainStorage: MatrixKeychainDataStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var reads: [String: Int] = [:]

    func read(service: String, account: String) throws -> Data? {
        lock.withLock {
            reads[key(service: service, account: account), default: 0] += 1
            return values[key(service: service, account: account)]
        }
    }

    func write(_ data: Data, service: String, account: String) throws {
        lock.withLock { values[key(service: service, account: account)] = data }
    }

    func delete(service: String, account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: key(service: service, account: account)) }
    }

    func accounts(service: String) -> [String] {
        lock.withLock {
            values.keys.compactMap { key in
                let prefix = "\(service)|"
                return key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
            }.sorted()
        }
    }

    func readCount(service: String, account: String) -> Int {
        lock.withLock { reads[key(service: service, account: account), default: 0] }
    }

    func resetReadCounts() {
        lock.withLock { reads = [:] }
    }

    private func key(service: String, account: String) -> String { "\(service)|\(account)" }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
