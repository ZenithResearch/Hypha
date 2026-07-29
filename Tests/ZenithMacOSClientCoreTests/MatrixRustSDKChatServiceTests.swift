import Foundation
import MatrixRustSDK
import XCTest
@testable import ZenithMacOSClientCore

final class MatrixRustSDKChatServiceTests: XCTestCase {
    func testPasswordSignInReauthenticatesExistingDeviceAndRestoresItsSDKStore() async throws {
        let accountKey = MatrixRustSDKChatService.accountKey(
            username: "alice",
            homeserver: MatrixProductConfiguration.production.homeserver
        )
        let existing = MatrixSDKSessionRecord.fixture(
            accountKey: accountKey,
            userID: "@alice:synapse.zenith-research.ca",
            deviceID: "EXISTINGDEVICE"
        )
        let refreshed = MatrixSDKSessionRecord.fixture(
            accountKey: accountKey,
            accessToken: "refreshed-token",
            userID: existing.userId,
            deviceID: existing.deviceId
        )
        let vault = MemorySessionVault()
        try vault.saveSession(existing)
        try vault.saveStoreKey(Data(repeating: 0xA5, count: 32), accountKey: accountKey)
        let client = FakeLiveClient()
        await client.setRooms([
            MatrixRoomSummary(id: "!encrypted:example.org", name: "Encrypted", isEncrypted: true, hasInvite: false)
        ])
        let reauthenticator = FakePasswordSessionReauthenticator(result: .success(refreshed))
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            passwordSessionReauthenticator: reauthenticator,
            randomStoreKey: { XCTFail("Existing device must reuse its store key"); return Data() }
        )

        let rooms = try await service.signIn(username: "alice", password: "not-recorded")

        let loginCount = await client.loginCount()
        let restoredSessions = await client.restoredSessions()
        let reauthenticationCount = await reauthenticator.callCount()
        XCTAssertEqual(rooms.map(\.id), ["!encrypted:example.org"])
        XCTAssertEqual(loginCount, 0)
        XCTAssertEqual(restoredSessions, [refreshed])
        XCTAssertEqual(reauthenticationCount, 1)
        XCTAssertEqual(try vault.loadSession(accountKey: accountKey), refreshed)
    }

    func testPasswordChangeForwardsCurrentAndNewPasswordsWithoutLoggingOutOtherDevices() async throws {
        let client = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        try await service.changePassword(
            currentPassword: "current-not-recorded",
            newPassword: "new-not-recorded",
            logoutOtherDevices: false
        )

        let request = await client.observedPasswordChange()
        XCTAssertEqual(request?.currentPassword, "current-not-recorded")
        XCTAssertEqual(request?.newPassword, "new-not-recorded")
        XCTAssertEqual(request?.logoutOtherDevices, false)
    }

    func testPasswordReauthenticationRejectsAReplacementDeviceBeforeOpeningTheStore() async throws {
        let accountKey = MatrixRustSDKChatService.accountKey(
            username: "alice",
            homeserver: MatrixProductConfiguration.production.homeserver
        )
        let existing = MatrixSDKSessionRecord.fixture(
            accountKey: accountKey,
            userID: "@alice:synapse.zenith-research.ca",
            deviceID: "EXISTINGDEVICE"
        )
        let replacement = MatrixSDKSessionRecord.fixture(
            accountKey: accountKey,
            accessToken: "replacement-token",
            userID: existing.userId,
            deviceID: "DIFFERENTDEVICE"
        )
        let vault = MemorySessionVault()
        try vault.saveSession(existing)
        try vault.saveStoreKey(Data(repeating: 0xA5, count: 32), accountKey: accountKey)
        let factory = FakeLiveClientFactory(client: FakeLiveClient())
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: factory,
            passwordSessionReauthenticator: FakePasswordSessionReauthenticator(result: .success(replacement))
        )

        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "not-recorded"),
            expected: .recoveryRequired
        )

        let makeCount = await factory.makeCount()
        XCTAssertEqual(makeCount, 0)
        XCTAssertEqual(try vault.loadSession(accountKey: accountKey), existing)
    }

    func testSignInBuildsEncryptedStorePersistsSessionAndReturnsSyncedRooms() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient()
        await client.setRooms([
            MatrixRoomSummary(id: "!encrypted:example.org", name: "Encrypted", isEncrypted: true, hasInvite: false)
        ])
        let factory = FakeLiveClientFactory(client: client)
        let service = MatrixRustSDKChatService(
            configuration: MatrixProductConfiguration.production,
            vault: vault,
            clientFactory: factory,
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        let rooms = try await service.signIn(username: "alice", password: "correct horse")

        XCTAssertEqual(rooms.map(\.id), ["!encrypted:example.org"])
        let makeCount = await factory.makeCount()
        let loginCount = await client.loginCount()
        let syncCount = await client.syncCount()
        let continuousSyncStartCount = await client.continuousSyncStartCount()
        XCTAssertEqual(makeCount, 1)
        XCTAssertEqual(try vault.loadedStoreKey()?.count, 32)
        XCTAssertEqual(try vault.loadSession()?.userId, "@alice:example.org")
        XCTAssertEqual(loginCount, 1)
        XCTAssertEqual(syncCount, 1)
        XCTAssertEqual(continuousSyncStartCount, 1)
    }

    func testManualRoomRefreshRestartsSyncAndReturnsNewInvites() async throws {
        let joined = MatrixRoomSummary(
            id: "!joined:example.org",
            name: "Joined",
            isEncrypted: true,
            hasInvite: false
        )
        let invited = MatrixRoomSummary(
            id: "!invited:example.org",
            name: "Invited",
            isEncrypted: true,
            hasInvite: true
        )
        let client = FakeLiveClient()
        await client.setRooms([joined])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        await client.setRooms([joined, invited])

        let refreshed = try await service.refreshRooms()
        let syncCount = await client.syncCount()
        let stopCount = await client.continuousSyncStopCount()
        let startCount = await client.continuousSyncStartCount()

        XCTAssertEqual(refreshed, [joined, invited])
        XCTAssertEqual(syncCount, 2)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(startCount, 2)
    }

    func testSignInAcceptsSDKCanonicalHomeserverInSessionRecord() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient(sessionHomeserverURL: "https://synapse.zenith-research.ca/")
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        _ = try await service.signIn(username: "alice", password: "correct horse")

        XCTAssertEqual(try vault.loadSession()?.homeserverURL, "https://synapse.zenith-research.ca/")
    }

    func testSignInReportsInitialSyncStageWithoutLeakingUnderlyingError() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient(syncError: FixtureSDKError("secret-token-material"))
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "correct horse"),
            expected: .unavailable(reason: "Initial Matrix sync failed")
        )
        XCTAssertNil(try vault.loadSession())
    }

    func testSignInReportsSessionReadStageWithoutLeakingUnderlyingError() async throws {
        let client = FakeLiveClient(sessionError: FixtureSDKError("secret-token-material"))
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "correct horse"),
            expected: .unavailable(reason: "Matrix login succeeded, but the SDK session could not be read")
        )
    }

    func testSignInReportsRoomLoadStageWithoutLeakingUnderlyingError() async throws {
        let client = FakeLiveClient(roomLoadError: FixtureSDKError("secret-token-material"))
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "correct horse"),
            expected: .unavailable(reason: "Initial Matrix room load failed")
        )
    }

    func testRestoreAcceptsSDKCanonicalHomeserverInSavedSession() async throws {
        let vault = MemorySessionVault()
        let session = MatrixSDKSessionRecord.fixture(homeserverURL: "https://synapse.zenith-research.ca/")
        try vault.saveSession(session)
        try vault.saveStoreKey(Data(repeating: 0x4A, count: 32), accountKey: session.accountKey)
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: FakeLiveClient()),
            randomStoreKey: { Data(repeating: 1, count: 32) }
        )

        _ = try await service.restore()
    }

    func testRestoreFailsClosedWhenStoreKeyIsMissing() async throws {
        let vault = MemorySessionVault()
        try vault.saveSession(.fixture())
        let service = MatrixRustSDKChatService(
            configuration: MatrixProductConfiguration.production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: FakeLiveClient()),
            randomStoreKey: { Data(repeating: 1, count: 32) }
        )

        do {
            _ = try await service.restore()
            XCTFail("Expected recovery requirement")
        } catch {
            XCTAssertEqual(error as? MatrixChatServiceError, .recoveryRequired)
        }
    }

    func testServiceForwardsDeviceVerificationLifecycleToLiveClient() async throws {
        let challenge = MatrixVerificationChallenge.emojis([
            MatrixVerificationEmoji(symbol: "🐶", description: "Dog")
        ])
        let client = FakeLiveClient(
            trustState: .unsigned,
            verificationChallenge: challenge
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let observedState = try await service.deviceTrustState()
        let observedChallenge = try await service.requestDeviceVerification()
        XCTAssertEqual(observedState, .unsigned)
        XCTAssertEqual(observedChallenge, challenge)
        try await service.approveDeviceVerification()
        await service.declineDeviceVerification()

        let approvalCount = await client.verificationApprovalCount()
        let declineCount = await client.verificationDeclineCount()
        XCTAssertEqual(approvalCount, 1)
        XCTAssertEqual(declineCount, 1)
    }

    func testServicePreservesAllPeerVerificationEligibilityOutcomes() async throws {
        let cases: [(MatrixPeerVerificationEligibility, Error?, MatrixPeerVerificationEligibility)] = [
            (.eligiblePeer, nil, .eligiblePeer),
            (.noEligiblePeer, nil, .noEligiblePeer),
            (.eligiblePeer, MatrixChatServiceError.offline, .unavailable),
        ]

        for (liveResult, liveError, expected) in cases {
            let client = FakeLiveClient(
                peerVerificationEligibility: liveResult,
                peerVerificationEligibilityError: liveError
            )
            let service = MatrixRustSDKChatService(
                configuration: .production,
                vault: MemorySessionVault(),
                clientFactory: FakeLiveClientFactory(client: client),
                randomStoreKey: { Data(repeating: 2, count: 32) }
            )
            _ = try await service.signIn(username: "alice", password: "secret")

            let observed = await service.peerVerificationEligibility()

            XCTAssertEqual(observed, expected)
        }
    }

    func testServiceReportsUnavailablePeerEligibilityWithoutSession() async {
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: FakeLiveClient()),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )

        let eligibility = await service.peerVerificationEligibility()

        XCTAssertEqual(eligibility, .unavailable)
    }

    func testServiceBootstrapsFirstDeviceTrustWithoutStartingSAS() async throws {
        let client = FakeLiveClient(
            trustState: .unsigned,
            bootstrapState: .verifiedByCurrentSelfSigningKey
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let result = try await service.bootstrapFirstDeviceTrust()

        let bootstrapCount = await client.bootstrapCount()
        let verificationRequestCount = await client.verificationRequestCount()
        XCTAssertEqual(result, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertEqual(verificationRequestCount, 0)
    }

    func testServiceDoesNotPromoteUnavailableBootstrapToLocalTrust() async throws {
        let client = FakeLiveClient(
            trustState: .verifiedByCurrentSelfSigningKey,
            bootstrapState: .unavailable
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let result = try await service.bootstrapFirstDeviceTrust()

        XCTAssertEqual(result, .unavailable)
    }

    func testServiceForwardsPasswordBootstrapContinuationWithoutStartingSAS() async throws {
        let client = FakeLiveClient(
            trustState: .unsigned,
            bootstrapState: .passwordRequired,
            bootstrapContinuationState: .verifiedByCurrentSelfSigningKey
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-retained")

        let initialState = try await service.bootstrapFirstDeviceTrust()
        let completedState = try await service.continueFirstDeviceTrust(password: "not-retained")
        let continuationCount = await client.bootstrapContinuationCount()
        let verificationRequestCount = await client.verificationRequestCount()

        XCTAssertEqual(initialState, .passwordRequired)
        XCTAssertEqual(completedState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(continuationCount, 1)
        XCTAssertEqual(verificationRequestCount, 0)
    }

    func testConcurrentBootstrapRequestsInvokeLiveClientExactlyOnce() async throws {
        let client = FakeLiveClient(
            trustState: .unsigned,
            bootstrapState: .passwordRequired,
            suspendBootstrap: true
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-retained")

        let first = Task { try await service.bootstrapFirstDeviceTrust() }
        await client.waitUntilBootstrapStarted()
        let second = Task { try await service.bootstrapFirstDeviceTrust() }
        for _ in 0..<20 { await Task.yield() }
        await client.releaseBootstrap()

        let results = try await [first.value, second.value]
        let bootstrapCount = await client.bootstrapCount()
        XCTAssertEqual(bootstrapCount, 1)
        XCTAssertEqual(Set(results), Set([.passwordRequired, .bootstrapping]))
    }

    func testServiceForwardsRecoveryAndEncryptedRoomCreation() async throws {
        let createdRoom = MatrixRoomSummary(
            id: "!created:example.org",
            name: "Private planning",
            isEncrypted: true,
            hasInvite: false
        )
        let client = FakeLiveClient(recoveryState: .available, createdRoom: createdRoom)
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let observedRecoveryState = try await service.encryptionRecoveryState(trustState: .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(observedRecoveryState, .available)
        let generatedRecoveryKey = try await service.setupEncryptionRecovery()
        try await service.restoreEncryption(recoveryKey: "not-a-real-recovery-key")
        let request = MatrixRoomCreationRequest(
            name: "Private planning",
            topic: "Launch",
            invitees: ["@bob:example.org"]
        )
        let room = try await service.createEncryptedRoom(request)

        let observedRecoveryKeys = await client.observedRecoveryKeys()
        let recoverySetupCount = await client.recoverySetupCount()
        let observedRoomCreationRequests = await client.observedRoomCreationRequests()
        XCTAssertEqual(generatedRecoveryKey, "not-a-real-generated-key")
        XCTAssertEqual(recoverySetupCount, 1)
        XCTAssertEqual(room, createdRoom)
        XCTAssertEqual(observedRecoveryKeys, ["not-a-real-recovery-key"])
        XCTAssertEqual(observedRoomCreationRequests, [request])
    }

    func testCreatorRoomRemovalLeavesBeforeForgettingAndRefreshesRooms() async throws {
        let ownedRoom = MatrixRoomSummary(
            id: "!owned:example.org",
            name: "Old room",
            isEncrypted: true,
            hasInvite: false,
            isCreatedByCurrentUser: true
        )
        let client = FakeLiveClient()
        await client.setRooms([ownedRoom])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let remaining = try await service.removeRoom(roomID: ownedRoom.id)
        let observedRemovalRequests = await client.observedRoomRemovalRequests()

        XCTAssertEqual(remaining, [])
        XCTAssertEqual(observedRemovalRequests, [ownedRoom.id])
    }

    func testRoomRemovalRejectsAnAccountThatDidNotCreateTheRoom() async throws {
        let otherAccountsRoom = MatrixRoomSummary(
            id: "!other:example.org",
            name: "Someone else's room",
            isEncrypted: true,
            hasInvite: false,
            isCreatedByCurrentUser: false
        )
        let client = FakeLiveClient()
        await client.setRooms([otherAccountsRoom])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        do {
            _ = try await service.removeRoom(roomID: otherAccountsRoom.id)
            XCTFail("Expected creator-scoped room removal to fail closed")
        } catch {
            XCTAssertEqual(
                error as? MatrixChatServiceError,
                .unavailable(reason: "Only the account that created this room can remove it")
            )
        }
        let observedRemovalRequests = await client.observedRoomRemovalRequests()
        XCTAssertEqual(observedRemovalRequests, [])
    }

    func testLogoutStopsContinuousSyncBeforeClearingSession() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        try await service.logout()

        let stopCount = await client.continuousSyncStopCount()
        XCTAssertEqual(stopCount, 1)
        XCTAssertNil(try vault.loadSession())
    }

    func testSuspendStopsContinuousSyncWithoutDeletingSavedAccountSession() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let savedBeforeSuspend = try vault.loadSession()

        await service.suspend()
        let stopCount = await client.continuousSyncStopCount()

        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(try vault.loadSession(), savedBeforeSuspend)
    }

    func testSendUsesLiveClientAndRejectsUnencryptedRooms() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient()
        await client.setRooms([
            MatrixRoomSummary(id: "!encrypted:example.org", name: "Encrypted", isEncrypted: true, hasInvite: false),
            MatrixRoomSummary(id: "!plain:example.org", name: "Plain", isEncrypted: false, hasInvite: false)
        ])
        let service = MatrixRustSDKChatService(
            configuration: MatrixProductConfiguration.production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        try await service.sendText("hello", to: "!encrypted:example.org")
        let sentBodies = await client.sentBodies()
        XCTAssertEqual(sentBodies, ["hello"])

        do {
            try await service.sendText("never plaintext", to: "!plain:example.org")
            XCTFail("Expected plaintext fallback refusal")
        } catch {
            XCTAssertEqual(error as? MatrixChatServiceError, .trustViolation)
        }
    }

    func testSASSessionRecordsAcceptanceAndSASStartBoundaries() async {
        let controller = DiagnosticSessionVerificationController()
        let stages = VerificationStageRecorder()
        let session = MatrixSASVerificationSession(controller: controller) { stage in
            stages.append(stage)
        }
        let challengeTask = Task {
            try await session.requestChallenge()
        }

        await controller.waitUntilRequestStarted()
        await stages.waitUntilContains(.waitingForAcceptance)
        controller.deliverAcceptance()
        controller.deliverAcceptance()
        await controller.waitUntilSASStarted()

        let sasStartCount = controller.sasStartCount()
        XCTAssertEqual(sasStartCount, 1)
        XCTAssertEqual(stages.snapshot(), [
            .controllerInstalled,
            .requestSubmitting,
            .waitingForAcceptance,
            .acceptanceReceived,
            .sasStarting,
            .sasProtocolStarted,
            .sasStartReturned,
        ])

        controller.deliverFailure()
        _ = try? await challengeTask.value
    }
}

private final class VerificationStageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stages: [MatrixVerificationDiagnosticStage] = []

    func append(_ stage: MatrixVerificationDiagnosticStage) {
        lock.withLock { stages.append(stage) }
    }

    func snapshot() -> [MatrixVerificationDiagnosticStage] {
        lock.withLock { stages }
    }

    func waitUntilContains(_ stage: MatrixVerificationDiagnosticStage) async {
        while !lock.withLock({ stages.contains(stage) }) {
            await Task.yield()
        }
    }
}

private final class DiagnosticSessionVerificationController: SessionVerificationController, @unchecked Sendable {
    private let lock = NSLock()
    private var delegate: SessionVerificationControllerDelegate?
    private var requestStarted = false
    private var sasStarts = 0

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("Not used by this test")
    }

    init() {
        super.init(noHandle: .init())
    }

    override func setDelegate(delegate: SessionVerificationControllerDelegate?) {
        lock.withLock { self.delegate = delegate }
    }

    override func requestDeviceVerification() async throws {
        lock.withLock { requestStarted = true }
    }

    override func startSasVerification() async throws {
        let currentDelegate = lock.withLock {
            sasStarts += 1
            return delegate
        }
        currentDelegate?.didStartSasVerification()
        currentDelegate?.didStartSasVerification()
    }

    func deliverAcceptance() {
        lock.withLock { delegate }?.didAcceptVerificationRequest()
    }

    func deliverFailure() {
        lock.withLock { delegate }?.didFail()
    }

    func waitUntilRequestStarted() async {
        while !lock.withLock({ requestStarted }) {
            await Task.yield()
        }
    }

    func waitUntilSASStarted() async {
        while lock.withLock({ sasStarts == 0 }) {
            await Task.yield()
        }
    }

    func sasStartCount() -> Int {
        lock.withLock { sasStarts }
    }
}

private final class MemorySessionVault: MatrixSDKSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MatrixSDKSessionRecord?
    private var storeKey: Data?

    func loadSession() throws -> MatrixSDKSessionRecord? { lock.withLock { session } }
    func loadSession(accountKey: String) throws -> MatrixSDKSessionRecord? {
        lock.withLock { session?.accountKey == accountKey ? session : nil }
    }
    func saveSession(_ value: MatrixSDKSessionRecord) throws { lock.withLock { session = value } }
    func deleteSession() throws { lock.withLock { session = nil } }
    func loadStoreKey(accountKey: String) throws -> Data? { lock.withLock { storeKey } }
    func saveStoreKey(_ value: Data, accountKey: String) throws { lock.withLock { storeKey = value } }
    func loadedStoreKey() throws -> Data? { lock.withLock { storeKey } }
}

private actor FakeLiveClient: MatrixLiveClient {
    struct PasswordChangeRequest: Sendable {
        let currentPassword: String
        let newPassword: String
        let logoutOtherDevices: Bool
    }

    private var rooms: [MatrixRoomSummary] = []
    private var logins = 0
    private var syncs = 0
    private var continuousSyncStarts = 0
    private var continuousSyncStops = 0
    private var verificationApprovals = 0
    private var verificationDeclines = 0
    private var verificationRequests = 0
    private var bootstraps = 0
    private var bootstrapContinuations = 0
    private var recoverySetups = 0
    private var recoveryKeys: [String] = []
    private var passwordChange: PasswordChangeRequest?
    private var restored: [MatrixSDKSessionRecord] = []
    private var roomCreationRequests: [MatrixRoomCreationRequest] = []
    private var roomRemovalRequests: [String] = []
    private var sends: [String] = []
    private let trustState: MatrixDeviceTrustState
    private let peerVerificationEligibility: MatrixPeerVerificationEligibility
    private let peerVerificationEligibilityError: Error?
    private let bootstrapState: MatrixFirstDeviceTrustBootstrapState
    private let bootstrapContinuationState: MatrixFirstDeviceTrustBootstrapState
    private let verificationChallenge: MatrixVerificationChallenge
    private let recoveryState: MatrixRecoveryState
    private let createdRoom: MatrixRoomSummary?
    private let sessionHomeserverURL: String
    private let loginError: Error?
    private let sessionError: Error?
    private let syncError: Error?
    private let roomLoadError: Error?
    private var suspendBootstrap: Bool
    private var bootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        sessionHomeserverURL: String = "https://synapse.zenith-research.ca",
        loginError: Error? = nil,
        sessionError: Error? = nil,
        syncError: Error? = nil,
        roomLoadError: Error? = nil,
        trustState: MatrixDeviceTrustState = .unknown,
        peerVerificationEligibility: MatrixPeerVerificationEligibility = .unavailable,
        peerVerificationEligibilityError: Error? = nil,
        bootstrapState: MatrixFirstDeviceTrustBootstrapState = .unavailable,
        bootstrapContinuationState: MatrixFirstDeviceTrustBootstrapState = .unavailable,
        suspendBootstrap: Bool = false,
        verificationChallenge: MatrixVerificationChallenge = .decimals([111, 222, 333]),
        recoveryState: MatrixRecoveryState = .unknown,
        createdRoom: MatrixRoomSummary? = nil
    ) {
        self.sessionHomeserverURL = sessionHomeserverURL
        self.loginError = loginError
        self.sessionError = sessionError
        self.syncError = syncError
        self.roomLoadError = roomLoadError
        self.trustState = trustState
        self.peerVerificationEligibility = peerVerificationEligibility
        self.peerVerificationEligibilityError = peerVerificationEligibilityError
        self.bootstrapState = bootstrapState
        self.bootstrapContinuationState = bootstrapContinuationState
        self.suspendBootstrap = suspendBootstrap
        self.verificationChallenge = verificationChallenge
        self.recoveryState = recoveryState
        self.createdRoom = createdRoom
    }

    func setRooms(_ value: [MatrixRoomSummary]) { rooms = value }
    func login(username: String, password: String) async throws {
        if let loginError { throw loginError }
        logins += 1
    }
    func restore(session: MatrixSDKSessionRecord) async throws { restored.append(session) }
    func sessionRecord(accountKey: String) async throws -> MatrixSDKSessionRecord {
        if let sessionError { throw sessionError }
        return .fixture(accountKey: accountKey, homeserverURL: sessionHomeserverURL)
    }
    func syncOnce() async throws {
        if let syncError { throw syncError }
        syncs += 1
    }
    func startContinuousSync() async { continuousSyncStarts += 1 }
    func stopContinuousSync() async { continuousSyncStops += 1 }
    func joinedRooms() async throws -> [MatrixRoomSummary] {
        if let roomLoadError { throw roomLoadError }
        return rooms
    }
    func timeline(roomID: String) async throws -> [MatrixTimelineEvent] { [] }
    func sendText(_ body: String, roomID: String) async throws { sends.append(body) }
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        roomCreationRequests.append(request)
        guard let createdRoom else {
            throw MatrixChatServiceError.unavailable(reason: "Room creation unavailable")
        }
        return createdRoom
    }
    func removeRoom(roomID: String) async throws {
        roomRemovalRequests.append(roomID)
        rooms.removeAll { $0.id == roomID }
    }
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState {
        recoveryState == .ready && trustState != .verifiedByCurrentSelfSigningKey ? .available : recoveryState
    }
    func setupEncryptionRecovery() async throws -> String {
        recoverySetups += 1
        return "not-a-real-generated-key"
    }
    func restoreEncryption(recoveryKey: String) async throws { recoveryKeys.append(recoveryKey) }
    func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        passwordChange = PasswordChangeRequest(
            currentPassword: currentPassword,
            newPassword: newPassword,
            logoutOtherDevices: logoutOtherDevices
        )
    }
    func deviceTrustState() async throws -> MatrixDeviceTrustState { trustState }
    func peerVerificationEligibility() async throws -> MatrixPeerVerificationEligibility {
        if let peerVerificationEligibilityError { throw peerVerificationEligibilityError }
        return peerVerificationEligibility
    }
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        bootstraps += 1
        if suspendBootstrap {
            await withCheckedContinuation { bootstrapWaiters.append($0) }
        }
        return bootstrapState
    }
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState {
        bootstrapContinuations += 1
        return bootstrapContinuationState
    }
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        verificationRequests += 1
        return verificationChallenge
    }
    func approveDeviceVerification() async throws { verificationApprovals += 1 }
    func declineDeviceVerification() async { verificationDeclines += 1 }
    func logout() async throws {}
    func loginCount() -> Int { logins }
    func restoredSessions() -> [MatrixSDKSessionRecord] { restored }
    func syncCount() -> Int { syncs }
    func continuousSyncStartCount() -> Int { continuousSyncStarts }
    func continuousSyncStopCount() -> Int { continuousSyncStops }
    func verificationApprovalCount() -> Int { verificationApprovals }
    func verificationDeclineCount() -> Int { verificationDeclines }
    func verificationRequestCount() -> Int { verificationRequests }
    func bootstrapCount() -> Int { bootstraps }
    func waitUntilBootstrapStarted() async {
        while bootstraps == 0 { await Task.yield() }
    }
    func releaseBootstrap() {
        suspendBootstrap = false
        let waiters = bootstrapWaiters
        bootstrapWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
    func bootstrapContinuationCount() -> Int { bootstrapContinuations }
    func recoverySetupCount() -> Int { recoverySetups }
    func observedRecoveryKeys() -> [String] { recoveryKeys }
    func observedPasswordChange() -> PasswordChangeRequest? { passwordChange }
    func observedRoomCreationRequests() -> [MatrixRoomCreationRequest] { roomCreationRequests }
    func observedRoomRemovalRequests() -> [String] { roomRemovalRequests }
    func sentBodies() -> [String] { sends }
}

private actor FakeLiveClientFactory: MatrixLiveClientFactory {
    private let client: FakeLiveClient
    private var makes = 0

    init(client: FakeLiveClient) { self.client = client }
    func make(accountKey: String, storeKey: Data) async throws -> any MatrixLiveClient {
        makes += 1
        return client
    }
    func makeCount() -> Int { makes }
}

private actor FakePasswordSessionReauthenticator: MatrixPasswordSessionReauthenticating {
    private let result: Result<MatrixSDKSessionRecord, Error>
    private var calls = 0

    init(result: Result<MatrixSDKSessionRecord, Error>) { self.result = result }

    func reauthenticate(
        username: String,
        password: String,
        existingSession: MatrixSDKSessionRecord,
        configuration: MatrixProductConfiguration
    ) async throws -> MatrixSDKSessionRecord {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
}

private extension MatrixSDKSessionRecord {
    static func fixture(
        accountKey: String = "fixture-account",
        accessToken: String = "fixture-token",
        homeserverURL: String = "https://synapse.zenith-research.ca",
        userID: String = "@alice:example.org",
        deviceID: String = "FIXTURE"
    ) -> Self {
        .init(
            accessToken: accessToken,
            refreshToken: nil,
            userId: userID,
            deviceId: deviceID,
            homeserverURL: homeserverURL,
            slidingSyncVersion: "native",
            accountKey: accountKey
        )
    }
}

private struct FixtureSDKError: Error, CustomStringConvertible, Sendable {
    let description: String
    init(_ description: String) { self.description = description }
}

private func XCTAssertThrowsMatrixError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatrixChatServiceError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected Matrix error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? MatrixChatServiceError, expected, file: file, line: line)
        XCTAssertFalse(String(describing: error).contains("secret-token-material"), file: file, line: line)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}
