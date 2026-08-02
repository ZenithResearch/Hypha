import CryptoKit
import Foundation
import MatrixRustSDK
import OSLog
import Security

public struct MatrixSDKSessionRecord: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let userId: String
    public let deviceId: String
    public let homeserverURL: String
    public let oauthData: String?
    public let slidingSyncVersion: String
    public let accountKey: String

    public init(
        accessToken: String,
        refreshToken: String?,
        userId: String,
        deviceId: String,
        homeserverURL: String,
        oauthData: String? = nil,
        slidingSyncVersion: String,
        accountKey: String
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.deviceId = deviceId
        self.homeserverURL = homeserverURL
        self.oauthData = oauthData
        self.slidingSyncVersion = slidingSyncVersion
        self.accountKey = accountKey
    }
}

public protocol MatrixSDKSessionVault: Sendable {
    func loadSession() throws -> MatrixSDKSessionRecord?
    func loadSession(accountKey: String) throws -> MatrixSDKSessionRecord?
    func saveSession(_ value: MatrixSDKSessionRecord) throws
    func deleteSession() throws
    func deleteSession(accountKey: String) throws
    func loadStoreKey(accountKey: String) throws -> Data?
    func saveStoreKey(_ value: Data, accountKey: String) throws
    func finalizeLegacyMigrationAfterRestore(accountKey: String) throws
}

public extension MatrixSDKSessionVault {
    func deleteSession(accountKey: String) throws {
        guard try loadSession()?.accountKey == accountKey else { return }
        try deleteSession()
    }
}

public extension MatrixSDKSessionVault {
    func loadSession(accountKey: String) throws -> MatrixSDKSessionRecord? {
        guard let session = try loadSession(), session.accountKey == accountKey else { return nil }
        return session
    }

    func finalizeLegacyMigrationAfterRestore(accountKey: String) throws {}
}

public protocol MatrixPasswordSessionReauthenticating: Sendable {
    func reauthenticate(
        username: String,
        password: String,
        existingSession: MatrixSDKSessionRecord,
        configuration: MatrixProductConfiguration
    ) async throws -> MatrixSDKSessionRecord
}

public struct MatrixPasswordSessionReauthenticator: MatrixPasswordSessionReauthenticating {
    public init() {}

    public func reauthenticate(
        username: String,
        password: String,
        existingSession: MatrixSDKSessionRecord,
        configuration: MatrixProductConfiguration
    ) async throws -> MatrixSDKSessionRecord {
        guard MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
            existingSession.homeserverURL,
            configured: configuration.homeserver
        ) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        let client = try await ClientBuilder()
            .homeserverUrl(url: configuration.homeserver.absoluteString)
            .build()
        try await client.login(
            username: username,
            password: password,
            initialDeviceName: "Hypha",
            deviceId: existingSession.deviceId
        )
        let session = try client.session()
        guard session.userId == existingSession.userId,
              session.deviceId == existingSession.deviceId,
              MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                  session.homeserverUrl,
                  configured: configuration.homeserver
              ) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return MatrixSDKSessionRecord(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.userId,
            deviceId: session.deviceId,
            homeserverURL: session.homeserverUrl,
            oauthData: session.oauthData,
            slidingSyncVersion: session.slidingSyncVersion == .native ? "native" : "none",
            accountKey: existingSession.accountKey
        )
    }
}

public protocol MatrixLiveClient: Sendable {
    func login(username: String, password: String) async throws
    func restore(session: MatrixSDKSessionRecord) async throws
    func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws
    func sessionRecord(accountKey: String) async throws -> MatrixSDKSessionRecord
    func syncOnce() async throws
    func startContinuousSync() async
    func stopContinuousSync() async
    func joinedRooms() async throws -> [MatrixRoomSummary]
    func timeline(roomID: String) async throws -> [MatrixTimelineEvent]
    func sendText(_ body: String, roomID: String) async throws
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws
    func removeRoom(roomID: String) async throws
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState
    func setupEncryptionRecovery() async throws -> String
    func restoreEncryption(recoveryKey: String) async throws
    func deviceTrustState() async throws -> MatrixDeviceTrustState
    func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge
    func approveDeviceVerification() async throws
    func declineDeviceVerification() async
    func logout() async throws
}

public extension MatrixLiveClient {
    func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Password change is unavailable")
    }

    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        throw MatrixChatServiceError.unavailable(reason: "Room creation is unavailable")
    }
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult {
        .unavailable
    }
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room invitations are unavailable")
    }
    func removeRoom(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room removal is unavailable")
    }
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState { .unknown }
    func setupEncryptionRecovery() async throws -> String {
        throw MatrixChatServiceError.unavailable(reason: "Encryption recovery setup is unavailable")
    }
    func restoreEncryption(recoveryKey: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Matrix Rust SDK client is unavailable")
    }
    func deviceTrustState() async throws -> MatrixDeviceTrustState { .unavailable }
    func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility { .unavailable }
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState { .unavailable }
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState { .unavailable }
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func approveDeviceVerification() async throws {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func declineDeviceVerification() async {}
}

public protocol MatrixLiveClientFactory: Sendable {
    func make(accountKey: String, storeKey: Data) async throws -> any MatrixLiveClient
}

public actor MatrixRustSDKChatService: MatrixChatService {
    public typealias RandomStoreKey = @Sendable () throws -> Data

    private let configuration: MatrixProductConfiguration
    private let vault: any MatrixSDKSessionVault
    private let clientFactory: any MatrixLiveClientFactory
    private let passwordSessionReauthenticator: any MatrixPasswordSessionReauthenticating
    private let randomStoreKey: RandomStoreKey
    private var client: (any MatrixLiveClient)?
    private var activeSession: MatrixSDKSessionRecord?
    private var roomsByID: [String: MatrixRoomSummary] = [:]
    private var firstDeviceBootstrapInFlight = false

    public init(
        configuration: MatrixProductConfiguration,
        vault: any MatrixSDKSessionVault,
        clientFactory: any MatrixLiveClientFactory,
        passwordSessionReauthenticator: any MatrixPasswordSessionReauthenticating = MatrixPasswordSessionReauthenticator(),
        randomStoreKey: @escaping RandomStoreKey = { try MatrixRustSDKChatService.secureRandomStoreKey() }
    ) {
        self.configuration = configuration
        self.vault = vault
        self.clientFactory = clientFactory
        self.passwordSessionReauthenticator = passwordSessionReauthenticator
        self.randomStoreKey = randomStoreKey
    }

    public func restore() async throws -> [MatrixRoomSummary] {
        guard let session = try vault.loadSession() else {
            throw MatrixChatServiceError.noSavedSession
        }
        guard MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
            session.homeserverURL,
            configured: configuration.homeserver
        ) else {
            throw MatrixChatServiceError.unavailable(reason: "Saved Matrix session belongs to another homeserver")
        }
        guard let storeKey = try vault.loadStoreKey(accountKey: session.accountKey), storeKey.count == 32 else {
            throw MatrixChatServiceError.recoveryRequired
        }

        let liveClient = try await clientFactory.make(accountKey: session.accountKey, storeKey: storeKey)
        do {
            try await liveClient.restore(session: session)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Matrix session restore failed")
        }
        let rooms = try await loadInitialRooms(with: liveClient)
        try vault.finalizeLegacyMigrationAfterRestore(accountKey: session.accountKey)
        activate(liveClient, session: session, rooms: rooms)
        return rooms
    }

    public func signIn(username: String, password: String) async throws -> [MatrixRoomSummary] {
        let accountKey = Self.accountKey(username: username, homeserver: configuration.homeserver)
        if let existingSession = try vault.loadSession(accountKey: accountKey) {
            guard let storeKey = try vault.loadStoreKey(accountKey: accountKey), storeKey.count == 32 else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let refreshedSession: MatrixSDKSessionRecord
            do {
                refreshedSession = try await passwordSessionReauthenticator.reauthenticate(
                    username: username,
                    password: password,
                    existingSession: existingSession,
                    configuration: configuration
                )
            } catch {
                throw mapLoginError(error)
            }
            guard refreshedSession.accountKey == accountKey,
                  refreshedSession.userId == existingSession.userId,
                  refreshedSession.deviceId == existingSession.deviceId else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let liveClient = try await clientFactory.make(accountKey: accountKey, storeKey: storeKey)
            do {
                try await liveClient.restore(session: refreshedSession)
            } catch {
                throw mapRuntimeError(error, fallbackReason: "Matrix session reauthentication restore failed")
            }
            let rooms = try await loadInitialRooms(with: liveClient)
            try vault.saveSession(refreshedSession)
            try vault.finalizeLegacyMigrationAfterRestore(accountKey: accountKey)
            activate(liveClient, session: refreshedSession, rooms: rooms)
            return rooms
        }

        let storeKey: Data
        if let existing = try vault.loadStoreKey(accountKey: accountKey) {
            guard existing.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
            storeKey = existing
        } else {
            let generated = try randomStoreKey()
            guard generated.count == 32 else {
                throw MatrixChatServiceError.unavailable(reason: "Unable to create encrypted Matrix store")
            }
            try vault.saveStoreKey(generated, accountKey: accountKey)
            storeKey = generated
        }

        let liveClient = try await clientFactory.make(accountKey: accountKey, storeKey: storeKey)
        do {
            try await liveClient.login(username: username, password: password)
        } catch {
            throw mapLoginError(error)
        }

        let record: MatrixSDKSessionRecord
        do {
            record = try await liveClient.sessionRecord(accountKey: accountKey)
        } catch {
            throw mapRuntimeError(
                error,
                fallbackReason: "Matrix login succeeded, but the SDK session could not be read"
            )
        }
        guard MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
            record.homeserverURL,
            configured: configuration.homeserver
        ) else {
            throw MatrixChatServiceError.unavailable(reason: "Matrix homeserver changed during login")
        }
        let rooms = try await loadInitialRooms(with: liveClient)
        try vault.saveSession(record)
        activate(liveClient, session: record, rooms: rooms)
        return rooms
    }

    public func refreshRooms() async throws -> [MatrixRoomSummary] {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        await client.stopContinuousSync()
        do {
            try await client.syncOnce()
            let rooms = try await client.joinedRooms()
            remember(rooms)
            await client.startContinuousSync()
            return rooms
        } catch {
            await client.startContinuousSync()
            throw mapRuntimeError(error, fallbackReason: "Matrix room sync failed")
        }
    }

    public func timeline(for roomID: String) async throws -> [MatrixTimelineEvent] {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        return try await client.timeline(roomID: roomID)
    }

    public func sendText(_ body: String, to roomID: String) async throws {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard roomsByID[roomID]?.isEncrypted == true else {
            throw MatrixChatServiceError.trustViolation
        }
        do {
            try await client.sendText(body, roomID: roomID)
        } catch {
            throw mapRuntimeError(error)
        }
    }

    public func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard !request.name.isEmpty else {
            throw MatrixChatServiceError.unavailable(reason: "Room name is required")
        }
        do {
            let room = try await client.createEncryptedRoom(request)
            guard room.isEncrypted else { throw MatrixChatServiceError.trustViolation }
            roomsByID[room.id] = room
            return room
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encrypted room creation failed")
        }
    }

    public func lookupInviteUser(
        userID: String,
        roomID: String
    ) async throws -> MatrixUserLookupResult {
        guard let client,
              let room = roomsByID[roomID],
              room.canInviteMembers,
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room invitation lookup is unavailable")
        }
        return try await client.lookupInviteUser(userID: userID, roomID: roomID)
    }

    public func inviteUsers(_ request: MatrixRoomInviteRequest) async throws {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard let room = roomsByID[request.roomID],
              room.canInviteMembers,
              !room.hasInvite,
              !room.isSpace,
              !request.userIDs.isEmpty else {
            throw MatrixChatServiceError.unavailable(reason: "You cannot invite members to this room")
        }
        do {
            try await client.inviteUsers(request)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room invitations failed")
        }
    }

    public func removeRoom(roomID: String) async throws -> [MatrixRoomSummary] {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard let room = roomsByID[roomID], room.isCreatedByCurrentUser else {
            throw MatrixChatServiceError.unavailable(
                reason: "Only the account that created this room can remove it"
            )
        }
        do {
            try await client.removeRoom(roomID: roomID)
            let remaining = try await client.joinedRooms()
            roomsByID = Dictionary(uniqueKeysWithValues: remaining.map { ($0.id, $0) })
            return remaining
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room removal failed")
        }
    }

    public func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.encryptionRecoveryState(trustState: trustState)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery status unavailable")
        }
    }

    public func setupEncryptionRecovery() async throws -> String {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.setupEncryptionRecovery()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery setup failed")
        }
    }

    public func restoreEncryption(recoveryKey: String) async throws {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.restoreEncryption(recoveryKey: recoveryKey)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery failed")
        }
    }

    public func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                logoutOtherDevices: logoutOtherDevices
            )
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Password change failed")
        }
    }

    public func isHomeserverAdministrator() async throws -> Bool {
        try await administratorClient().isAdministrator()
    }

    public func administratorSnapshot() async throws -> MatrixAdminSnapshot {
        try await administratorClient().snapshot()
    }

    public func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        try await administratorClient().createAccount(
            localpart: localpart,
            temporaryPassword: temporaryPassword,
            administrator: administrator
        )
    }

    public func deactivateAdministratorManagedAccount(userID: String) async throws {
        try await administratorClient().deactivateAccount(userID: userID)
    }

    public func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary {
        try await administratorClient().createRoom(name: name, topic: topic, asSpace: asSpace, visibility: visibility)
    }

    public func logoutAdministratorManagedAccount(userID: String) async throws {
        try await administratorClient().logoutAccount(userID: userID)
    }

    public func purgeAdministratorManagedRoom(roomID: String) async throws {
        try await administratorClient().purgeRoom(roomID: roomID)
    }

    public func deviceTrustState() async throws -> MatrixDeviceTrustState {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.deviceTrustState()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device trust state unavailable")
        }
    }

    public func peerVerificationEligibility() async -> MatrixPeerVerificationEligibility {
        guard let client else { return .unavailable }
        do {
            return try await client.peerVerificationEligibility()
        } catch {
            return .unavailable
        }
    }

    public func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        guard !firstDeviceBootstrapInFlight else { return .bootstrapping }
        firstDeviceBootstrapInFlight = true
        defer { firstDeviceBootstrapInFlight = false }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.bootstrapFirstDeviceTrust()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "First-device security setup failed")
        }
    }

    public func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState {
        guard !firstDeviceBootstrapInFlight else { return .bootstrapping }
        firstDeviceBootstrapInFlight = true
        defer { firstDeviceBootstrapInFlight = false }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.continueFirstDeviceTrust(password: password)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "First-device security setup failed")
        }
    }


    public func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.requestDeviceVerification()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device verification request failed")
        }
    }

    public func approveDeviceVerification() async throws {
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.approveDeviceVerification()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device verification approval failed")
        }
    }

    public func declineDeviceVerification() async {
        guard let client else { return }
        await client.declineDeviceVerification()
    }

    public func suspend() async {
        if let client {
            await client.stopContinuousSync()
        }
        self.client = nil
        activeSession = nil
        roomsByID = [:]
    }

    public func logout() async throws {
        var remoteLogoutError: Error?
        if let client {
            await client.stopContinuousSync()
            do {
                try await client.logout()
            } catch {
                remoteLogoutError = error
            }
        }
        try vault.deleteSession()
        self.client = nil
        activeSession = nil
        roomsByID = [:]
        if let remoteLogoutError {
            throw mapRuntimeError(remoteLogoutError, fallbackReason: "Signed out locally, but remote logout could not be confirmed")
        }
    }

    private func loadInitialRooms(with client: any MatrixLiveClient) async throws -> [MatrixRoomSummary] {
        do {
            try await client.syncOnce()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Initial Matrix sync failed")
        }

        do {
            let rooms = try await client.joinedRooms()
            await client.startContinuousSync()
            return rooms
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Initial Matrix room load failed")
        }
    }

    private func activate(
        _ client: any MatrixLiveClient,
        session: MatrixSDKSessionRecord,
        rooms: [MatrixRoomSummary]
    ) {
        self.client = client
        activeSession = session
        remember(rooms)
    }

    private func administratorClient() throws -> MatrixSynapseAdminClient {
        guard client != nil, let activeSession else {
            throw MatrixChatServiceError.sessionExpired
        }
        guard MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
            activeSession.homeserverURL,
            configured: configuration.homeserver
        ) else {
            throw MatrixChatServiceError.unavailable(reason: "Administrator session belongs to another homeserver")
        }
        return MatrixSynapseAdminClient(
            homeserver: configuration.homeserver,
            currentUserID: activeSession.userId,
            accessToken: activeSession.accessToken
        )
    }

    private func remember(_ rooms: [MatrixRoomSummary]) {
        roomsByID = rooms.reduce(into: [:]) { result, room in
            result[room.id] = room
        }
    }

    private func mapLoginError(_ error: Error) -> MatrixChatServiceError {
        if case let ClientError.MatrixApi(kind, _, _, _)? = error as? ClientError,
           kind == .forbidden {
            return .invalidCredentials
        }
        let description = String(describing: error).lowercased()
        if description.contains("forbidden") || description.contains("m_forbidden") || description.contains("invalid username or password") {
            return .invalidCredentials
        }
        return mapRuntimeError(error, fallbackReason: "Matrix login request failed")
    }

    private func mapRuntimeError(
        _ error: Error,
        fallbackReason: String = "Matrix request failed"
    ) -> MatrixChatServiceError {
        if let error = error as? MatrixChatServiceError { return error }
        if case let ClientError.MatrixApi(kind, _, _, _)? = error as? ClientError {
            switch kind {
            case .unknownToken, .unauthorized:
                return .sessionExpired
            case .connectionFailed, .connectionTimeout:
                return .offline
            default:
                break
            }
        }
        let description = String(describing: error).lowercased()
        if description.contains("unknown token") || description.contains("m_unknown_token") {
            return .sessionExpired
        }
        if description.contains("network") || description.contains("connection") || description.contains("timed out") {
            return .offline
        }
        return .unavailable(reason: fallbackReason)
    }

    public static func accountKey(username: String, homeserver: URL) -> String {
        let normalized = "\(homeserver.absoluteString.lowercased())|\(username.lowercased())"
        return SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func secureRandomStoreKey() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to create encrypted Matrix store")
        }
        return Data(bytes)
    }
}

protocol MatrixKeychainDataStorage: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

private final class SecurityMatrixKeychainDataStorage: MatrixKeychainDataStorage, @unchecked Sendable {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to read Matrix Keychain data")
        }
        return data
    }

    func write(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to update Matrix Keychain data")
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to save Matrix Keychain data")
        }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to delete Matrix Keychain data")
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

public final class MatrixEncryptedSessionVault: MatrixSDKSessionVault, HyphaMatrixCredentialStore, HyphaLegacyCredentialMigrationTracking, @unchecked Sendable {
    public typealias RandomRootKey = @Sendable () throws -> Data

    private struct Manifest: Codable, Equatable {
        let version: Int
        var accountKeys: [String]
        var activeAccountKey: String?
    }

    private struct LegacyMigrationState: Codable, Equatable {
        let version: Int
        let originProcessIdentity: String
        var verifiedProcessIdentity: String?
    }

    private struct AccountRecord: Codable {
        let version: Int
        let accountKey: String
        var session: MatrixSDKSessionRecord?
        var storeKey: Data?
        var credential: HyphaMatrixCredentialDescriptor?
        var password: String?
        var legacyMigration: LegacyMigrationState?
        var credentialMigration: LegacyMigrationState?
    }

    private let service = "ca.zenithresearch.macos.client.matrix"
    private let legacyService = ["ca", "zenith-research", "mobile-macos", "matrix"].joined(separator: ".")
    private let rootKeyAccount = "matrix-vault-key-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let currentProcessIdentity = UUID().uuidString
    private let storage: any MatrixKeychainDataStorage
    private let vaultDirectory: URL
    private let processIdentity: String
    private let randomRootKey: RandomRootKey
    private let lock = NSRecursiveLock()
    private var cachedRootKey: Data?

    public convenience init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            storage: SecurityMatrixKeychainDataStorage(),
            vaultDirectory: base
                .appendingPathComponent("ca.zenithresearch.macos.client", isDirectory: true)
                .appendingPathComponent("MatrixSessionVault-v1", isDirectory: true),
            randomRootKey: { try Self.secureRandomRootKey() }
        )
    }

    init(
        storage: any MatrixKeychainDataStorage,
        vaultDirectory: URL,
        processIdentity: String = MatrixEncryptedSessionVault.currentProcessIdentity,
        randomRootKey: @escaping RandomRootKey
    ) {
        self.storage = storage
        self.vaultDirectory = vaultDirectory
        self.processIdentity = processIdentity
        self.randomRootKey = randomRootKey
    }

    public func loadSession() throws -> MatrixSDKSessionRecord? {
        try synchronized {
            let key = try prepareVault()
            let manifest = try loadManifest(key: key)
            guard let accountKey = manifest.activeAccountKey else { return nil }
            guard let record = try loadAccount(accountKey: accountKey, key: key),
                  record.session?.accountKey == accountKey else {
                throw MatrixChatServiceError.recoveryRequired
            }
            return record.session
        }
    }

    public func loadSession(accountKey: String) throws -> MatrixSDKSessionRecord? {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard let record = try loadAccount(accountKey: accountKey, key: key) else { return nil }
            guard record.session == nil || record.session?.accountKey == accountKey else {
                throw MatrixChatServiceError.recoveryRequired
            }
            return record.session
        }
    }

    public func saveSession(_ value: MatrixSDKSessionRecord) throws {
        try synchronized {
            guard Self.isValidAccountKey(value.accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            var record = try loadAccount(accountKey: value.accountKey, key: key)
                ?? AccountRecord(version: 1, accountKey: value.accountKey, session: nil, storeKey: nil, credential: nil, password: nil, legacyMigration: nil, credentialMigration: nil)
            record.session = value
            try writeAccount(record, key: key)
            var manifest = try loadManifest(key: key)
            if !manifest.accountKeys.contains(value.accountKey) {
                manifest.accountKeys.append(value.accountKey)
            }
            manifest.activeAccountKey = value.accountKey
            try writeManifest(manifest, key: key)
        }
    }

    public func finalizeLegacyMigrationAfterRestore(accountKey: String) throws {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard var record = try loadAccount(accountKey: accountKey, key: key),
                  record.session?.accountKey == accountKey,
                  record.storeKey?.count == 32,
                  var migration = record.legacyMigration else { return }
            guard migration.version == 1, !migration.originProcessIdentity.isEmpty else {
                throw MatrixChatServiceError.recoveryRequired
            }
            if migration.verifiedProcessIdentity == nil {
                guard migration.originProcessIdentity != processIdentity else { return }
                migration.verifiedProcessIdentity = processIdentity
                record.legacyMigration = migration
                try writeAccount(record, key: key)
                guard try loadAccount(accountKey: accountKey, key: key)?.legacyMigration == migration else {
                    throw MatrixChatServiceError.recoveryRequired
                }
            }
            try cleanupLegacyRecords(accountKey: accountKey)
        }
    }

    public func storedSessions() throws -> [MatrixSDKSessionRecord] {
        try synchronized {
            let key = try prepareVault()
            return try loadManifest(key: key).accountKeys.compactMap { accountKey in
                guard let record = try loadAccount(accountKey: accountKey, key: key) else {
                    throw MatrixChatServiceError.recoveryRequired
                }
                return record.session
            }
        }
    }

    public func activateSession(accountKey: String) throws {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard let record = try loadAccount(accountKey: accountKey, key: key),
                  record.session?.accountKey == accountKey else {
                throw MatrixChatServiceError.recoveryRequired
            }
            var manifest = try loadManifest(key: key)
            guard manifest.accountKeys.contains(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            manifest.activeAccountKey = accountKey
            try writeManifest(manifest, key: key)
        }
    }

    public func deleteSession() throws {
        try synchronized {
            let key = try prepareVault()
            var manifest = try loadManifest(key: key)
            guard let accountKey = manifest.activeAccountKey else { return }
            try clearSession(accountKey: accountKey, key: key, manifest: &manifest)
        }
    }

    public func deleteSession(accountKey: String) throws {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            var manifest = try loadManifest(key: key)
            try clearSession(accountKey: accountKey, key: key, manifest: &manifest)
        }
    }

    private func clearSession(accountKey: String, key: Data, manifest: inout Manifest) throws {
        guard var record = try loadAccount(accountKey: accountKey, key: key) else { return }
        record.session = nil
        if record.storeKey == nil, record.credential == nil {
            try? FileManager.default.removeItem(at: accountURL(accountKey: accountKey))
            manifest.accountKeys.removeAll { $0 == accountKey }
        } else {
            try writeAccount(record, key: key)
        }
        if manifest.activeAccountKey == accountKey {
            manifest.activeAccountKey = nil
        }
        try writeManifest(manifest, key: key)
    }

    public func loadStoreKey(accountKey: String) throws -> Data? {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            return try loadAccount(accountKey: accountKey, key: key)?.storeKey
        }
    }

    public func saveStoreKey(_ value: Data, accountKey: String) throws {
        try synchronized {
            guard Self.isValidAccountKey(accountKey), value.count == 32 else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            var record = try loadAccount(accountKey: accountKey, key: key)
                ?? AccountRecord(version: 1, accountKey: accountKey, session: nil, storeKey: nil, credential: nil, password: nil, legacyMigration: nil, credentialMigration: nil)
            record.storeKey = value
            try writeAccount(record, key: key)
        }
    }

    public func credentials() throws -> [HyphaMatrixCredentialDescriptor] {
        try synchronized {
            let key = try prepareVault()
            return try loadManifest(key: key).accountKeys.compactMap { accountKey in
                guard let record = try loadAccount(accountKey: accountKey, key: key) else {
                    throw MatrixChatServiceError.recoveryRequired
                }
                return record.credential
            }.sorted { $0.id < $1.id }
        }
    }

    public func password(for credential: HyphaMatrixCredentialDescriptor) throws -> String? {
        try synchronized {
            guard HyphaMatrixKeychainCredentialStore.isValidCredential(credential) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard let record = try loadAccount(accountKey: credential.id, key: key) else { return nil }
            if record.credential == nil, record.password == nil { return nil }
            guard record.credential == credential else {
                throw MatrixChatServiceError.recoveryRequired
            }
            return record.password
        }
    }

    @discardableResult
    public func savePassword(
        _ password: String,
        username: String,
        homeserver: URL
    ) throws -> HyphaMatrixCredentialDescriptor {
        try synchronized {
            let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedUsername.isEmpty, !password.isEmpty else {
                throw MatrixChatServiceError.invalidCredentials
            }
            let credential = HyphaMatrixCredentialDescriptor(
                id: MatrixRustSDKChatService.accountKey(username: normalizedUsername, homeserver: homeserver),
                username: normalizedUsername,
                homeserverURL: homeserver.absoluteString
            )
            guard HyphaMatrixKeychainCredentialStore.isValidCredential(credential) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            var record = try loadAccount(accountKey: credential.id, key: key)
                ?? AccountRecord(version: 1, accountKey: credential.id, session: nil, storeKey: nil, credential: nil, password: nil, legacyMigration: nil, credentialMigration: nil)
            record.credential = credential
            record.password = password
            try writeAccount(record, key: key)
            var manifest = try loadManifest(key: key)
            if !manifest.accountKeys.contains(credential.id) {
                manifest.accountKeys.append(credential.id)
            }
            try writeManifest(manifest, key: key)
            return credential
        }
    }

    func markLegacyCredentialMigrationPending(
        credentialID: String,
        originProcessIdentity: String
    ) throws {
        try synchronized {
            guard Self.isValidAccountKey(credentialID), !originProcessIdentity.isEmpty else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard var record = try loadAccount(accountKey: credentialID, key: key),
                  record.credential?.id == credentialID,
                  record.password?.isEmpty == false else {
                throw MatrixChatServiceError.recoveryRequired
            }
            if record.credentialMigration == nil {
                record.credentialMigration = LegacyMigrationState(
                    version: 1,
                    originProcessIdentity: originProcessIdentity,
                    verifiedProcessIdentity: nil
                )
                try writeAccount(record, key: key)
            }
        }
    }

    func authorizeLegacyCredentialCleanup(
        credentialID: String,
        verifierProcessIdentity: String
    ) throws -> Bool {
        try synchronized {
            guard Self.isValidAccountKey(credentialID), !verifierProcessIdentity.isEmpty else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard var record = try loadAccount(accountKey: credentialID, key: key),
                  record.credential?.id == credentialID,
                  record.password?.isEmpty == false,
                  var migration = record.credentialMigration else { return false }
            guard migration.version == 1,
                  !migration.originProcessIdentity.isEmpty else {
                throw MatrixChatServiceError.recoveryRequired
            }
            if migration.verifiedProcessIdentity == nil {
                guard migration.originProcessIdentity != verifierProcessIdentity else { return false }
                migration.verifiedProcessIdentity = verifierProcessIdentity
                record.credentialMigration = migration
                try writeAccount(record, key: key)
                guard try loadAccount(accountKey: credentialID, key: key)?.credentialMigration == migration else {
                    throw MatrixChatServiceError.recoveryRequired
                }
            }
            return true
        }
    }

    public func delete(_ credential: HyphaMatrixCredentialDescriptor) throws {
        try synchronized {
            guard HyphaMatrixKeychainCredentialStore.isValidCredential(credential) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard var record = try loadAccount(accountKey: credential.id, key: key) else { return }
            guard record.credential == credential else {
                throw MatrixChatServiceError.recoveryRequired
            }
            record.credential = nil
            record.password = nil
            record.credentialMigration = nil
            var manifest = try loadManifest(key: key)
            if record.session == nil, record.storeKey == nil {
                try? FileManager.default.removeItem(at: accountURL(accountKey: credential.id))
                manifest.accountKeys.removeAll { $0 == credential.id }
                if manifest.activeAccountKey == credential.id { manifest.activeAccountKey = nil }
                try writeManifest(manifest, key: key)
            } else {
                try writeAccount(record, key: key)
            }
        }
    }

    private func prepareVault() throws -> Data {
        let key = try rootKey()
        try ensureDirectories()
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
            try migrateLegacyRecords(key: key)
        }
        return key
    }

    private func rootKey() throws -> Data {
        if let cachedRootKey { return cachedRootKey }
        if let existing = try storage.read(service: service, account: rootKeyAccount) {
            guard existing.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
            cachedRootKey = existing
            return existing
        }
        let generated = try randomRootKey()
        guard generated.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
        try storage.write(generated, service: service, account: rootKeyAccount)
        cachedRootKey = generated
        return generated
    }

    private func migrateLegacyRecords(key: Data) throws {
        var records: [String: AccountRecord] = [:]
        var orderedAccountKeys: [String] = []
        var activeAccountKey: String?

        if let indexData = try storage.read(service: service, account: "session-index-v1") {
            let index: [String]
            do { index = try decoder.decode([String].self, from: indexData) }
            catch { throw MatrixChatServiceError.recoveryRequired }
            guard Set(index).count == index.count, index.allSatisfy(Self.isValidAccountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            for accountKey in index {
                guard let sessionData = try storage.read(service: service, account: "session:\(accountKey)"),
                      let storeKey = try readLegacyStoreKey(accountKey: accountKey) else {
                    throw MatrixChatServiceError.recoveryRequired
                }
                let session = try decodeLegacySession(sessionData, expectedAccountKey: accountKey)
                records[accountKey] = AccountRecord(
                    version: 1,
                    accountKey: accountKey,
                    session: session,
                    storeKey: storeKey,
                    credential: nil,
                    password: nil,
                    legacyMigration: LegacyMigrationState(
                        version: 1,
                        originProcessIdentity: processIdentity,
                        verifiedProcessIdentity: nil
                    ),
                    credentialMigration: nil
                )
                orderedAccountKeys.append(accountKey)
            }
            if let activeData = try storage.read(service: service, account: "active-session"),
               let active = String(data: activeData, encoding: .utf8),
               orderedAccountKeys.contains(active) {
                activeAccountKey = active
            }
        }

        for sourceService in [service, legacyService] {
            guard let data = try storage.read(service: sourceService, account: "current-session") else { continue }
            let session = try decodeLegacySession(data, expectedAccountKey: nil)
            let accountKey = session.accountKey
            guard let storeKey = try readLegacyStoreKey(accountKey: accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            if records[accountKey] == nil {
                records[accountKey] = AccountRecord(
                    version: 1,
                    accountKey: accountKey,
                    session: session,
                    storeKey: storeKey,
                    credential: nil,
                    password: nil,
                    legacyMigration: LegacyMigrationState(
                        version: 1,
                        originProcessIdentity: processIdentity,
                        verifiedProcessIdentity: nil
                    ),
                    credentialMigration: nil
                )
                orderedAccountKeys.append(accountKey)
            }
            if activeAccountKey == nil { activeAccountKey = accountKey }
        }

        for accountKey in records.keys.sorted() {
            guard let record = records[accountKey] else { continue }
            try writeAccount(record, key: key)
        }
        let manifest = Manifest(version: 1, accountKeys: orderedAccountKeys, activeAccountKey: activeAccountKey)
        try writeManifest(manifest, key: key)

        let verified = try loadManifest(key: key)
        guard verified == manifest else { throw MatrixChatServiceError.recoveryRequired }
        for accountKey in orderedAccountKeys {
            guard try loadAccount(accountKey: accountKey, key: key)?.session?.accountKey == accountKey else {
                throw MatrixChatServiceError.recoveryRequired
            }
        }
    }

    private func cleanupLegacyRecords(accountKey: String) throws {
        for sourceService in [service, legacyService] {
            if let data = try storage.read(service: sourceService, account: "current-session") {
                let session = try decodeLegacySession(data, expectedAccountKey: nil)
                if session.accountKey == accountKey {
                    try storage.delete(service: sourceService, account: "current-session")
                }
            }
            try storage.delete(service: sourceService, account: "session:\(accountKey)")
            try storage.delete(service: sourceService, account: "store-key:\(accountKey)")
        }

        if let activeData = try storage.read(service: service, account: "active-session"),
           let activeAccountKey = String(data: activeData, encoding: .utf8) {
            if activeAccountKey == accountKey {
                try storage.delete(service: service, account: "active-session")
            }
        }

        if let indexData = try storage.read(service: service, account: "session-index-v1") {
            let index: [String]
            do { index = try decoder.decode([String].self, from: indexData) }
            catch { throw MatrixChatServiceError.recoveryRequired }
            guard Set(index).count == index.count, index.allSatisfy(Self.isValidAccountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let remaining = index.filter { $0 != accountKey }
            if remaining.isEmpty {
                try storage.delete(service: service, account: "session-index-v1")
            } else if remaining != index {
                try storage.write(encoder.encode(remaining), service: service, account: "session-index-v1")
            }
        }
    }

    private func decodeLegacySession(_ data: Data, expectedAccountKey: String?) throws -> MatrixSDKSessionRecord {
        let session: MatrixSDKSessionRecord
        do { session = try decoder.decode(MatrixSDKSessionRecord.self, from: data) }
        catch { throw MatrixChatServiceError.recoveryRequired }
        guard Self.isValidAccountKey(session.accountKey),
              expectedAccountKey == nil || session.accountKey == expectedAccountKey else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return session
    }

    private func readLegacyStoreKey(accountKey: String) throws -> Data? {
        for sourceService in [service, legacyService] {
            if let data = try storage.read(service: sourceService, account: "store-key:\(accountKey)") {
                guard data.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
                return data
            }
        }
        return nil
    }

    private func loadManifest(key: Data) throws -> Manifest {
        let plaintext = try decryptFile(at: manifestURL, key: key, associatedData: manifestAssociatedData)
        let manifest: Manifest
        do { manifest = try decoder.decode(Manifest.self, from: plaintext) }
        catch { throw MatrixChatServiceError.recoveryRequired }
        guard manifest.version == 1,
              Set(manifest.accountKeys).count == manifest.accountKeys.count,
              manifest.accountKeys.allSatisfy(Self.isValidAccountKey),
              manifest.activeAccountKey == nil || manifest.accountKeys.contains(manifest.activeAccountKey!) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return manifest
    }

    private func writeManifest(_ manifest: Manifest, key: Data) throws {
        try writeEncrypted(
            encoder.encode(manifest),
            to: manifestURL,
            key: key,
            associatedData: manifestAssociatedData
        )
    }

    private func loadAccount(accountKey: String, key: Data) throws -> AccountRecord? {
        let url = accountURL(accountKey: accountKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let plaintext = try decryptFile(
            at: url,
            key: key,
            associatedData: accountAssociatedData(accountKey: accountKey)
        )
        let record: AccountRecord
        do { record = try decoder.decode(AccountRecord.self, from: plaintext) }
        catch { throw MatrixChatServiceError.recoveryRequired }
        guard record.version == 1,
              record.accountKey == accountKey,
              record.session?.accountKey == nil || record.session?.accountKey == accountKey,
              record.storeKey == nil || record.storeKey?.count == 32,
              (record.credential == nil && record.password == nil) ||
                (record.credential?.id == accountKey &&
                 record.credential.map(HyphaMatrixKeychainCredentialStore.isValidCredential) == true &&
                 record.password?.isEmpty == false),
              record.legacyMigration == nil ||
                (record.legacyMigration?.version == 1 &&
                 record.legacyMigration?.originProcessIdentity.isEmpty == false &&
                 (record.legacyMigration?.verifiedProcessIdentity == nil ||
                  (record.legacyMigration?.verifiedProcessIdentity?.isEmpty == false &&
                   record.legacyMigration?.verifiedProcessIdentity != record.legacyMigration?.originProcessIdentity))),
              record.credentialMigration == nil ||
                (record.credential?.id == accountKey &&
                 record.password?.isEmpty == false &&
                 record.credentialMigration?.version == 1 &&
                 record.credentialMigration?.originProcessIdentity.isEmpty == false &&
                 (record.credentialMigration?.verifiedProcessIdentity == nil ||
                  (record.credentialMigration?.verifiedProcessIdentity?.isEmpty == false &&
                   record.credentialMigration?.verifiedProcessIdentity != record.credentialMigration?.originProcessIdentity))) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        return record
    }

    private func writeAccount(_ record: AccountRecord, key: Data) throws {
        guard Self.isValidAccountKey(record.accountKey) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        try writeEncrypted(
            encoder.encode(record),
            to: accountURL(accountKey: record.accountKey),
            key: key,
            associatedData: accountAssociatedData(accountKey: record.accountKey)
        )
    }

    private func encrypt(_ plaintext: Data, key: Data, associatedData: Data) throws -> Data {
        let sealed = try AES.GCM.seal(
            plaintext,
            using: SymmetricKey(data: key),
            authenticating: associatedData
        )
        guard let combined = sealed.combined else { throw MatrixChatServiceError.recoveryRequired }
        return combined
    }

    private func decryptFile(at url: URL, key: Data, associatedData: Data) throws -> Data {
        do {
            let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
            return try AES.GCM.open(
                sealed,
                using: SymmetricKey(data: key),
                authenticating: associatedData
            )
        } catch {
            throw MatrixChatServiceError.recoveryRequired
        }
    }

    private func writeEncrypted(
        _ plaintext: Data,
        to url: URL,
        key: Data,
        associatedData: Data
    ) throws {
        let ciphertext = try encrypt(plaintext, key: key, associatedData: associatedData)
        do {
            try ciphertext.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw MatrixChatServiceError.unavailable(reason: "Unable to update encrypted Matrix session storage")
        }
    }

    private func ensureDirectories() throws {
        do {
            try FileManager.default.createDirectory(at: accountsDirectory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: vaultDirectory.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: accountsDirectory.path)
        } catch {
            throw MatrixChatServiceError.unavailable(reason: "Unable to open encrypted Matrix session storage")
        }
    }

    private var manifestURL: URL { vaultDirectory.appendingPathComponent("manifest.enc") }
    private var accountsDirectory: URL { vaultDirectory.appendingPathComponent("accounts", isDirectory: true) }
    private func accountURL(accountKey: String) -> URL {
        accountsDirectory.appendingPathComponent("\(accountKey).enc")
    }
    private var manifestAssociatedData: Data {
        Data("zenith.matrix.session-vault|manifest|v1".utf8)
    }
    private func accountAssociatedData(accountKey: String) -> Data {
        Data("zenith.matrix.session-vault|account|\(accountKey)|v1".utf8)
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private static func secureRandomRootKey() throws -> Data {
        var data = Data(count: 32)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to create encrypted Matrix session key")
        }
        return data
    }

    private static func isValidAccountKey(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public typealias MatrixKeychainSessionVault = MatrixEncryptedSessionVault

public struct MatrixRustLiveClientFactory: MatrixLiveClientFactory {
    private let configuration: MatrixProductConfiguration
    private let rootDirectory: URL
    private let legacyRootDirectory: URL?

    public init(configuration: MatrixProductConfiguration, rootDirectory: URL? = nil) {
        self.configuration = configuration
        if let rootDirectory {
            self.rootDirectory = rootDirectory
            self.legacyRootDirectory = nil
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.rootDirectory = applicationSupport
                .appendingPathComponent("ZenithMacOSClient/Matrix", isDirectory: true)
            self.legacyRootDirectory = applicationSupport
                .appendingPathComponent(
                    ["Zenith", "Mobile", "MacOS"].joined() + "/Matrix",
                    isDirectory: true
                )
        }
    }

    public func make(accountKey: String, storeKey: Data) async throws -> any MatrixLiveClient {
        if let legacyRootDirectory {
            try Self.migrateLegacyRootIfNeeded(from: legacyRootDirectory, to: rootDirectory)
        }
        let storeDirectory = rootDirectory
            .appendingPathComponent("passphrase-v1", isDirectory: true)
            .appendingPathComponent(accountKey, isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: storeDirectory.path)
        let store = SqliteStoreBuilder(dataPath: storeDirectory.path, cachePath: storeDirectory.path)
            .passphrase(passphrase: storeKey.base64EncodedString())
        let client = try await ClientBuilder()
            .homeserverUrl(url: configuration.homeserver.absoluteString)
            .sqliteStore(config: store)
            .build()
        guard Self.matchesConfiguredHomeserver(client.homeserver(), configured: configuration.homeserver) else {
            throw MatrixChatServiceError.unavailable(reason: "Matrix SDK changed the configured homeserver")
        }
        return MatrixRustLiveClient(client: client)
    }

    static func migrateLegacyRootIfNeeded(
        from legacyRoot: URL,
        to renamedRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        guard legacyRoot.standardizedFileURL != renamedRoot.standardizedFileURL,
              fileManager.fileExists(atPath: legacyRoot.path),
              !fileManager.fileExists(atPath: renamedRoot.path) else { return }
        try fileManager.createDirectory(
            at: renamedRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: legacyRoot, to: renamedRoot)
    }

    public static func matchesConfiguredHomeserver(_ reported: String, configured: URL) -> Bool {
        guard let reportedComponents = URLComponents(string: reported),
              let configuredComponents = URLComponents(url: configured, resolvingAgainstBaseURL: false),
              reportedComponents.user == nil,
              reportedComponents.password == nil,
              reportedComponents.query == nil,
              reportedComponents.fragment == nil else {
            return false
        }

        func effectivePort(_ components: URLComponents) -> Int? {
            if let port = components.port { return port }
            switch components.scheme?.lowercased() {
            case "https": return 443
            case "http": return 80
            default: return nil
            }
        }

        func normalizedPath(_ components: URLComponents) -> String {
            var path = components.percentEncodedPath
            while path.count > 1 && path.hasSuffix("/") {
                path.removeLast()
            }
            return path == "/" ? "" : path
        }

        return reportedComponents.scheme?.lowercased() == configuredComponents.scheme?.lowercased()
            && reportedComponents.host?.lowercased() == configuredComponents.host?.lowercased()
            && effectivePort(reportedComponents) == effectivePort(configuredComponents)
            && normalizedPath(reportedComponents) == normalizedPath(configuredComponents)
    }
}

public actor MatrixRustLiveClient: MatrixLiveClient {
    private let client: Client
    private var roomByID: [String: Room] = [:]
    private var timelineByRoomID: [String: MatrixTimelineBinding] = [:]
    private var syncHandle: TaskHandle?
    private var syncListener: MatrixSyncListener?
    private var verificationSession: MatrixSASVerificationSession?
    private var crossSigningBootstrapHandle: CrossSigningBootstrapHandle?
    private var firstDeviceBootstrapInFlight = false

    public init(client: Client) { self.client = client }

    deinit {
        syncHandle?.cancel()
    }

    public func login(username: String, password: String) async throws {
        try await client.login(username: username, password: password, initialDeviceName: "Hypha", deviceId: nil)
    }

    public func restore(session: MatrixSDKSessionRecord) async throws {
        let version: SlidingSyncVersion = session.slidingSyncVersion == "native" ? .native : .none
        try await client.restoreSession(session: Session(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.userId,
            deviceId: session.deviceId,
            homeserverUrl: session.homeserverURL,
            oauthData: session.oauthData,
            slidingSyncVersion: version
        ))
    }

    public func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        let initial = try await client.changePassword(
            newPassword: newPassword,
            logoutDevices: logoutOtherDevices,
            currentPassword: nil,
            session: nil
        )
        switch initial {
        case .success:
            return
        case let .authenticationRequired(challenge):
            guard let session = challenge.session else {
                throw MatrixChatServiceError.invalidCredentials
            }
            let authenticated = try await client.changePassword(
                newPassword: newPassword,
                logoutDevices: logoutOtherDevices,
                currentPassword: currentPassword,
                session: session
            )
            guard authenticated == .success else {
                throw MatrixChatServiceError.invalidCredentials
            }
        }
    }

    public func sessionRecord(accountKey: String) async throws -> MatrixSDKSessionRecord {
        let session = try client.session()
        let version = session.slidingSyncVersion == .native ? "native" : "none"
        return MatrixSDKSessionRecord(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.userId,
            deviceId: session.deviceId,
            homeserverURL: session.homeserverUrl,
            oauthData: session.oauthData,
            slidingSyncVersion: version,
            accountKey: accountKey
        )
    }

    public func syncOnce() async throws {
        _ = try await client.syncOnceV2(settings: SyncSettingsV2(timeoutMs: 0, fullState: true))
    }

    public func startContinuousSync() async {
        guard syncHandle == nil else { return }
        let listener = MatrixSyncListener()
        syncListener = listener
        syncHandle = client.syncV2(
            settings: SyncSettingsV2(timeoutMs: 30_000, fullState: false),
            listener: listener
        )
    }

    public func stopContinuousSync() async {
        syncHandle?.cancel()
        syncHandle = nil
        syncListener = nil
    }

    public func joinedRooms() async throws -> [MatrixRoomSummary] {
        var summaries: [MatrixRoomSummary] = []
        var retained: [String: Room] = [:]
        for room in client.rooms() where room.membership() == .joined || room.membership() == .invited {
            let roomID = room.id()
            retained[roomID] = room
            let info = try? await room.roomInfo()
            let isCreatedByCurrentUser = info?.creators?.contains(room.ownUserId()) == true
            let canInviteMembers: Bool
            if room.membership() == .joined, let powerLevels = info?.powerLevels {
                canInviteMembers = (try? powerLevels.canUserInvite(userId: room.ownUserId())) ?? false
            } else {
                canInviteMembers = false
            }
            summaries.append(MatrixRoomSummary(
                id: roomID,
                name: room.displayName() ?? room.canonicalAlias() ?? roomID,
                isEncrypted: await room.isEncrypted(),
                hasInvite: room.membership() == .invited,
                isCreatedByCurrentUser: isCreatedByCurrentUser,
                isSpace: info?.isSpace == true,
                isDirect: await room.isDirect(),
                topic: info?.topic,
                canInviteMembers: canInviteMembers
            ))
        }
        roomByID = retained
        return summaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func lookupInviteUser(
        userID: String,
        roomID: String
    ) async throws -> MatrixUserLookupResult {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room invitation lookup is unavailable")
        }
        do {
            let profile = try await client.getProfile(userId: userID)
            guard profile.userId == userID else { return .unavailable }
            return .exists(userID: userID, displayName: profile.displayName)
        } catch let error as ClientError {
            if case let .MatrixApi(kind, _, _, _) = error, kind == .notFound {
                let inviteLink = try await room.matrixToPermalink()
                return .notFound(userID: userID, inviteLink: inviteLink)
            }
            throw error
        }
    }

    public func inviteUsers(_ request: MatrixRoomInviteRequest) async throws {
        guard let room = roomByID[request.roomID],
              room.membership() == .joined,
              !request.userIDs.isEmpty else {
            throw MatrixChatServiceError.unavailable(reason: "Room invitations are unavailable")
        }
        let powerLevels = try await room.getPowerLevels()
        guard try powerLevels.canUserInvite(userId: room.ownUserId()) else {
            throw MatrixChatServiceError.unavailable(reason: "Invite permission changed")
        }
        for userID in request.userIDs {
            try await room.inviteUserById(userId: userID)
        }
    }

    static func mapAuthoritativeDeviceVerificationState(
        _ state: AuthoritativeDeviceVerificationState
    ) -> MatrixDeviceTrustState {
        switch state {
        case .verifiedByCurrentSelfSigningKey: return .verifiedByCurrentSelfSigningKey
        case .unsigned: return .unsigned
        case .invalidSignature: return .invalidSignature
        case .unavailable: return .unavailable
        }
    }


    static func mapFirstDeviceTrustBootstrapState(
        _ state: AuthoritativeDeviceVerificationState
    ) -> MatrixFirstDeviceTrustBootstrapState {
        switch state {
        case .verifiedByCurrentSelfSigningKey: return .verifiedByCurrentSelfSigningKey
        case .unsigned: return .notBootstrapped
        case .invalidSignature: return .invalidSignature
        case .unavailable: return .unavailable
        }
    }

    static func mapTimelineEvent(_ event: EventTimelineItem) -> MatrixTimelineEvent? {
        let id: String
        switch event.eventOrTransactionId {
        case let .eventId(eventId): id = eventId
        case let .transactionId(transactionId): id = "txn-\(transactionId)"
        }

        let senderDisplayName: String
        if case let .ready(displayName, _, _, _, _) = event.senderProfile,
           let displayName,
           !displayName.isEmpty {
            senderDisplayName = displayName
        } else {
            senderDisplayName = event.sender
        }

        let mappedContent: MatrixTimelineEvent.Content
        switch event.content {
        case let .msgLike(content):
            switch content.kind {
            case let .message(message):
                switch message.msgType {
                case let .text(text):
                    mappedContent = .text(text.body)
                default:
                    mappedContent = .unsupported(type: event.eventTypeRaw ?? "m.room.message")
                }
            case .unableToDecrypt:
                mappedContent = .undecryptable(reason: "Waiting for Matrix room keys")
            default:
                mappedContent = .unsupported(type: event.eventTypeRaw ?? "m.room.message")
            }
        case let .failedToParseMessageLike(eventType, _):
            mappedContent = .unsupported(type: eventType)
        case let .failedToParseState(eventType, _, _):
            mappedContent = .unsupported(type: eventType)
        default:
            return nil
        }

        return MatrixTimelineEvent(
            id: id,
            senderDisplayName: senderDisplayName,
            senderID: event.sender,
            content: mappedContent,
            isOwn: event.isOwn,
            authenticity: mapTimelineAuthenticity(event.lazyProvider.getShields(strict: true)),
            timestamp: event.timestamp
        )
    }

    static func mapTimelineAuthenticity(_ shield: ShieldState) -> MatrixEventAuthenticity {
        let code: TimelineEventShieldStateCode
        switch shield {
        case .none:
            return .noWarning
        case let .red(value), let .grey(value):
            code = value
        }

        switch code {
        case .authenticityNotGuaranteed: return .authenticityNotGuaranteed
        case .unknownDevice: return .unknownDevice
        case .unsignedDevice: return .unsignedDevice
        case .unverifiedIdentity: return .unverifiedIdentity
        case .verificationViolation: return .verificationViolation
        case .mismatchedSender: return .mismatchedSender
        case .sentInClear: return .sentInClear
        }
    }

    public func timeline(roomID: String) async throws -> [MatrixTimelineEvent] {
        let binding = try await timelineBinding(roomID: roomID)
        return await binding.store.snapshot()
    }

    public func sendText(_ body: String, roomID: String) async throws {
        guard let room = roomByID[roomID], await room.isEncrypted() else {
            throw MatrixChatServiceError.trustViolation
        }
        let binding = try await timelineBinding(roomID: roomID)
        let messageType = MessageType.text(content: TextMessageContent(body: body, formatted: nil))
        guard let content = binding.timeline.createMessageContent(msgType: messageType) else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to encode Matrix message")
        }
        _ = try await binding.timeline.send(msg: content)
    }

    private func timelineBinding(roomID: String) async throws -> MatrixTimelineBinding {
        if let existing = timelineByRoomID[roomID] { return existing }
        guard let room = roomByID[roomID] else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        let timeline = try await room.timeline()
        let store = MatrixTimelineStore()
        let handle = await timeline.addListener(listener: store)
        _ = try await timeline.paginateBackwards(numEvents: 50)
        store.finishInitialLoad()
        let binding = MatrixTimelineBinding(timeline: timeline, store: store, handle: handle)
        timelineByRoomID[roomID] = binding
        return binding
    }

    public func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        let createsSpace = request.kind == .space
        let isPublic = request.visibility == .public
        let roomID = try await client.createRoom(request: CreateRoomParameters(
            name: request.name,
            topic: request.topic,
            isEncrypted: !createsSpace,
            visibility: isPublic ? .public : .private,
            preset: isPublic ? .publicChat : .privateChat,
            invite: request.invitees.isEmpty ? nil : request.invitees,
            isSpace: createsSpace
        ))

        var createdRoom: Room?
        for _ in 0..<50 {
            if let room = try client.getRoom(roomId: roomID) {
                createdRoom = room
                break
            }
            try await Task<Never, Never>.sleep(for: .milliseconds(100))
        }
        guard let room = createdRoom else {
            throw MatrixChatServiceError.unavailable(reason: "Created room was not returned by Matrix sync")
        }
        let isEncrypted = await room.isEncrypted()
        guard createsSpace || isEncrypted else {
            throw MatrixChatServiceError.trustViolation
        }

        roomByID[roomID] = room
        return MatrixRoomSummary(
            id: roomID,
            name: room.displayName() ?? room.canonicalAlias() ?? request.name,
            isEncrypted: !createsSpace,
            hasInvite: false,
            isCreatedByCurrentUser: true,
            isSpace: createsSpace,
            topic: request.topic
        )
    }

    public func removeRoom(roomID: String) async throws {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        let info = try await room.roomInfo()
        guard info.creators?.contains(room.ownUserId()) == true else {
            throw MatrixChatServiceError.unavailable(
                reason: "Only the account that created this room can remove it"
            )
        }
        try await room.leave()
        try await room.forget()
        roomByID.removeValue(forKey: roomID)
        timelineByRoomID.removeValue(forKey: roomID)
    }

    static func mapRecoveryState(
        _ state: RecoveryState,
        trustState: MatrixDeviceTrustState
    ) -> MatrixRecoveryState {
        switch state {
        case .unknown: return .unknown
        case .enabled:
            return trustState == .verifiedByCurrentSelfSigningKey ? .ready : .available
        case .disabled: return .unavailable
        case .incomplete: return .incomplete
        }
    }

    public func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState {
        let encryption = client.encryption()
        await encryption.waitForE2eeInitializationTasks()
        return Self.mapRecoveryState(encryption.recoveryState(), trustState: trustState)
    }

    public func setupEncryptionRecovery() async throws -> String {
        try await client.encryption().enableRecovery(
            waitForBackupsToUpload: true,
            passphrase: nil,
            progressListener: MatrixEnableRecoveryProgressListener()
        )
    }

    public func restoreEncryption(recoveryKey: String) async throws {
        let encryption = client.encryption()
        do {
            _ = try await encryption.authoritativeDeviceVerificationState()
        } catch {
            throw MatrixChatServiceError.recoveryFailed(stage: .identityRefresh)
        }
        let recoveryImportSucceeded: Bool
        do {
            try await encryption.recover(recoveryKey: recoveryKey)
            recoveryImportSucceeded = true
        } catch {
            recoveryImportSucceeded = false
        }
        guard let status = await encryption.crossSigningStatus() else {
            throw MatrixChatServiceError.recoveryFailed(
                stage: recoveryImportSucceeded ? .selfSigningKeyImport : .secretStorageUnlock
            )
        }
        if !recoveryImportSucceeded && !status.hasSelfSigningKey {
            throw MatrixChatServiceError.recoveryFailed(stage: .secretStorageUnlock)
        }
        guard status.hasSelfSigningKey else {
            throw MatrixChatServiceError.recoveryFailed(stage: .selfSigningKeyImport)
        }
        let sdkReceipt: CrossSigningDiagnosticReceipt
        do {
            sdkReceipt = try await encryption.diagnoseAndSignOwnDevice()
        } catch {
            throw MatrixChatServiceError.recoveryFailed(stage: .deviceSignatureUpload)
        }
        let uploadTransport: MatrixDiagnosticUploadTransport =
            sdkReceipt.uploadTransport == .accepted ? .accepted : .failed
        let uploadProcessing: MatrixDiagnosticUploadProcessing
        switch sdkReceipt.uploadProcessing {
        case .accepted: uploadProcessing = .accepted
        case .keyMismatch: uploadProcessing = .keyMismatch
        case .invalidSignature: uploadProcessing = .invalidSignature
        case .otherFailure: uploadProcessing = .otherFailure
        }
        var backupRepair: MatrixDiagnosticBackupRepair = .notAttempted
        if sdkReceipt.postUploadServerSignaturePresent {
            do {
                try await encryption.recoverAndFixBackup(recoveryKey: recoveryKey)
                backupRepair = .completed
            } catch {
                backupRepair = .failed
            }
        }
        let receipt = MatrixCrossSigningDiagnosticReceipt(
            publicIdentityRefreshed: sdkReceipt.publicIdentityRefreshed,
            privateSelfSigningKeyPresent: sdkReceipt.privateSelfSigningKeyPresent,
            privateSelfSigningKeyMatchesCurrentPublicIdentity:
                sdkReceipt.privateSelfSigningKeyMatchesCurrentPublicIdentity,
            localOwnDeviceKeyMatchesServerDeviceKey:
                sdkReceipt.localOwnDeviceKeyMatchesServerDeviceKey,
            signedObjectMatchesFreshServerDeviceObject:
                sdkReceipt.signedObjectMatchesFreshServerDeviceObject,
            generatedSignatureValidLocally: sdkReceipt.generatedSignatureValidLocally,
            uploadTransport: uploadTransport,
            uploadProcessing: uploadProcessing,
            postUploadServerSignaturePresent: sdkReceipt.postUploadServerSignaturePresent,
            backupRepair: backupRepair
        )
        guard receipt.postUploadServerSignaturePresent, receipt.backupRepair == .completed else {
            throw MatrixChatServiceError.recoveryDiagnostic(receipt: receipt)
        }
    }

    public func deviceTrustState() async throws -> MatrixDeviceTrustState {
        Self.mapAuthoritativeDeviceVerificationState(
            try await client.encryption().authoritativeDeviceVerificationState()
        )
    }

    public func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility {
        try await client.encryption().hasDevicesToVerifyAgainst()
            ? .eligiblePeer
            : .noEligiblePeer
    }

    public func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        guard !firstDeviceBootstrapInFlight else { return .bootstrapping }
        firstDeviceBootstrapInFlight = true
        defer { firstDeviceBootstrapInFlight = false }
        if crossSigningBootstrapHandle != nil { return .passwordRequired }
        let encryption = client.encryption()
        if let handle = try await encryption.bootstrapCrossSigningIfNeeded() {
            crossSigningBootstrapHandle = handle
            return .passwordRequired
        }
        return Self.mapFirstDeviceTrustBootstrapState(
            try await encryption.authoritativeDeviceVerificationState()
        )
    }

    public func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState {
        guard !firstDeviceBootstrapInFlight else { return .bootstrapping }
        firstDeviceBootstrapInFlight = true
        defer { firstDeviceBootstrapInFlight = false }
        guard let handle = crossSigningBootstrapHandle else { return .unavailable }
        guard try await handle.authWithPassword(password: password) == nil else {
            return .passwordRequired
        }
        crossSigningBootstrapHandle = nil
        return Self.mapFirstDeviceTrustBootstrapState(
            try await client.encryption().authoritativeDeviceVerificationState()
        )
    }


    public func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        let controller = try await client.getSessionVerificationController()
        let session = MatrixSASVerificationSession(controller: controller)
        verificationSession = session
        do {
            return try await session.requestChallenge()
        } catch {
            if verificationSession === session { verificationSession = nil }
            throw error
        }
    }

    public func approveDeviceVerification() async throws {
        guard let session = verificationSession else {
            throw MatrixChatServiceError.unavailable(reason: "No active device verification")
        }
        try await session.approveAndWaitForFinish()
        if verificationSession === session { verificationSession = nil }
    }

    public func declineDeviceVerification() async {
        guard let session = verificationSession else { return }
        await session.declineOrCancel()
        if verificationSession === session { verificationSession = nil }
    }

    public func logout() async throws { try await client.logout() }
}

private final class MatrixEnableRecoveryProgressListener: EnableRecoveryProgressListener, @unchecked Sendable {
    func onUpdate(status: EnableRecoveryProgress) {
        // The returned key is handled only by the setup call and its one-time UI.
        // Progress callbacks deliberately retain and log no recovery material.
    }
}

private final class MatrixSyncListener: SyncListenerV2, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "ca.zenithresearch.macos.client",
        category: "MatrixSync"
    )

    private let lock = NSLock()
    private var responseCount = 0

    func onUpdate(response: SyncResponseV2) {
        let count = lock.withLock {
            responseCount += 1
            return responseCount
        }
        Self.logger.notice("response=\(count, privacy: .public)")
    }
}

enum MatrixVerificationDiagnosticStage: String, Sendable {
    case controllerInstalled
    case requestSubmitting
    case waitingForAcceptance
    case acceptanceReceived
    case sasStarting
    case sasStartReturned
    case sasProtocolStarted
    case challengeReceived
    case approvalSubmitting
    case approvalSubmitted
    case cancelling
    case cancelled
    case failed
    case finished
}

enum MatrixVerificationFlowError: Error {
    case failed
    case cancelled
    case alreadyActive
}

final class MatrixSASVerificationSession: SessionVerificationControllerDelegate, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "ca.zenithresearch.macos.client",
        category: "MatrixVerification"
    )

    private let controller: SessionVerificationController
    private let stageObserver: @Sendable (MatrixVerificationDiagnosticStage) -> Void
    private let lock = NSLock()
    private var challengeContinuation: CheckedContinuation<MatrixVerificationChallenge, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var challengePresented = false
    private var sasStartSubmitted = false
    private var sasProtocolStarted = false
    private var terminal = false

    init(
        controller: SessionVerificationController,
        stageObserver: @escaping @Sendable (MatrixVerificationDiagnosticStage) -> Void = { _ in }
    ) {
        self.controller = controller
        self.stageObserver = stageObserver
        controller.setDelegate(delegate: self)
        record(.controllerInstalled)
    }

    deinit {
        controller.setDelegate(delegate: nil)
    }

    private func record(_ stage: MatrixVerificationDiagnosticStage) {
        Self.logger.notice("stage=\(stage.rawValue, privacy: .public)")
        stageObserver(stage)
    }

    func requestChallenge() async throws -> MatrixVerificationChallenge {
        try await withCheckedThrowingContinuation { continuation in
            let accepted = lock.withLock {
                guard challengeContinuation == nil, !terminal else { return false }
                challengeContinuation = continuation
                return true
            }
            guard accepted else {
                continuation.resume(throwing: MatrixVerificationFlowError.alreadyActive)
                return
            }
            Task { [controller, weak self] in
                do {
                    self?.record(.requestSubmitting)
                    try await controller.requestDeviceVerification()
                    self?.record(.waitingForAcceptance)
                } catch {
                    self?.fail(error)
                }
            }
        }
    }

    func approveAndWaitForFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let accepted = lock.withLock {
                guard finishContinuation == nil, !terminal else { return false }
                finishContinuation = continuation
                return true
            }
            guard accepted else {
                continuation.resume(throwing: MatrixVerificationFlowError.alreadyActive)
                return
            }
            Task { [controller, weak self] in
                do {
                    self?.record(.approvalSubmitting)
                    try await controller.approveVerification()
                    self?.record(.approvalSubmitted)
                } catch {
                    self?.fail(error)
                }
            }
        }
    }

    func declineOrCancel() async {
        record(.cancelling)
        let shouldDecline = lock.withLock { challengePresented }
        do {
            if shouldDecline {
                try await controller.declineVerification()
            } else {
                try await controller.cancelVerification()
            }
        } catch {
            fail(error)
            return
        }
        cancel()
    }

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {}

    func didAcceptVerificationRequest() {
        let shouldStart = lock.withLock {
            guard !terminal, !sasStartSubmitted else { return false }
            sasStartSubmitted = true
            return true
        }
        guard shouldStart else { return }

        record(.acceptanceReceived)
        Task { [controller, weak self] in
            await Task.yield()
            do {
                self?.record(.sasStarting)
                try await controller.startSasVerification()
                self?.record(.sasStartReturned)
            } catch {
                self?.fail(error)
            }
        }
    }

    func didStartSasVerification() {
        let first = lock.withLock {
            guard !sasProtocolStarted else { return false }
            sasProtocolStarted = true
            return true
        }
        if first {
            record(.sasProtocolStarted)
        }
    }

    func didReceiveVerificationData(data: SessionVerificationData) {
        record(.challengeReceived)
        let challenge: MatrixVerificationChallenge
        switch data {
        case let .emojis(emojis, _):
            challenge = .emojis(emojis.map {
                MatrixVerificationEmoji(symbol: $0.symbol(), description: $0.description())
            })
        case let .decimals(values):
            challenge = .decimals(values)
        }

        let continuation: CheckedContinuation<MatrixVerificationChallenge, Error>? = lock.withLock {
            guard !terminal else { return nil }
            challengePresented = true
            let pending = challengeContinuation
            challengeContinuation = nil
            return pending
        }
        continuation?.resume(returning: challenge)
    }

    func didFail() { fail(MatrixVerificationFlowError.failed) }
    func didCancel() { cancel() }

    func didFinish() {
        record(.finished)
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard !terminal else { return nil }
            terminal = true
            let pending = finishContinuation
            finishContinuation = nil
            challengeContinuation = nil
            return pending
        }
        continuation?.resume(returning: ())
    }

    private func cancel() {
        record(.cancelled)
        completeAll(throwing: MatrixVerificationFlowError.cancelled)
    }

    private func fail(_ error: Error) {
        record(.failed)
        completeAll(throwing: error)
    }

    private func completeAll(throwing error: Error) {
        let continuations: (
            CheckedContinuation<MatrixVerificationChallenge, Error>?,
            CheckedContinuation<Void, Error>?
        ) = lock.withLock {
            guard !terminal else { return (nil, nil) }
            terminal = true
            let challenge = challengeContinuation
            let finish = finishContinuation
            challengeContinuation = nil
            finishContinuation = nil
            return (challenge, finish)
        }
        continuations.0?.resume(throwing: error)
        continuations.1?.resume(throwing: error)
    }
}

private final class MatrixTimelineBinding: @unchecked Sendable {
    let timeline: Timeline
    let store: MatrixTimelineStore
    private let handle: TaskHandle

    init(timeline: Timeline, store: MatrixTimelineStore, handle: TaskHandle) {
        self.timeline = timeline
        self.store = store
        self.handle = handle
    }

    deinit { handle.cancel() }
}

private final class MatrixTimelineStore: TimelineListener, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TimelineItem] = []
    private var initialized = false
    private var waiters: [CheckedContinuation<[MatrixTimelineEvent], Never>] = []

    func onUpdate(diff: [TimelineDiff]) {
        let result: (snapshot: [MatrixTimelineEvent], waiters: [CheckedContinuation<[MatrixTimelineEvent], Never>]) = lock.withLock {
            for update in diff { apply(update) }
            initialized = true
            let snapshot = mappedSnapshot()
            let pending = waiters
            waiters.removeAll()
            return (snapshot, pending)
        }
        for waiter in result.waiters { waiter.resume(returning: result.snapshot) }
    }

    func finishInitialLoad() {
        let result: (snapshot: [MatrixTimelineEvent], waiters: [CheckedContinuation<[MatrixTimelineEvent], Never>]) = lock.withLock {
            initialized = true
            let snapshot = mappedSnapshot()
            let pending = waiters
            waiters.removeAll()
            return (snapshot, pending)
        }
        for waiter in result.waiters { waiter.resume(returning: result.snapshot) }
    }

    func snapshot() async -> [MatrixTimelineEvent] {
        await withCheckedContinuation { continuation in
            let immediate: [MatrixTimelineEvent]? = lock.withLock {
                if initialized { return mappedSnapshot() }
                waiters.append(continuation)
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
    }

    private func mappedSnapshot() -> [MatrixTimelineEvent] {
        items.compactMap { item in
            guard let event = item.asEvent() else { return nil }
            return MatrixRustLiveClient.mapTimelineEvent(event)
        }
    }

    private func apply(_ diff: TimelineDiff) {
        switch diff {
        case let .append(values):
            items.append(contentsOf: values)
        case .clear:
            items.removeAll()
        case let .pushFront(value):
            items.insert(value, at: 0)
        case let .pushBack(value):
            items.append(value)
        case .popFront:
            if !items.isEmpty { items.removeFirst() }
        case .popBack:
            if !items.isEmpty { items.removeLast() }
        case let .insert(index, value):
            let offset = min(Int(index), items.count)
            items.insert(value, at: offset)
        case let .set(index, value):
            let offset = Int(index)
            if items.indices.contains(offset) { items[offset] = value }
        case let .remove(index):
            let offset = Int(index)
            if items.indices.contains(offset) { items.remove(at: offset) }
        case let .truncate(length):
            if items.count > Int(length) { items.removeLast(items.count - Int(length)) }
        case let .reset(values):
            items = values
        }
    }
}
