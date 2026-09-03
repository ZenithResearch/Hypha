import CryptoKit
import Foundation
import MatrixRustSDK
import OSLog
import Security

private final class MatrixAsyncRaceGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Value, Error>, Never>?
    private var pendingResult: Result<Value, Error>?
    private var resolved = false

    func install(_ continuation: CheckedContinuation<Result<Value, Error>, Never>) {
        let result = lock.withLock { () -> Result<Value, Error>? in
            if let pendingResult {
                self.pendingResult = nil
                return pendingResult
            }
            self.continuation = continuation
            return nil
        }
        if let result { continuation.resume(returning: result) }
    }

    func resolve(_ result: Result<Value, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<Result<Value, Error>, Never>? in
            guard !resolved else { return nil }
            resolved = true
            guard let continuation = self.continuation else {
                pendingResult = result
                return nil
            }
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: result)
    }
}

public struct MatrixSDKSessionRecord: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let userId: String
    public let deviceId: String
    public let homeserverURL: String
    public let oauthData: String?
    public let slidingSyncVersion: String
    public let accountKey: String
    public let storeNamespace: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        userId: String,
        deviceId: String,
        homeserverURL: String,
        oauthData: String? = nil,
        slidingSyncVersion: String,
        accountKey: String,
        storeNamespace: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.deviceId = deviceId
        self.homeserverURL = homeserverURL
        self.oauthData = oauthData
        self.slidingSyncVersion = slidingSyncVersion
        self.accountKey = accountKey
        self.storeNamespace = storeNamespace
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
    func deleteStoreKey(accountKey: String) throws
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

    func deleteStoreKey(accountKey: String) throws {}
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
            accountKey: existingSession.accountKey,
            storeNamespace: existingSession.storeNamespace
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
    func homeserverUsers() async throws -> [MatrixHomeserverUser]
    func homeserverRooms() async throws -> [MatrixHomeserverRoom]
    func timeline(roomID: String) async throws -> [MatrixTimelineEvent]
    func sendText(_ body: String, roomID: String) async throws
    func roomRepositoryState(roomID: String) async throws -> MatrixRoomRepositoryState
    func setRoomRepositorySet(
        _ repositorySet: MatrixRoomRepositorySet,
        roomID: String
    ) async throws -> MatrixRoomRepositorySetWriteResult
    func roomTemplateReference(roomID: String) async throws -> HyphaRoomTemplateReference?
    func setRoomTemplateReference(
        _ reference: HyphaRoomTemplateReference,
        roomID: String
    ) async throws
    func roomRepositoryAttachment(roomID: String) async throws -> MatrixRoomRepositoryAttachment?
    func setRoomRepositoryAttachment(
        _ attachment: MatrixRoomRepositoryAttachment,
        roomID: String
    ) async throws
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws
    func acceptInvitation(roomID: String) async throws
    func declineInvitation(roomID: String) async throws
    func removeRoom(roomID: String) async throws
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState
    func setupEncryptionRecovery() async throws -> String
    func restoreEncryption(recoveryKey: String) async throws
    func beginEncryptionIdentityReset() async throws -> MatrixRecoveryIdentityResetAuthorization
    func continueEncryptionIdentityReset(password: String) async throws -> Bool
    func continueEncryptionIdentityResetAfterOAuth() async throws
    func createReplacementEncryptionRecoveryKey() async throws -> String
    func deviceTrustState() async throws -> MatrixDeviceTrustState
    func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge
    func acceptIncomingDeviceVerification() async throws
    func approveDeviceVerification() async throws
    func declineDeviceVerification() async
    func setIncomingDeviceVerificationHandler(
        _ handler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    ) async throws
    func logout() async throws
}

struct MatrixRecoveryIdentityResetLifecycle {
    enum BeginAction: Equatable {
        case startIdentityReset
        case reuseAuthorization(MatrixRecoveryIdentityResetAuthorization)
        case identityResetAlreadyCommitted
        case authorizationBlocked
        case identityResetIndeterminate
        case operationInFlight
    }

    private enum Phase: Equatable {
        case idle
        case beginning
        case authorizationRequired(MatrixRecoveryIdentityResetAuthorization)
        case continuingPassword
        case continuingOAuth(URL)
        case identityResetCommitted
        case creatingReplacementKey
        case replacementKeyCreated
        case authorizationBlocked
        case identityResetIndeterminate
    }

    private var phase: Phase = .idle

    mutating func begin() -> BeginAction {
        switch phase {
        case .idle:
            phase = .beginning
            return .startIdentityReset
        case .beginning:
            return .operationInFlight
        case .continuingPassword, .continuingOAuth:
            return .operationInFlight
        case let .authorizationRequired(authorization):
            return .reuseAuthorization(authorization)
        case .identityResetCommitted:
            return .identityResetAlreadyCommitted
        case .creatingReplacementKey, .replacementKeyCreated:
            return .identityResetAlreadyCommitted
        case .authorizationBlocked:
            return .authorizationBlocked
        case .identityResetIndeterminate:
            return .identityResetIndeterminate
        }
    }

    mutating func didBegin(requiring authorization: MatrixRecoveryIdentityResetAuthorization) {
        if authorization == .completed {
            phase = .identityResetCommitted
        } else {
            phase = .authorizationRequired(authorization)
        }
    }

    mutating func didFailAfterDestructiveInvocation() {
        if phase == .beginning { phase = .identityResetIndeterminate }
    }

    mutating func didCommitIdentityReset() {
        phase = .identityResetCommitted
    }

    mutating func didBlockAuthorization() {
        phase = .authorizationBlocked
    }

    mutating func beginPasswordContinuation() -> Bool {
        guard phase == .authorizationRequired(.password) else { return false }
        phase = .continuingPassword
        return true
    }

    mutating func didRejectPasswordContinuation() {
        if phase == .continuingPassword {
            phase = .authorizationRequired(.password)
        }
    }

    mutating func beginOAuthContinuation() -> Bool {
        guard case let .authorizationRequired(.oauth(approvalURL)) = phase else { return false }
        phase = .continuingOAuth(approvalURL)
        return true
    }

    mutating func didRejectOAuthContinuation() {
        guard case let .continuingOAuth(approvalURL) = phase else { return }
        phase = .authorizationRequired(.oauth(approvalURL: approvalURL))
    }

    mutating func beginReplacementKeyCreation() -> Bool {
        guard phase == .identityResetCommitted else { return false }
        phase = .creatingReplacementKey
        return true
    }

    mutating func didFailReplacementKeyCreation() {
        if phase == .creatingReplacementKey {
            phase = .identityResetCommitted
        }
    }

    mutating func didCreateReplacementKey() {
        if phase == .creatingReplacementKey {
            phase = .replacementKeyCreated
        }
    }

    var canCreateReplacementRecoveryKey: Bool {
        phase == .identityResetCommitted
    }

    var canContinueWithPassword: Bool {
        phase == .authorizationRequired(.password)
    }

    var canContinueAfterOAuth: Bool {
        if case .authorizationRequired(.oauth) = phase { return true }
        return false
    }
}

public extension MatrixLiveClient {
    func homeserverUsers() async throws -> [MatrixHomeserverUser] {
        throw MatrixChatServiceError.unavailable(reason: "The homeserver user directory is unavailable")
    }

    func homeserverRooms() async throws -> [MatrixHomeserverRoom] {
        throw MatrixChatServiceError.unavailable(reason: "The homeserver room directory is unavailable")
    }
    func roomTemplateReference(roomID: String) async throws -> HyphaRoomTemplateReference? { nil }

    func setRoomTemplateReference(
        _ reference: HyphaRoomTemplateReference,
        roomID: String
    ) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room templates are unavailable")
    }

    func roomRepositoryAttachment(roomID: String) async throws -> MatrixRoomRepositoryAttachment? { nil }

    func roomRepositoryState(roomID: String) async throws -> MatrixRoomRepositoryState {
        guard let attachment = try await roomRepositoryAttachment(roomID: roomID) else {
            return .empty
        }
        return MatrixRoomRepositoryState(
            repositorySet: try MatrixRoomRepositorySet.migrating(attachment),
            source: .legacy,
            mirrorStatus: .current
        )
    }

    func setRoomRepositorySet(
        _ repositorySet: MatrixRoomRepositorySet,
        roomID: String
    ) async throws -> MatrixRoomRepositorySetWriteResult {
        guard let mirror = repositorySet.legacyMirror else {
            throw MatrixChatServiceError.unavailable(reason: "Repository collection clearing is unavailable")
        }
        try await setRoomRepositoryAttachment(mirror, roomID: roomID)
        return .applied
    }

    func setRoomRepositoryAttachment(
        _ attachment: MatrixRoomRepositoryAttachment,
        roomID: String
    ) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room repository attachments are unavailable")
    }

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
    func acceptInvitation(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Invitation acceptance is unavailable")
    }
    func declineInvitation(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Invitation decline is unavailable")
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
    func beginEncryptionIdentityReset() async throws -> MatrixRecoveryIdentityResetAuthorization {
        throw MatrixChatServiceError.unavailable(reason: "Encryption identity reset is unavailable")
    }
    func continueEncryptionIdentityReset(password: String) async throws -> Bool {
        throw MatrixChatServiceError.unavailable(reason: "Encryption identity reset is unavailable")
    }
    func continueEncryptionIdentityResetAfterOAuth() async throws {
        throw MatrixChatServiceError.unavailable(reason: "Encryption identity reset is unavailable")
    }
    func createReplacementEncryptionRecoveryKey() async throws -> String {
        throw MatrixChatServiceError.unavailable(reason: "Replacement recovery-key creation is unavailable")
    }
    func deviceTrustState() async throws -> MatrixDeviceTrustState { .unavailable }
    func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility { .unavailable }
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState { .unavailable }
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState { .unavailable }
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func acceptIncomingDeviceVerification() async throws {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func approveDeviceVerification() async throws {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func declineDeviceVerification() async {}
    func setIncomingDeviceVerificationHandler(
        _ handler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    ) async throws {}
}

public protocol MatrixLiveClientFactory: Sendable {
    func make(accountKey: String, storeKey: Data) async throws -> any MatrixLiveClient
    func resetStore(accountKey: String) async throws
}

public extension MatrixLiveClientFactory {
    func resetStore(accountKey: String) async throws {}
}

public actor MatrixRustSDKChatService: MatrixChatService {
    public typealias RandomStoreKey = @Sendable () throws -> Data
    public typealias AdministratorClientFactory = @Sendable (URL, String, String) -> any MatrixAdminClient

    private struct AdministratorSessionBinding: Equatable, Sendable {
        let accountKey: String
        let userID: String
        let deviceID: String
        let homeserverURL: String
    }

    private let configuration: MatrixProductConfiguration
    private let vault: any MatrixSDKSessionVault
    private let clientFactory: any MatrixLiveClientFactory
    private let passwordSessionReauthenticator: any MatrixPasswordSessionReauthenticating
    private let administratorClientFactory: AdministratorClientFactory
    private let randomStoreKey: RandomStoreKey
    private var transactionClient: (any MatrixLiveClient)?
    private var incomingVerificationHandler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    private var activeSession: MatrixSDKSessionRecord?
    private var roomsByID: [String: MatrixRoomSummary] = [:]
    private var firstDeviceBootstrapInFlight = false
    private var primarySessionTransitionInFlight = false
    private var primarySessionOperationsInFlight = 0

    private var client: (any MatrixLiveClient)? {
        get {
            guard !primarySessionTransitionInFlight else { return nil }
            return transactionClient
        }
        set { transactionClient = newValue }
    }

    public init(
        configuration: MatrixProductConfiguration,
        vault: any MatrixSDKSessionVault,
        clientFactory: any MatrixLiveClientFactory,
        passwordSessionReauthenticator: any MatrixPasswordSessionReauthenticating = MatrixPasswordSessionReauthenticator(),
        administratorClientFactory: @escaping AdministratorClientFactory = { homeserver, userID, accessToken in
            MatrixSynapseAdminClient(homeserver: homeserver, currentUserID: userID, accessToken: accessToken)
        },
        randomStoreKey: @escaping RandomStoreKey = { try MatrixRustSDKChatService.secureRandomStoreKey() }
    ) {
        self.configuration = configuration
        self.vault = vault
        self.clientFactory = clientFactory
        self.passwordSessionReauthenticator = passwordSessionReauthenticator
        self.administratorClientFactory = administratorClientFactory
        self.randomStoreKey = randomStoreKey
    }

    public func restore() async throws -> [MatrixRoomSummary] {
        try reservePrimarySessionTransition()
        defer { primarySessionTransitionInFlight = false }
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

        let liveClient = try await clientFactory.make(
            accountKey: session.storeNamespace ?? session.accountKey,
            storeKey: storeKey
        )
        do {
            try await liveClient.restore(session: session)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Matrix session restore failed")
        }
        let rooms = try await loadInitialRooms(with: liveClient)
        try vault.finalizeLegacyMigrationAfterRestore(accountKey: session.accountKey)
        try await activate(liveClient, session: session, rooms: rooms)
        return rooms
    }

    public func signIn(username: String, password: String) async throws -> [MatrixRoomSummary] {
        try reservePrimarySessionTransition()
        defer { primarySessionTransitionInFlight = false }
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
            try await activate(liveClient, session: refreshedSession, rooms: rooms)
            return rooms
        }

        if let abandonedStoreKey = try vault.loadStoreKey(accountKey: accountKey) {
            guard abandonedStoreKey.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
            try await clientFactory.resetStore(accountKey: accountKey)
            try vault.deleteStoreKey(accountKey: accountKey)
        }
        let storeKey = try randomStoreKey()
        guard storeKey.count == 32 else {
            throw MatrixChatServiceError.unavailable(reason: "Unable to create encrypted Matrix store")
        }
        try vault.saveStoreKey(storeKey, accountKey: accountKey)

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
        try await activate(liveClient, session: record, rooms: rooms)
        return rooms
    }

    public func setIncomingDeviceVerificationHandler(
        _ handler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    ) async {
        guard (try? beginPrimarySessionOperation()) != nil else { return }
        defer { endPrimarySessionOperation() }
        incomingVerificationHandler = handler
        try? await client?.setIncomingDeviceVerificationHandler(handler)
    }

    public func refreshRooms() async throws -> [MatrixRoomSummary] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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

    public func homeserverUsers() async throws -> [MatrixHomeserverUser] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.homeserverUsers()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "The homeserver user directory could not be loaded")
        }
    }

    public func homeserverRooms() async throws -> [MatrixHomeserverRoom] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.homeserverRooms()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "The homeserver room directory could not be loaded")
        }
    }

    public func timeline(for roomID: String) async throws -> [MatrixTimelineEvent] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        return try await client.timeline(roomID: roomID)
    }

    public func sendText(_ body: String, to roomID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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

    public func roomRepositoryState(roomID: String) async throws -> MatrixRoomRepositoryState {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository state is unavailable")
        }
        do {
            return try await client.roomRepositoryState(roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room repository state could not be read")
        }
    }

    public func setRoomRepositorySet(
        _ repositorySet: MatrixRoomRepositorySet,
        roomID: String
    ) async throws -> MatrixRoomRepositorySetWriteResult {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository state is unavailable")
        }
        do {
            return try await client.setRoomRepositorySet(repositorySet, roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room repository state could not be saved")
        }
    }

    public func roomTemplateReference(roomID: String) async throws -> HyphaRoomTemplateReference? {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room template state is unavailable")
        }
        do {
            return try await client.roomTemplateReference(roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room template state could not be read")
        }
    }

    public func setRoomTemplateReference(
        _ reference: HyphaRoomTemplateReference,
        roomID: String
    ) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room template state is unavailable")
        }
        do {
            try await client.setRoomTemplateReference(reference, roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room template state could not be saved")
        }
    }

    public func roomRepositoryAttachment(roomID: String) async throws -> MatrixRoomRepositoryAttachment? {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment is unavailable")
        }
        do {
            return try await client.roomRepositoryAttachment(roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room repository attachment could not be read")
        }
    }

    public func setRoomRepositoryAttachment(
        _ attachment: MatrixRoomRepositoryAttachment,
        roomID: String
    ) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client,
              let room = roomsByID[roomID],
              !room.hasInvite,
              !room.isSpace else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment is unavailable")
        }
        do {
            try await client.setRoomRepositoryAttachment(attachment, roomID: roomID)
        } catch let error as MatrixChatServiceError {
            throw error
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room repository attachment could not be saved")
        }
    }

    public func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room invitation failed")
        }
    }

    public func acceptInvitation(roomID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard let room = roomsByID[roomID], room.hasInvite else {
            throw MatrixChatServiceError.unavailable(reason: "This room invitation is no longer pending")
        }
        do {
            try await client.acceptInvitation(roomID: roomID)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room invitation acceptance failed")
        }
    }

    public func declineInvitation(roomID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        guard let room = roomsByID[roomID], room.hasInvite else {
            throw MatrixChatServiceError.unavailable(reason: "This room invitation is no longer pending")
        }
        do {
            try await client.declineInvitation(roomID: roomID)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Room invitation decline failed")
        }
    }

    public func removeRoom(roomID: String) async throws -> [MatrixRoomSummary] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.encryptionRecoveryState(trustState: trustState)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery status unavailable")
        }
    }

    public func setupEncryptionRecovery() async throws -> String {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.setupEncryptionRecovery()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery setup failed")
        }
    }

    public func restoreEncryption(recoveryKey: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.restoreEncryption(recoveryKey: recoveryKey)
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Encryption recovery failed")
        }
    }

    public func beginEncryptionIdentityReset() async throws -> MatrixRecoveryIdentityResetAuthorization {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        return try await client.beginEncryptionIdentityReset()
    }

    public func continueEncryptionIdentityReset(password: String) async throws -> Bool {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        return try await client.continueEncryptionIdentityReset(password: password)
    }

    public func continueEncryptionIdentityResetAfterOAuth() async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        try await client.continueEncryptionIdentityResetAfterOAuth()
    }

    public func createReplacementEncryptionRecoveryKey() async throws -> String {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        return try await client.createReplacementEncryptionRecoveryKey()
    }

    public func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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

    public func requestHomeserverPasswordReset() async throws -> MatrixPasswordResetRequest {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primarySessionClient().requestPasswordReset()
    }

    public func currentHomeserverPasswordResetRequest() async throws -> MatrixPasswordResetRequest? {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primarySessionClient().currentPasswordResetRequest()
    }

    public func completeHomeserverPasswordResetRequest() async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        try await primarySessionClient().completePasswordResetRequest()
    }




    public func isHomeserverAdministrator() async throws -> Bool {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().isAdministrator()
    }

    public func administratorSnapshot() async throws -> MatrixAdminSnapshot {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().snapshot()
    }

    public func administratorPasswordResetRequests(
        users: [MatrixAdminUserSummary]
    ) async throws -> [MatrixPasswordResetRequest] {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().passwordResetRequests(users: users)
    }

    public func resetAdministratorManagedPassword(
        for request: MatrixPasswordResetRequest,
        temporaryPassword: String
    ) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        try await primaryAdministratorClient().resetPassword(
            for: request,
            temporaryPassword: temporaryPassword
        )
    }

    public func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().createAccount(
            localpart: localpart,
            temporaryPassword: temporaryPassword,
            administrator: administrator
        )
    }

    public func setAdministratorManagedAccount(
        userID: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().setAdministrator(
            userID: userID,
            administrator: administrator
        )
    }

    public func deactivateAdministratorManagedAccount(userID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        try await primaryAdministratorClient().deactivateAccount(userID: userID)
    }

    public func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        return try await primaryAdministratorClient().createRoom(name: name, topic: topic, asSpace: asSpace, visibility: visibility)
    }

    public func logoutAdministratorManagedAccount(userID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        try await primaryAdministratorClient().logoutAccount(userID: userID)
    }

    public func purgeAdministratorManagedRoom(roomID: String) async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        try await primaryAdministratorClient().purgeRoom(roomID: roomID)
    }

    public func deviceTrustState() async throws -> MatrixDeviceTrustState {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.deviceTrustState()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device trust state unavailable")
        }
    }

    public func peerVerificationEligibility() async -> MatrixPeerVerificationEligibility {
        guard (try? beginPrimarySessionOperation()) != nil else { return .unavailable }
        defer { endPrimarySessionOperation() }
        guard let client else { return .unavailable }
        do {
            return try await client.peerVerificationEligibility()
        } catch {
            return .unavailable
        }
    }

    public func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
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
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            return try await client.requestDeviceVerification()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device verification request failed")
        }
    }

    public func acceptIncomingDeviceVerification() async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.acceptIncomingDeviceVerification()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device verification acceptance failed")
        }
    }

    public func approveDeviceVerification() async throws {
        try beginPrimarySessionOperation()
        defer { endPrimarySessionOperation() }
        guard let client else { throw MatrixChatServiceError.sessionExpired }
        do {
            try await client.approveDeviceVerification()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Device verification approval failed")
        }
    }

    public func declineDeviceVerification() async {
        guard (try? beginPrimarySessionOperation()) != nil else { return }
        defer { endPrimarySessionOperation() }
        guard let client else { return }
        await client.declineDeviceVerification()
    }

    public func suspend() async -> Bool {
        guard !primarySessionTransitionInFlight,
              primarySessionOperationsInFlight == 0 else { return false }
        primarySessionTransitionInFlight = true
        defer { primarySessionTransitionInFlight = false }
        if let client = transactionClient {
            await client.stopContinuousSync()
        }
        self.client = nil
        activeSession = nil
        roomsByID = [:]
        return true
    }

    public func logout() async throws {
        try reservePrimarySessionTransition()
        defer { primarySessionTransitionInFlight = false }
        var remoteLogoutError: Error?
        if let client = transactionClient {
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
            return try await client.joinedRooms()
        } catch {
            throw mapRuntimeError(error, fallbackReason: "Initial Matrix room load failed")
        }
    }

    private func activate(
        _ client: any MatrixLiveClient,
        session: MatrixSDKSessionRecord,
        rooms: [MatrixRoomSummary]
    ) async throws {
        self.client = client
        activeSession = session
        remember(rooms)
        try? await client.setIncomingDeviceVerificationHandler(incomingVerificationHandler)
        await client.startContinuousSync()
    }

    private func currentAdministratorBinding() throws -> AdministratorSessionBinding {
        guard transactionClient != nil, let activeSession else {
            throw MatrixChatServiceError.sessionExpired
        }
        guard MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
            activeSession.homeserverURL,
            configured: configuration.homeserver
        ) else {
            throw MatrixChatServiceError.unavailable(reason: "Active session belongs to another homeserver")
        }
        return AdministratorSessionBinding(
            accountKey: activeSession.accountKey,
            userID: activeSession.userId,
            deviceID: activeSession.deviceId,
            homeserverURL: activeSession.homeserverURL
        )
    }

    private func reservePrimarySessionTransition() throws {
        guard !primarySessionTransitionInFlight else {
            throw MatrixChatServiceError.unavailable(
                reason: "Another primary Matrix session operation is already in progress"
            )
        }
        guard primarySessionOperationsInFlight == 0 else {
            throw MatrixChatServiceError.unavailable(
                reason: "A primary Matrix operation is still in progress"
            )
        }
        primarySessionTransitionInFlight = true
    }

    private func beginPrimarySessionOperation() throws {
        guard !primarySessionTransitionInFlight else {
            throw MatrixChatServiceError.unavailable(
                reason: "Primary Matrix session transition is already in progress"
            )
        }
        primarySessionOperationsInFlight += 1
    }

    private func endPrimarySessionOperation() {
        precondition(primarySessionOperationsInFlight > 0)
        primarySessionOperationsInFlight -= 1
    }

    private func primarySessionClient() throws -> MatrixSynapseAdminClient {
        _ = try currentAdministratorBinding()
        guard let activeSession else { throw MatrixChatServiceError.sessionExpired }
        return MatrixSynapseAdminClient(
            homeserver: configuration.homeserver,
            currentUserID: activeSession.userId,
            accessToken: activeSession.accessToken
        )
    }

    private func primaryAdministratorClient() throws -> any MatrixAdminClient {
        _ = try currentAdministratorBinding()
        guard let activeSession else { throw MatrixChatServiceError.sessionExpired }
        return administratorClientFactory(
            configuration.homeserver,
            activeSession.userId,
            activeSession.accessToken
        )
    }


    private func remember(_ rooms: [MatrixRoomSummary]) {
        roomsByID = rooms.reduce(into: [:]) { result, room in
            result[room.id] = room
        }
    }

    private func mapLoginError(_ error: Error) -> MatrixChatServiceError {
        if case let ClientError.MatrixApi(kind, code, _, _)? = error as? ClientError {
            switch code.uppercased() {
            case "M_USER_AWAITING_APPROVAL":
                return .unavailable(reason: "Account is awaiting homeserver approval")
            case "M_USER_DEACTIVATED":
                return .unavailable(reason: "Account has been deleted or deactivated")
            default:
                break
            }
            if kind == .forbidden || code.uppercased() == "M_FORBIDDEN" {
                return .invalidCredentials
            }
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

    private let service: String
    private let legacyService: String?
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

    public convenience init(identity: MatrixPlatformStorageIdentity = .current) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            storage: SecurityMatrixKeychainDataStorage(),
            vaultDirectory: base
                .appendingPathComponent(identity.vaultRoot, isDirectory: true),
            identity: identity,
            randomRootKey: { try Self.secureRandomRootKey() }
        )
    }

    init(
        storage: any MatrixKeychainDataStorage,
        vaultDirectory: URL,
        processIdentity: String = MatrixEncryptedSessionVault.currentProcessIdentity,
        identity: MatrixPlatformStorageIdentity = .macOS,
        randomRootKey: @escaping RandomRootKey
    ) {
        self.storage = storage
        self.vaultDirectory = vaultDirectory
        self.processIdentity = processIdentity
        self.service = identity.keychainService
        self.legacyService = identity.legacyKeychainService
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

    public func deleteStoreKey(accountKey: String) throws {
        try synchronized {
            guard Self.isValidAccountKey(accountKey) else {
                throw MatrixChatServiceError.recoveryRequired
            }
            let key = try prepareVault()
            guard var record = try loadAccount(accountKey: accountKey, key: key) else { return }
            record.storeKey = nil
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

        for sourceService in legacySourceServices {
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
        for sourceService in legacySourceServices {
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
        for sourceService in legacySourceServices {
            if let data = try storage.read(service: sourceService, account: "store-key:\(accountKey)") {
                guard data.count == 32 else { throw MatrixChatServiceError.recoveryRequired }
                return data
            }
        }
        return nil
    }

    private var legacySourceServices: [String] {
        [service] + (legacyService.map { [$0] } ?? [])
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

    public init(
        configuration: MatrixProductConfiguration,
        rootDirectory: URL? = nil,
        identity: MatrixPlatformStorageIdentity = .current
    ) {
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
                .appendingPathComponent(identity.cryptoRoot, isDirectory: true)
            self.legacyRootDirectory = identity.legacyCryptoRoot.map {
                applicationSupport.appendingPathComponent($0, isDirectory: true)
            }
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

    public func resetStore(accountKey: String) async throws {
        guard accountKey.count == 64,
              accountKey.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw MatrixChatServiceError.recoveryRequired
        }
        let storeDirectory = rootDirectory
            .appendingPathComponent("passphrase-v1", isDirectory: true)
            .appendingPathComponent(accountKey, isDirectory: true)
        if FileManager.default.fileExists(atPath: storeDirectory.path) {
            try FileManager.default.removeItem(at: storeDirectory)
        }
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

enum MatrixRoomNameResolution {
    static func resolve(
        rawName: String?,
        roomInfoDisplayName: String?,
        roomDisplayName: String?,
        canonicalAlias: String?,
        fallback: String
    ) -> String {
        [rawName, roomInfoDisplayName, roomDisplayName, canonicalAlias]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty }) ?? fallback
    }
}

final class MatrixRoomDirectoryEntriesCollector: RoomDirectorySearchEntriesListener, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [RoomDescription] = []

    func onUpdate(roomEntriesUpdate updates: [RoomDirectorySearchEntryUpdate]) {
        lock.lock()
        defer { lock.unlock() }
        for update in updates {
            switch update {
            case let .append(values):
                entries.append(contentsOf: values)
            case .clear:
                entries.removeAll()
            case let .pushFront(value):
                entries.insert(value, at: 0)
            case let .pushBack(value):
                entries.append(value)
            case .popFront:
                if !entries.isEmpty { entries.removeFirst() }
            case .popBack:
                if !entries.isEmpty { entries.removeLast() }
            case let .insert(index, value):
                entries.insert(value, at: min(Int(index), entries.count))
            case let .set(index, value):
                guard Int(index) < entries.count else { continue }
                entries[Int(index)] = value
            case let .remove(index):
                guard Int(index) < entries.count else { continue }
                entries.remove(at: Int(index))
            case let .truncate(length):
                if entries.count > Int(length) {
                    entries.removeLast(entries.count - Int(length))
                }
            case let .reset(values):
                entries = values
            }
        }
    }

    func snapshot() -> [RoomDescription] {
        lock.lock()
        defer { lock.unlock() }
        return entries
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
    private var recoveryIdentityResetHandle: IdentityResetHandle?
    private var recoveryIdentityResetLifecycle = MatrixRecoveryIdentityResetLifecycle()
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
        try await prepareKnownRoomTimelinesForSync()
        _ = try await client.syncOnceV2(settings: SyncSettingsV2(timeoutMs: 0, fullState: true))
    }

    private func prepareKnownRoomTimelinesForSync() async throws {
        let knownRooms = try await joinedRooms()
        for room in knownRooms where !room.hasInvite && !room.isSpace {
            _ = try await timelineBinding(roomID: room.id)
        }
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
                name: MatrixRoomNameResolution.resolve(
                    rawName: info?.rawName,
                    roomInfoDisplayName: info?.displayName,
                    roomDisplayName: room.displayName(),
                    canonicalAlias: room.canonicalAlias(),
                    fallback: roomID
                ),
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

    public func homeserverUsers() async throws -> [MatrixHomeserverUser] {
        let ownUserID = try client.userId()
        guard let ownServerName = Self.serverName(in: ownUserID) else {
            throw MatrixChatServiceError.unavailable(reason: "The signed-in Matrix user ID is invalid")
        }
        let search = try await client.searchUsers(searchTerm: "", limit: 1_000)
        var users: [String: MatrixHomeserverUser] = [:]
        for profile in search.results {
            guard Self.serverName(in: profile.userId)?.caseInsensitiveCompare(ownServerName) == .orderedSame else {
                continue
            }
            users[profile.userId] = MatrixHomeserverUser(
                id: profile.userId,
                displayName: profile.displayName,
                avatarURL: profile.avatarUrl
            )
        }
        if users[ownUserID] == nil, let profile = try? await client.getProfile(userId: ownUserID) {
            users[ownUserID] = MatrixHomeserverUser(
                id: ownUserID,
                displayName: profile.displayName,
                avatarURL: profile.avatarUrl
            )
        }
        return users.values.sorted {
            let left = $0.displayName?.isEmpty == false ? $0.displayName! : $0.id
            let right = $1.displayName?.isEmpty == false ? $1.displayName! : $1.id
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    public func homeserverRooms() async throws -> [MatrixHomeserverRoom] {
        let directory = client.roomDirectorySearch()
        let collector = MatrixRoomDirectoryEntriesCollector()
        let listenerHandle = await directory.results(listener: collector)
        defer { listenerHandle.cancel() }

        try await directory.search(filter: nil, batchSize: 100, viaServerName: nil)
        while try await !directory.isAtLastPage() {
            let loadedPages = try await directory.loadedPages()
            try await directory.nextPage()
            guard try await directory.loadedPages() > loadedPages else {
                throw MatrixChatServiceError.unavailable(reason: "The homeserver room directory stopped paginating")
            }
        }

        return collector.snapshot().map { room in
            MatrixHomeserverRoom(
                id: room.roomId,
                name: room.name?.isEmpty == false ? room.name! : (room.alias ?? room.roomId),
                topic: room.topic,
                canonicalAlias: room.alias,
                joinedMemberCount: room.joinedMembers,
                joinRule: Self.mapRoomDirectoryJoinRule(room.joinRule),
                isWorldReadable: room.isWorldReadable
            )
        }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func serverName(in userID: String) -> String? {
        guard userID.hasPrefix("@"), let separator = userID.lastIndex(of: ":") else { return nil }
        let serverName = userID[userID.index(after: separator)...]
        return serverName.isEmpty ? nil : String(serverName)
    }

    private static func mapRoomDirectoryJoinRule(
        _ joinRule: PublicRoomJoinRule?
    ) -> MatrixRoomDirectoryJoinRule {
        switch joinRule {
        case .public: .public
        case .knock: .knock
        case .restricted: .restricted
        case .knockRestricted: .knockRestricted
        case .invite: .invite
        case nil: .unknown
        }
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

    public func acceptInvitation(roomID: String) async throws {
        guard let room = roomByID[roomID], room.membership() == .invited else {
            throw MatrixChatServiceError.unavailable(reason: "This room invitation is no longer pending")
        }
        try await room.join()
    }

    public func declineInvitation(roomID: String) async throws {
        guard let room = roomByID[roomID], room.membership() == .invited else {
            throw MatrixChatServiceError.unavailable(reason: "This room invitation is no longer pending")
        }
        try await room.leave()
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
        let baselineEventIDs = Set(await binding.store.snapshot().map(\.id))
        _ = try await binding.timeline.send(msg: content)
        for _ in 0..<100 {
            let events = await binding.store.snapshot()
            if Self.hasRemoteSendAcknowledgement(
                events: events,
                baselineEventIDs: baselineEventIDs,
                body: body
            ) {
                return
            }
            try Task.checkCancellation()
            try await Task<Never, Never>.sleep(for: .milliseconds(100))
        }
        throw MatrixChatServiceError.unavailable(
            reason: "The homeserver did not confirm the encrypted message"
        )
    }

    public func roomRepositoryState(roomID: String) async throws -> MatrixRoomRepositoryState {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        if let rawCollection = try await room.getStateEventRaw(
            eventType: MatrixRoomRepositorySet.eventType,
            stateKey: MatrixRoomRepositorySet.stateKey
        ) {
            guard let data = rawCollection.data(using: .utf8) else {
                throw MatrixChatServiceError.unavailable(reason: "Room repository collection is invalid")
            }
            let repositorySet: MatrixRoomRepositorySet
            do {
                repositorySet = try MatrixRoomRepositorySet.decodeStateEvent(data)
            } catch {
                throw MatrixChatServiceError.unavailable(reason: "Room repository collection is invalid")
            }
            let rawMirror = try await room.getStateEventRaw(
                eventType: MatrixRoomRepositoryAttachment.eventType,
                stateKey: MatrixRoomRepositoryAttachment.stateKey
            )
            let mirror = rawMirror
                .flatMap { $0.data(using: .utf8) }
                .flatMap { try? MatrixRoomRepositoryAttachment.decodeStateEvent($0) }
            let mirrorStatus: MatrixRoomRepositoryMirrorStatus
            if let primary = repositorySet.primary {
                if let mirror {
                    mirrorStatus = mirror.matches(primary) ? .current : .divergent
                } else {
                    mirrorStatus = .missing
                }
            } else {
                mirrorStatus = mirror == nil ? .current : .divergent
            }
            return MatrixRoomRepositoryState(
                repositorySet: repositorySet,
                source: .collection,
                mirrorStatus: mirrorStatus
            )
        }

        guard let legacy = try await roomRepositoryAttachment(roomID: roomID) else {
            return .empty
        }
        do {
            return MatrixRoomRepositoryState(
                repositorySet: try MatrixRoomRepositorySet.migrating(legacy),
                source: .legacy,
                mirrorStatus: .current
            )
        } catch {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment is invalid")
        }
    }

    public func setRoomRepositorySet(
        _ repositorySet: MatrixRoomRepositorySet,
        roomID: String
    ) async throws -> MatrixRoomRepositorySetWriteResult {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        let collection = try repositorySet.encodedContent()
        guard let collectionJSON = String(data: collection, encoding: .utf8) else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository collection could not be encoded")
        }
        _ = try await room.sendStateEventRaw(
            eventType: MatrixRoomRepositorySet.eventType,
            stateKey: MatrixRoomRepositorySet.stateKey,
            content: collectionJSON
        )

        do {
            let mirrorData = try repositorySet.legacyMirror?.encodedContent() ?? Data("{}".utf8)
            guard let mirrorJSON = String(data: mirrorData, encoding: .utf8) else {
                return .appliedWithStaleMirror
            }
            _ = try await room.sendStateEventRaw(
                eventType: MatrixRoomRepositoryAttachment.eventType,
                stateKey: MatrixRoomRepositoryAttachment.stateKey,
                content: mirrorJSON
            )
            return .applied
        } catch {
            return .appliedWithStaleMirror
        }
    }

    public func roomTemplateReference(roomID: String) async throws -> HyphaRoomTemplateReference? {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        guard let raw = try await room.getStateEventRaw(
            eventType: HyphaRoomTemplateReference.eventType,
            stateKey: HyphaRoomTemplateReference.stateKey
        ) else { return nil }
        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HyphaRoomTemplateReference.self, from: data),
              let reference = try? HyphaRoomTemplateReference(
                source: .init(
                    repositoryID: decoded.source.repositoryID,
                    path: decoded.source.path,
                    resolvedCommit: decoded.source.resolvedCommit,
                    sha256: decoded.source.sha256
                ),
                version: decoded.version
              ) else {
            throw MatrixChatServiceError.unavailable(reason: "Room template reference is invalid")
        }
        return reference
    }

    public func setRoomTemplateReference(
        _ reference: HyphaRoomTemplateReference,
        roomID: String
    ) async throws {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        let data = try JSONEncoder().encode(reference)
        guard data.count <= 16 * 1_024,
              let content = String(data: data, encoding: .utf8) else {
            throw MatrixChatServiceError.unavailable(reason: "Room template reference could not be encoded")
        }
        _ = try await room.sendStateEventRaw(
            eventType: HyphaRoomTemplateReference.eventType,
            stateKey: HyphaRoomTemplateReference.stateKey,
            content: content
        )
    }

    public func roomRepositoryAttachment(roomID: String) async throws -> MatrixRoomRepositoryAttachment? {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        guard let raw = try await room.getStateEventRaw(
            eventType: MatrixRoomRepositoryAttachment.eventType,
            stateKey: MatrixRoomRepositoryAttachment.stateKey
        ) else { return nil }
        guard let data = raw.data(using: .utf8) else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment is invalid")
        }
        do {
            return try MatrixRoomRepositoryAttachment.decodeStateEvent(data)
        } catch {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment is invalid")
        }
    }

    public func setRoomRepositoryAttachment(
        _ attachment: MatrixRoomRepositoryAttachment,
        roomID: String
    ) async throws {
        guard let room = roomByID[roomID], room.membership() == .joined else {
            throw MatrixChatServiceError.unavailable(reason: "Room is not available")
        }
        let content = try attachment.encodedContent()
        guard let json = String(data: content, encoding: .utf8) else {
            throw MatrixChatServiceError.unavailable(reason: "Room repository attachment could not be encoded")
        }
        _ = try await room.sendStateEventRaw(
            eventType: MatrixRoomRepositoryAttachment.eventType,
            stateKey: MatrixRoomRepositoryAttachment.stateKey,
            content: json
        )
    }

    static func hasRemoteSendAcknowledgement(
        events: [MatrixTimelineEvent],
        baselineEventIDs: Set<String>,
        body: String
    ) -> Bool {
        events.contains { event in
            guard event.isOwn,
                  !event.id.hasPrefix("txn-"),
                  !baselineEventIDs.contains(event.id),
                  case let .text(value) = event.content else { return false }
            return value == body
        }
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

        let info = try? await room.roomInfo()
        roomByID[roomID] = room
        return MatrixRoomSummary(
            id: roomID,
            name: MatrixRoomNameResolution.resolve(
                rawName: info?.rawName,
                roomInfoDisplayName: info?.displayName,
                roomDisplayName: room.displayName(),
                canonicalAlias: room.canonicalAlias(),
                fallback: request.name
            ),
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

    public func beginEncryptionIdentityReset() async throws -> MatrixRecoveryIdentityResetAuthorization {
        switch recoveryIdentityResetLifecycle.begin() {
        case let .reuseAuthorization(authorization):
            return authorization
        case .identityResetAlreadyCommitted:
            return .completed
        case .authorizationBlocked:
            throw MatrixChatServiceError.unavailable(
                reason: "Matrix returned an invalid identity-reset authorization URL"
            )
        case .identityResetIndeterminate:
            throw MatrixChatServiceError.unavailable(
                reason: "Encryption identity reset may have changed server state and cannot be repeated safely"
            )
        case .operationInFlight:
            throw MatrixChatServiceError.unavailable(reason: "Encryption identity reset is already in progress")
        case .startIdentityReset:
            break
        }

        do {
            let encryption = client.encryption()
            guard let handle = try await encryption.resetIdentity() else {
                recoveryIdentityResetLifecycle.didBegin(requiring: .completed)
                return .completed
            }
            recoveryIdentityResetHandle = handle
            let authorization: MatrixRecoveryIdentityResetAuthorization
            switch handle.authType() {
            case .uiaa:
                authorization = .password
            case let .oAuth(info):
                guard let approvalURL = URL(string: info.approvalUrl),
                      approvalURL.scheme?.lowercased() == "https",
                      approvalURL.host != nil,
                      approvalURL.user == nil,
                      approvalURL.password == nil else {
                    recoveryIdentityResetLifecycle.didBlockAuthorization()
                    throw MatrixChatServiceError.unavailable(
                        reason: "Matrix returned an invalid identity-reset authorization URL"
                    )
                }
                authorization = .oauth(approvalURL: approvalURL)
            }
            recoveryIdentityResetLifecycle.didBegin(requiring: authorization)
            return authorization
        } catch {
            if recoveryIdentityResetHandle == nil {
                recoveryIdentityResetLifecycle.didFailAfterDestructiveInvocation()
            }
            throw error
        }
    }

    public func continueEncryptionIdentityReset(password: String) async throws -> Bool {
        guard let handle = recoveryIdentityResetHandle,
              recoveryIdentityResetLifecycle.beginPasswordContinuation() else {
            throw MatrixChatServiceError.unavailable(reason: "Password identity-reset authorization is unavailable")
        }
        do {
            guard try await handle.resetWithPassword(password: password) == nil else {
                recoveryIdentityResetLifecycle.didRejectPasswordContinuation()
                return false
            }
            recoveryIdentityResetHandle = nil
            recoveryIdentityResetLifecycle.didCommitIdentityReset()
            return true
        } catch {
            recoveryIdentityResetLifecycle.didRejectPasswordContinuation()
            throw error
        }
    }

    public func continueEncryptionIdentityResetAfterOAuth() async throws {
        guard let handle = recoveryIdentityResetHandle,
              recoveryIdentityResetLifecycle.beginOAuthContinuation() else {
            throw MatrixChatServiceError.unavailable(reason: "OAuth identity-reset authorization is unavailable")
        }
        do {
            try await handle.reset(auth: nil)
            recoveryIdentityResetHandle = nil
            recoveryIdentityResetLifecycle.didCommitIdentityReset()
        } catch {
            recoveryIdentityResetLifecycle.didRejectOAuthContinuation()
            throw error
        }
    }

    public func createReplacementEncryptionRecoveryKey() async throws -> String {
        guard recoveryIdentityResetLifecycle.beginReplacementKeyCreation() else {
            throw MatrixChatServiceError.unavailable(
                reason: "Replacement recovery-key creation is not ready"
            )
        }
        do {
            let recoveryKey = try await client.encryption().resetRecoveryKey()
            recoveryIdentityResetLifecycle.didCreateReplacementKey()
            return recoveryKey
        } catch {
            recoveryIdentityResetLifecycle.didFailReplacementKeyCreation()
            throw error
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
        let session: MatrixSASVerificationSession
        if let existing = verificationSession {
            session = existing
        } else {
            let controller = try await client.getSessionVerificationController()
            let created = MatrixSASVerificationSession(controller: controller)
            verificationSession = created
            session = created
        }
        do {
            return try await session.requestChallenge()
        } catch {
            if verificationSession === session { verificationSession = nil }
            throw error
        }
    }

    public func setIncomingDeviceVerificationHandler(
        _ handler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    ) async throws {
        guard let handler, verificationSession == nil else { return }
        let controller = try await client.getSessionVerificationController()
        verificationSession = MatrixSASVerificationSession(
            controller: controller,
            incomingStateObserver: handler
        )
    }

    public func acceptIncomingDeviceVerification() async throws {
        guard let session = verificationSession else {
            throw MatrixChatServiceError.unavailable(reason: "No incoming device verification")
        }
        try await session.acceptIncomingRequest()
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
        subsystem: MatrixPlatformStorageIdentity.current.loggerSubsystem,
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
    case noIncomingRequest
}

final class MatrixSASVerificationSession: SessionVerificationControllerDelegate, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: MatrixPlatformStorageIdentity.current.loggerSubsystem,
        category: "MatrixVerification"
    )

    private let controller: SessionVerificationController
    private let incomingStateObserver: @Sendable (MatrixVerificationFlowState) -> Void
    private let stageObserver: @Sendable (MatrixVerificationDiagnosticStage) -> Void
    private let lock = NSLock()
    private var challengeContinuation: CheckedContinuation<MatrixVerificationChallenge, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?
    private var pendingIncomingRequest: SessionVerificationRequestDetails?
    private var challengePresented = false
    private var sasStartSubmitted = false
    private var sasProtocolStarted = false
    private var terminal = false

    init(
        controller: SessionVerificationController,
        incomingStateObserver: @escaping @Sendable (MatrixVerificationFlowState) -> Void = { _ in },
        stageObserver: @escaping @Sendable (MatrixVerificationDiagnosticStage) -> Void = { _ in }
    ) {
        self.controller = controller
        self.incomingStateObserver = incomingStateObserver
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

    func acceptIncomingRequest() async throws {
        guard let details = lock.withLock({ pendingIncomingRequest }) else {
            throw MatrixVerificationFlowError.noIncomingRequest
        }
        do {
            try await controller.acknowledgeVerificationRequest(
                senderId: details.senderProfile.userId,
                flowId: details.flowId
            )
            try await controller.acceptVerificationRequest()
            lock.withLock { pendingIncomingRequest = nil }
        } catch {
            fail(error)
            throw error
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

    func didReceiveVerificationRequest(details: SessionVerificationRequestDetails) {
        let shouldPresent = lock.withLock {
            guard !terminal,
                  challengeContinuation == nil,
                  pendingIncomingRequest == nil,
                  !sasStartSubmitted else { return false }
            pendingIncomingRequest = details
            return true
        }
        guard shouldPresent else { return }
        incomingStateObserver(.incomingRequest)
    }

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
        if continuation == nil {
            incomingStateObserver(.challenge(challenge))
        }
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
            pendingIncomingRequest = nil
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
            pendingIncomingRequest = nil
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
