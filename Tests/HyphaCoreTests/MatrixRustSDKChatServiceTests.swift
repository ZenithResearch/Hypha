import Foundation
import MatrixRustSDK
import XCTest
@testable import HyphaCore

final class MatrixRustSDKChatServiceTests: XCTestCase {
    func testRecoveryIdentityResetLifecycleNeverRestartsAfterIdentityCommitment() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()

        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didBegin(requiring: .password)
        XCTAssertEqual(lifecycle.begin(), .reuseAuthorization(.password))
        XCTAssertTrue(lifecycle.canContinueWithPassword)
        XCTAssertFalse(lifecycle.canContinueAfterOAuth)

        lifecycle.didCommitIdentityReset()

        XCTAssertEqual(lifecycle.begin(), .identityResetAlreadyCommitted)
        XCTAssertFalse(lifecycle.canContinueWithPassword)
        XCTAssertFalse(lifecycle.canContinueAfterOAuth)
        XCTAssertTrue(lifecycle.canCreateReplacementRecoveryKey)
    }

    func testRecoveryIdentityResetLifecycleDoesNotRestartAfterBlockedAuthorization() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()

        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didBlockAuthorization()

        XCTAssertEqual(lifecycle.begin(), .authorizationBlocked)
        XCTAssertFalse(lifecycle.canContinueWithPassword)
        XCTAssertFalse(lifecycle.canContinueAfterOAuth)
        XCTAssertFalse(lifecycle.canCreateReplacementRecoveryKey)
    }

    func testRecoveryIdentityResetLifecycleDoesNotRestartAfterAmbiguousInvocationFailure() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()

        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didFailAfterDestructiveInvocation()

        XCTAssertEqual(lifecycle.begin(), .identityResetIndeterminate)
        XCTAssertFalse(lifecycle.canContinueWithPassword)
        XCTAssertFalse(lifecycle.canContinueAfterOAuth)
        XCTAssertFalse(lifecycle.canCreateReplacementRecoveryKey)
    }

    func testRecoveryIdentityResetLifecycleSerializesPasswordContinuations() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()
        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didBegin(requiring: .password)

        XCTAssertTrue(lifecycle.beginPasswordContinuation())
        XCTAssertFalse(lifecycle.beginPasswordContinuation())
        XCTAssertFalse(lifecycle.canContinueWithPassword)

        lifecycle.didRejectPasswordContinuation()

        XCTAssertTrue(lifecycle.canContinueWithPassword)
        XCTAssertTrue(lifecycle.beginPasswordContinuation())
        lifecycle.didCommitIdentityReset()
        XCTAssertFalse(lifecycle.beginPasswordContinuation())
    }

    func testRecoveryIdentityResetLifecycleSerializesOAuthContinuations() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()
        let approvalURL = URL(string: "https://auth.example.org/approve")!
        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didBegin(requiring: .oauth(approvalURL: approvalURL))

        XCTAssertTrue(lifecycle.beginOAuthContinuation())
        XCTAssertFalse(lifecycle.beginOAuthContinuation())
        XCTAssertFalse(lifecycle.canContinueAfterOAuth)

        lifecycle.didRejectOAuthContinuation()

        XCTAssertTrue(lifecycle.canContinueAfterOAuth)
        XCTAssertTrue(lifecycle.beginOAuthContinuation())
        lifecycle.didCommitIdentityReset()
        XCTAssertFalse(lifecycle.beginOAuthContinuation())
    }

    func testRecoveryIdentityResetLifecycleSerializesReplacementKeyCreation() {
        var lifecycle = MatrixRecoveryIdentityResetLifecycle()
        XCTAssertEqual(lifecycle.begin(), .startIdentityReset)
        lifecycle.didBegin(requiring: .completed)

        XCTAssertTrue(lifecycle.beginReplacementKeyCreation())
        XCTAssertFalse(lifecycle.beginReplacementKeyCreation())

        lifecycle.didFailReplacementKeyCreation()
        XCTAssertTrue(lifecycle.beginReplacementKeyCreation())
        lifecycle.didCreateReplacementKey()

        XCTAssertFalse(lifecycle.beginReplacementKeyCreation())
        XCTAssertFalse(lifecycle.canCreateReplacementRecoveryKey)
    }

    func testRecoveryIdentityResetKeepsTheOrdinarySessionAndReturnsAReplacementKey() async throws {
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        let authorization = try await service.beginEncryptionIdentityReset()
        let resetCompleted = try await service.continueEncryptionIdentityReset(password: "not-recorded")
        let key = try await service.createReplacementEncryptionRecoveryKey()

        let loginCount = await liveClient.loginCount()
        let resetBeginCount = await liveClient.recoveryIdentityResetBeginCount()
        let resetContinuationCount = await liveClient.recoveryIdentityResetContinuationCount()
        let replacementKeyCount = await liveClient.replacementRecoveryKeyCount()

        XCTAssertEqual(authorization, .password)
        XCTAssertTrue(resetCompleted)
        XCTAssertEqual(key, "not-a-real-replacement-key")
        XCTAssertEqual(loginCount, 1)
        XCTAssertEqual(resetBeginCount, 1)
        XCTAssertEqual(resetContinuationCount, 1)
        XCTAssertEqual(replacementKeyCount, 1)
    }

    func testPrimarySessionProvidesAdministratorAuthorityWithoutSecondLogin() async throws {
        let observedTokens = LockedValues<String>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: FakeLiveClient()),
            administratorClientFactory: { _, _, token in
                observedTokens.append(token)
                return FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        let authorized = try await service.isHomeserverAdministrator()
        XCTAssertTrue(authorized)
        XCTAssertEqual(observedTokens.values(), ["fixture-token"])
    }

    func testAdministratorUpgradeDoesNotStartForAlreadyAuthorizedPrimarySession() async throws {
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in FakeMatrixAdminClient(isAdministrator: true) },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        await XCTAssertThrowsMatrixError(
            try await service.beginAdministratorAuthorization(),
            expected: .unavailable(reason: "The primary Matrix session already has administrator capability")
        )
        let authorizedInvocations = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(authorizedInvocations.count, 0)
    }

    func testAdministratorUpgradeDoesNotStartForRoleDeniedPrimarySession() async throws {
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in FakeMatrixAdminClient(isAdministrator: false) },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        do {
            _ = try await service.beginAdministratorAuthorization()
            XCTFail("Expected role denial")
        } catch {
            XCTAssertEqual(error as? MatrixAdminClientError, .notAdministrator)
        }
        let deniedInvocations = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(deniedInvocations.count, 0)
    }

    func testAdministratorUpgradeDoesNotStartForNonExactProbeFailures() async throws {
        let rejectedErrors: [MatrixAdminClientError] = [
            .insufficientScope(required: ["urn:matrix:client:unrelated"]),
            .insufficientScope(required: ["urn:synapse:admin:*", "urn:matrix:client:extra"]),
            .sessionExpired,
            .offline,
            .invalidResponse,
            .serverRejected,
        ]

        for rejectedError in rejectedErrors {
            let liveClient = FakeLiveClient()
            let service = MatrixRustSDKChatService(
                configuration: .production,
                vault: MemorySessionVault(),
                clientFactory: FakeLiveClientFactory(client: liveClient),
                administratorClientFactory: { _, _, _ in
                    FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: rejectedError
                    )
                },
                randomStoreKey: { Data(repeating: 0xA5, count: 32) }
            )
            _ = try await service.signIn(username: "alice", password: "not-recorded")

            do {
                _ = try await service.beginAdministratorAuthorization()
                XCTFail("Expected \(rejectedError) to remain outside the OAuth migration gate")
            } catch {
                XCTAssertEqual(error as? MatrixAdminClientError, rejectedError)
            }

            let invocations = await liveClient.oauthUpgradeInvocations()
            let syncStops = await liveClient.continuousSyncStopCount()
            let syncStarts = await liveClient.continuousSyncStartCount()
            XCTAssertEqual(invocations.count, 0)
            XCTAssertEqual(syncStops, 1)
            XCTAssertEqual(syncStarts, 2)
        }
    }

    func testAdministratorUpgradeUsesActiveDeviceAndPersistsRefreshedPrimarySession() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let observedTokens = LockedValues<String>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, token in
                observedTokens.append(token)
                return observedTokens.values().count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "refreshed-primary-token",
            refreshToken: "refreshed-primary-refresh-token",
            userID: original.userId,
            deviceID: original.deviceId,
            oauthData: "refreshed-oauth-metadata",
            slidingSyncVersion: "refreshed-native",
            storeNamespace: "replacement-store-must-not-win"
        ))

        let request = try await service.beginAdministratorAuthorization()
        try await service.completeAdministratorAuthorization(
            requestID: request.id,
            callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
        )

        let invocations = await liveClient.oauthUpgradeInvocations()
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.deviceID, original.deviceId)
        XCTAssertEqual(invocation.loginHint, "mxid:\(original.userId)")
        XCTAssertEqual(invocation.additionalScopes, ["urn:synapse:admin:*"])
        let syncStops = await liveClient.continuousSyncStopCount()
        let syncStarts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(syncStops, 1)
        XCTAssertEqual(syncStarts, 2)
        XCTAssertEqual(
            try vault.loadSession(),
            MatrixSDKSessionRecord(
                accessToken: "refreshed-primary-token",
                refreshToken: "refreshed-primary-refresh-token",
                userId: original.userId,
                deviceId: original.deviceId,
                homeserverURL: original.homeserverURL,
                oauthData: "refreshed-oauth-metadata",
                slidingSyncVersion: "refreshed-native",
                accountKey: original.accountKey,
                storeNamespace: original.storeNamespace
            )
        )
        XCTAssertNil(try vault.loadProvisionalSession(accountKey: original.accountKey))
        let authorizedAfterUpgrade = try await service.isHomeserverAdministrator()
        XCTAssertTrue(authorizedAfterUpgrade)
        XCTAssertEqual(observedTokens.values().last, "refreshed-primary-token")

        let ended = await service.endAdministratorAuthorization()
        XCTAssertTrue(ended)
        let authorizedAfterEnd = try await service.isHomeserverAdministrator()
        XCTAssertTrue(authorizedAfterEnd)
        let logoutCount = await liveClient.logoutCount()
        XCTAssertEqual(logoutCount, 0)
    }

    func testAdministratorUpgradeConfirmsCandidateAuthorityBeforePersistence() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let persistedTokensAtProbe = LockedValues<String>()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                persistedTokensAtProbe.append((try? vault.loadSession()?.accessToken) ?? "missing")
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "confirmed-before-persistence-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        let request = try await service.beginAdministratorAuthorization()

        try await service.completeAdministratorAuthorization(
            requestID: request.id,
            callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
        )

        XCTAssertEqual(persistedTokensAtProbe.values(), [original.accessToken, original.accessToken])
        XCTAssertEqual(try vault.loadSession()?.accessToken, "confirmed-before-persistence-token")
    }

    func testAdministratorUpgradeRejectsIdentityDriftAndRestoresOriginalPrimarySession() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "wrong-identity-token",
            userID: "@mallory:synapse.zenith-research.ca",
            deviceID: original.deviceId
        ))
        let request = try await service.beginAdministratorAuthorization()

        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .unavailable(reason: "Administrator authorization identity changed")
        )

        XCTAssertEqual(try vault.loadSession(), original)
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertEqual(restoredSessions.last, original)
    }

    func testAdministratorUpgradeRejectsEquivalentButNonidenticalHomeserverRecord() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "representation-drift-token",
            homeserverURL: "https://synapse.zenith-research.ca:443",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        let request = try await service.beginAdministratorAuthorization()

        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .unavailable(reason: "Administrator authorization identity changed")
        )

        XCTAssertEqual(try vault.loadSession(), original)
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertEqual(restoredSessions.last, original)
    }

    func testAdministratorUpgradeRollsBackWhenRefreshedSessionCannotBePersisted() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "refreshed-primary-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        vault.failNextSessionSave(with: FixtureSDKError("simulated persistence failure"))
        let request = try await service.beginAdministratorAuthorization()

        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .unavailable(reason: "Refreshed Matrix session could not be saved")
        )

        XCTAssertEqual(try vault.loadSession(), original)
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertEqual(restoredSessions.last, original)
        let syncStarts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(syncStarts, 2)
    }

    func testAdministratorUpgradeRollsBackWhenFinalAuthorityProbeIsNotConfirmed() async throws {
        let outcomes: [(Result<Bool, MatrixAdminClientError>, MatrixAdminClientError)] = [
            (.success(false), .notAdministrator),
            (.failure(.offline), .offline),
        ]

        for (outcome, expectedError) in outcomes {
            let vault = MemorySessionVault()
            let liveClient = FakeLiveClient()
            let probeCount = LockedValues<Int>()
            let service = MatrixRustSDKChatService(
                configuration: .production,
                vault: vault,
                clientFactory: FakeLiveClientFactory(client: liveClient),
                administratorClientFactory: { _, _, _ in
                    let count = probeCount.values().count + 1
                    probeCount.append(count)
                    if count == 1 {
                        return FakeMatrixAdminClient(
                            isAdministrator: false,
                            administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                        )
                    }
                    switch outcome {
                    case let .success(isAdministrator):
                        return FakeMatrixAdminClient(isAdministrator: isAdministrator)
                    case let .failure(error):
                        return FakeMatrixAdminClient(isAdministrator: false, administratorError: error)
                    }
                },
                randomStoreKey: { Data(repeating: 0xA5, count: 32) }
            )
            _ = try await service.signIn(username: "alice", password: "not-recorded")
            let original = try XCTUnwrap(vault.loadSession())
            await liveClient.setOAuthCompletionSession(.fixture(
                accountKey: original.accountKey,
                accessToken: "unconfirmed-refreshed-token",
                userID: original.userId,
                deviceID: original.deviceId
            ))
            let request = try await service.beginAdministratorAuthorization()

            do {
                try await service.completeAdministratorAuthorization(
                    requestID: request.id,
                    callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
                )
                XCTFail("Expected final administrator authority to remain unconfirmed")
            } catch {
                XCTAssertEqual(error as? MatrixAdminClientError, expectedError)
            }

            XCTAssertEqual(try vault.loadSession(), original)
            XCTAssertNil(try vault.loadProvisionalSession(accountKey: original.accountKey))
            let restoredSessions = await liveClient.restoredSessions()
            XCTAssertEqual(restoredSessions.last, original)
            let syncStarts = await liveClient.continuousSyncStartCount()
            XCTAssertEqual(syncStarts, 2)
        }
    }

    func testAdministratorUpgradeRollsBackWhenSDKMutatesSessionThenThrows() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "partially-committed-sdk-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.setOAuthCompletionErrorAfterMutation(
            FixtureSDKError("simulated callback failure after SDK mutation")
        )
        let request = try await service.beginAdministratorAuthorization()

        do {
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            )
            XCTFail("Expected callback completion failure")
        } catch {
            XCTAssertTrue(error is FixtureSDKError)
        }

        XCTAssertEqual(try vault.loadSession(), original)
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertEqual(restoredSessions.last, original)
        let syncStarts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(syncStarts, 2)
    }

    func testRestoredUpgradedPrimarySessionProvidesAuthorityWithoutOAuth() async throws {
        let vault = MemorySessionVault()
        let initialClient = FakeLiveClient()
        let initialProbeCount = LockedValues<Int>()
        let initialService = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: initialClient),
            administratorClientFactory: { _, _, _ in
                let count = initialProbeCount.values().count + 1
                initialProbeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await initialService.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await initialClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "restorable-administrator-token",
            refreshToken: "restorable-refresh-token",
            homeserverURL: original.homeserverURL,
            userID: original.userId,
            deviceID: original.deviceId,
            oauthData: "restorable-oauth-metadata",
            slidingSyncVersion: original.slidingSyncVersion
        ))
        let request = try await initialService.beginAdministratorAuthorization()
        try await initialService.completeAdministratorAuthorization(
            requestID: request.id,
            callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
        )
        _ = await initialService.suspend()

        let restoredClient = FakeLiveClient()
        let restoredTokens = LockedValues<String>()
        let restoredService = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: restoredClient),
            administratorClientFactory: { _, _, token in
                restoredTokens.append(token)
                return FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0x00, count: 32) }
        )

        _ = try await restoredService.restore()
        let restoredAuthority = try await restoredService.isHomeserverAdministrator()
        XCTAssertTrue(restoredAuthority)
        XCTAssertEqual(restoredTokens.values(), ["restorable-administrator-token"])
        let oauthInvocations = await restoredClient.oauthUpgradeInvocations()
        XCTAssertEqual(oauthInvocations.count, 0)
    }

    func testSuspendDoesNotClearSessionWhileAdministratorOAuthCompletionIsInFlight() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "serialized-completion-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.suspendOAuthCompletion()
        let request = try await service.beginAdministratorAuthorization()
        let completion = Task {
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            )
        }
        await liveClient.waitUntilOAuthCompletionStarted()

        _ = await service.suspend()
        await liveClient.resumeOAuthCompletion()
        try await completion.value

        XCTAssertEqual(try vault.loadSession()?.accessToken, "serialized-completion-token")
        let authority = try await service.isHomeserverAdministrator()
        XCTAssertTrue(authority)
    }

    func testRoomRefreshCannotSyncWhileAdministratorOAuthCompletionIsInFlight() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "sync-isolated-completion-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.suspendOAuthCompletion()
        let request = try await service.beginAdministratorAuthorization()
        let completion = Task {
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            )
        }
        await liveClient.waitUntilOAuthCompletionStarted()

        await XCTAssertThrowsMatrixError(
            try await service.refreshRooms(),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )
        let syncsWhileSuspended = await liveClient.syncCount()
        let stopsWhileSuspended = await liveClient.continuousSyncStopCount()
        let startsWhileSuspended = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(syncsWhileSuspended, 1)
        XCTAssertEqual(stopsWhileSuspended, 1)
        XCTAssertEqual(startsWhileSuspended, 1)

        await liveClient.resumeOAuthCompletion()
        try await completion.value
        let startsAfterCompletion = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(startsAfterCompletion, 2)
    }

    func testRollbackFailureQuarantinesSessionWithoutRestartingSync() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "rollback-failure-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.setOAuthCompletionErrorAfterMutation(
            FixtureSDKError("simulated callback failure after SDK mutation")
        )
        vault.failNextSessionSave(with: FixtureSDKError("simulated rollback persistence failure"))
        let request = try await service.beginAdministratorAuthorization()

        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .recoveryRequired
        )

        let syncStarts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(syncStarts, 1)
        do {
            _ = try await service.isHomeserverAdministrator()
            XCTFail("Expected quarantined session")
        } catch {
            XCTAssertEqual(error as? MatrixChatServiceError, .sessionExpired)
        }
        XCTAssertEqual(try vault.loadSession(), original)
    }

    func testConcurrentAdministratorAuthorizationBeginReservesOneLifecycleBeforeAwait() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let suspendedProbe = FakeMatrixAdminClient(
            isAdministrator: false,
            administratorError: .insufficientScope(required: ["urn:synapse:admin:*"]),
            suspendAdministratorProbe: true
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in suspendedProbe },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let firstBegin = Task { try await service.beginAdministratorAuthorization() }
        await suspendedProbe.waitUntilAdministratorProbeStarted()

        await XCTAssertThrowsMatrixError(
            try await service.beginAdministratorAuthorization(),
            expected: .unavailable(reason: "Administrator authorization is already in progress")
        )

        await suspendedProbe.resumeAdministratorProbe()
        let request = try await firstBegin.value
        let invocations = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(invocations.count, 1)
        let cancelled = await service.cancelAdministratorAuthorization(requestID: request.id)
        XCTAssertTrue(cancelled)
    }

    func testCancellationDuringSuspendedAdministratorPreflightReleasesOwnership() async throws {
        let liveClient = FakeLiveClient()
        let suspendedProbe = FakeMatrixAdminClient(
            isAdministrator: false,
            administratorError: .insufficientScope(required: ["urn:synapse:admin:*"]),
            suspendAdministratorProbe: true
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in suspendedProbe },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let firstBegin = Task { try await service.beginAdministratorAuthorization() }
        await suspendedProbe.waitUntilAdministratorProbeStarted()
        let stopsDuringPreflight = await liveClient.continuousSyncStopCount()
        let startsDuringPreflight = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(stopsDuringPreflight, 1)
        XCTAssertEqual(startsDuringPreflight, 1)

        let cancellationFinishedSynchronously = await service.cancelAdministratorAuthorization(requestID: nil)
        XCTAssertFalse(cancellationFinishedSynchronously)
        do {
            _ = try await firstBegin.value
            XCTFail("Expected cancelled administrator preflight")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        await suspendedProbe.resumeAdministratorProbe()
        var secondRequest: MatrixAdminOAuthRequest?
        for _ in 0..<100 {
            do {
                secondRequest = try await service.beginAdministratorAuthorization()
                break
            } catch MatrixChatServiceError.unavailable {
                await Task.yield()
            }
        }
        let resumedRequest = try XCTUnwrap(secondRequest)
        let cancelled = await service.cancelAdministratorAuthorization(requestID: resumedRequest.id)
        XCTAssertTrue(cancelled)
        let invocations = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(invocations.count, 1)
    }

    func testAdministratorAuthorizationCannotOverlapSuspendedOrdinaryClientOperation() async throws {
        let liveClient = FakeLiveClient()
        await liveClient.setRooms([
            MatrixRoomSummary(
                id: "!encrypted:example.org",
                name: "Encrypted",
                isEncrypted: true,
                hasInvite: false
            )
        ])
        await liveClient.suspendSend()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: MatrixPrimarySessionOAuth.requiredScopes)
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")

        let send = Task { try await service.sendText("in flight", to: "!encrypted:example.org") }
        await liveClient.waitUntilSendStarted()
        await XCTAssertThrowsMatrixError(
            try await service.beginAdministratorAuthorization(),
            expected: .unavailable(reason: "A primary Matrix operation is still in progress")
        )
        let invocationsWhileSendSuspended = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(invocationsWhileSendSuspended.count, 0)

        await liveClient.resumeSend()
        try await send.value
        _ = try await service.beginAdministratorAuthorization()
        let invocationsAfterSend = await liveClient.oauthUpgradeInvocations()
        XCTAssertEqual(invocationsAfterSend.count, 1)
    }

    func testCancellationDuringSuspendedOAuthURLCreationRetainsBarrierUntilLateResult() async throws {
        let liveClient = FakeLiveClient()
        await liveClient.suspendOAuthBegin()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let begin = Task { try await service.beginAdministratorAuthorization() }
        await liveClient.waitUntilOAuthBeginStarted()

        let cancelledSynchronously = await service.cancelAdministratorAuthorization(requestID: nil)
        XCTAssertFalse(cancelledSynchronously)
        do {
            _ = try await begin.value
            XCTFail("Expected OAuth URL creation cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        await XCTAssertThrowsMatrixError(
            try await service.refreshRooms(),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )

        await liveClient.resumeOAuthBegin()
        await liveClient.waitUntilOAuthBeginFinished()
        var refreshSucceeded = false
        for _ in 0..<100 {
            do {
                _ = try await service.refreshRooms()
                refreshSucceeded = true
                break
            } catch MatrixChatServiceError.unavailable {
                await Task.yield()
            }
        }
        XCTAssertTrue(refreshSucceeded)
    }

    func testPrimarySessionTransitionPreventsAdministratorOAuthFromStarting() async throws {
        let liveClient = FakeLiveClient()
        await liveClient.suspendSync()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        let signIn = Task {
            try await service.signIn(username: "alice", password: "not-recorded")
        }
        await liveClient.waitUntilSyncStarted()

        await XCTAssertThrowsMatrixError(
            try await service.beginAdministratorAuthorization(),
            expected: .unavailable(reason: "Administrator authorization is already in progress")
        )

        await liveClient.resumeSync()
        _ = try await signIn.value
        let oauthInvocations = await liveClient.oauthUpgradeInvocations()
        XCTAssertTrue(oauthInvocations.isEmpty)
    }

    func testOrdinaryAndProtectedAPIsCannotUseUncommittedOAuthSession() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: true)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "uncommitted-session-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.suspendOAuthCompletion()
        let request = try await service.beginAdministratorAuthorization()
        let completion = Task {
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            )
        }
        await liveClient.waitUntilOAuthCompletionStarted()

        XCTAssertTrue(try vault.hasPendingOAuthCompletion(accountKey: original.accountKey))
        XCTAssertNil(try vault.loadProvisionalSession(accountKey: original.accountKey))

        await XCTAssertThrowsMatrixError(
            try await service.sendText("must-not-send", to: "!encrypted:example.org"),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )
        await XCTAssertThrowsMatrixError(
            try await service.administratorSnapshot(),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )
        await XCTAssertThrowsMatrixError(
            try await service.restore(),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )
        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "must-not-run"),
            expected: .unavailable(reason: "Administrator authorization is still completing")
        )
        let sentBodies = await liveClient.sentBodies()
        XCTAssertTrue(sentBodies.isEmpty)

        await liveClient.resumeOAuthCompletion()
        try await completion.value
    }

    func testRollbackSlidingSyncDriftQuarantinesSession() async throws {
        let vault = MemorySessionVault()
        let liveClient = FakeLiveClient()
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: false)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let original = try XCTUnwrap(vault.loadSession())
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "rollback-drift-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        await liveClient.setRestoredSlidingSyncVersionOverride("unexpected-session-mode")
        let request = try await service.beginAdministratorAuthorization()

        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .recoveryRequired
        )
        let starts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(starts, 1)
        do {
            _ = try await service.isHomeserverAdministrator()
            XCTFail("Expected quarantined session")
        } catch {
            XCTAssertEqual(error as? MatrixChatServiceError, .sessionExpired)
        }
    }

    func testQRStoreNamespaceRollbackNormalizesSDKSessionExport() async throws {
        let vault = MemorySessionVault()
        let original = MatrixSDKSessionRecord.fixture(
            accountKey: "qr-origin-account",
            accessToken: "qr-origin-token",
            storeNamespace: "qr-origin-store-namespace"
        )
        try vault.saveSession(original)
        try vault.saveStoreKey(Data(repeating: 0xA5, count: 32), accountKey: original.accountKey)
        let liveClient = FakeLiveClient()
        await liveClient.setOmitRestoredStoreNamespace(true)
        let probeCount = LockedValues<Int>()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                let count = probeCount.values().count + 1
                probeCount.append(count)
                return count == 1
                    ? FakeMatrixAdminClient(
                        isAdministrator: false,
                        administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                    )
                    : FakeMatrixAdminClient(isAdministrator: false)
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.restore()
        await liveClient.setOAuthCompletionSession(.fixture(
            accountKey: original.accountKey,
            accessToken: "qr-origin-candidate-token",
            userID: original.userId,
            deviceID: original.deviceId
        ))
        let request = try await service.beginAdministratorAuthorization()

        do {
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            )
            XCTFail("Expected final authority denial")
        } catch {
            XCTAssertEqual(error as? MatrixAdminClientError, .notAdministrator)
        }

        XCTAssertEqual(try vault.loadSession(), original)
        let starts = await liveClient.continuousSyncStartCount()
        XCTAssertEqual(starts, 2)
    }

    func testAdministratorUpgradeCancellationAbortsOnlyPendingActiveClientOAuth() async throws {
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: liveClient),
            administratorClientFactory: { _, _, _ in
                FakeMatrixAdminClient(
                    isAdministrator: false,
                    administratorError: .insufficientScope(required: ["urn:synapse:admin:*"])
                )
            },
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let request = try await service.beginAdministratorAuthorization()

        let cancelled = await service.cancelAdministratorAuthorization(requestID: request.id)
        let cancellationCount = await liveClient.oauthCancellationCount()
        let logoutCount = await liveClient.logoutCount()
        XCTAssertTrue(cancelled)
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(logoutCount, 0)
        await XCTAssertThrowsMatrixError(
            try await service.completeAdministratorAuthorization(
                requestID: request.id,
                callbackURL: URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
            ),
            expected: .unavailable(reason: "Administrator authorization request is stale or invalid")
        )
    }

    func testAdministratorOAuthCallbackValidationIsExact() {
        XCTAssertEqual(
            MatrixPrimarySessionOAuth.callbackScheme,
            "ca.zenith-research.hypha"
        )
        XCTAssertTrue(MatrixPrimarySessionOAuth.validCallback(
            URL(string: "ca.zenith-research.hypha:/oauth?code=opaque&state=opaque")!
        ))
        for invalid in [
            "ca.zenithresearch.hypha:/oauth?code=opaque&state=opaque",
            "https://ca.zenith-research.hypha/oauth",
            "ca.zenith-research.hypha://attacker.example/oauth",
            "ca.zenith-research.hypha:/oauth/extra",
            "ca.zenith-research.hypha:/oauth#fragment",
        ] {
            XCTAssertFalse(MatrixPrimarySessionOAuth.validCallback(URL(string: invalid)!))
        }
    }


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

    func testSignInRemainsActiveWhenIncomingVerificationControllerIsUnavailable() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient(
            incomingVerificationHandlerError: FixtureSDKError("verification controller unavailable")
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        let rooms = try await service.signIn(username: "alice", password: "not-recorded")
        let continuousSyncStartCount = await client.continuousSyncStartCount()

        XCTAssertEqual(rooms, [])
        XCTAssertEqual(try vault.loadSession()?.userId, "@alice:example.org")
        XCTAssertEqual(continuousSyncStartCount, 1)
    }

    func testQrLoginPersistsCanonicalAccountWithItsProvisionalEncryptedStore() async throws {
        let vault = MemorySessionVault()
        let client = FakeLiveClient(
            sessionUserID: "@alice:synapse.zenith-research.ca",
            qrLoginUpdates: [
                .starting,
                .checkCodeDisplay("42"),
                .syncingSecrets,
                .completed,
            ]
        )
        await client.setRooms([
            MatrixRoomSummary(id: "!encrypted:example.org", name: "Encrypted", isEncrypted: true, hasInvite: false)
        ])
        let factory = FakeLiveClientFactory(client: client, qrLoginSupported: true)
        let provisionalNamespace = String(repeating: "a", count: 64)
        let storeKey = Data(repeating: 0xB6, count: 32)
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: factory,
            randomStoreKey: { storeKey },
            randomStoreNamespace: { provisionalNamespace }
        )
        let updates = LockedQrProgress()

        let rooms = try await service.signInWithQrCode(Data([0x4d, 0x41, 0x54, 0x52, 0x49, 0x58])) {
            updates.append($0)
        }

        let canonicalAccountKey = MatrixRustSDKChatService.accountKey(
            username: "@alice:synapse.zenith-research.ca",
            homeserver: MatrixProductConfiguration.production.homeserver
        )
        let qrStoreNamespaces = await factory.qrStoreNamespaces()
        XCTAssertEqual(rooms.map(\.id), ["!encrypted:example.org"])
        XCTAssertEqual(updates.values(), [.starting, .checkCodeDisplay("42"), .syncingSecrets, .completed])
        XCTAssertEqual(qrStoreNamespaces, [provisionalNamespace])
        XCTAssertEqual(try vault.loadedStoreKey(), storeKey)
        XCTAssertEqual(try vault.loadSession()?.accountKey, canonicalAccountKey)
        XCTAssertEqual(try vault.loadSession()?.storeNamespace, provisionalNamespace)
    }

    func testQrLoginRefusesToReplaceAnExistingCanonicalEncryptedStore() async throws {
        let canonicalAccountKey = MatrixRustSDKChatService.accountKey(
            username: "@alice:synapse.zenith-research.ca",
            homeserver: MatrixProductConfiguration.production.homeserver
        )
        let existingKey = Data(repeating: 0xA5, count: 32)
        let existingSession = MatrixSDKSessionRecord.fixture(
            accountKey: canonicalAccountKey,
            storeNamespace: String(repeating: "b", count: 64)
        )
        let vault = MemorySessionVault()
        try vault.saveStoreKey(existingKey, accountKey: canonicalAccountKey)
        try vault.saveSession(existingSession)
        let provisionalNamespace = String(repeating: "a", count: 64)
        let factory = FakeLiveClientFactory(
            client: FakeLiveClient(sessionUserID: "@alice:synapse.zenith-research.ca"),
            qrLoginSupported: true
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: factory,
            randomStoreKey: { Data(repeating: 0xB6, count: 32) },
            randomStoreNamespace: { provisionalNamespace }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signInWithQrCode(Data([0x4d])) { _ in },
            expected: .unavailable(reason: "A saved Hypha session already owns this account")
        )

        XCTAssertEqual(try vault.loadSession(accountKey: canonicalAccountKey), existingSession)
        XCTAssertEqual(try vault.loadStoreKey(accountKey: canonicalAccountKey), existingKey)
        let resetAccountKeys = await factory.resetAccountKeys()
        XCTAssertEqual(resetAccountKeys, [provisionalNamespace])
    }

    func testQrLoginRollsBackCanonicalStoreKeyWhenSessionPersistenceFails() async throws {
        let provisionalNamespace = String(repeating: "a", count: 64)
        let vault = MemorySessionVault(saveSessionError: FixtureSDKError("write failed"))
        let factory = FakeLiveClientFactory(
            client: FakeLiveClient(sessionUserID: "@alice:synapse.zenith-research.ca"),
            qrLoginSupported: true
        )
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: factory,
            randomStoreKey: { Data(repeating: 0xB6, count: 32) },
            randomStoreNamespace: { provisionalNamespace }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signInWithQrCode(Data([0x4d])) { _ in },
            expected: .unavailable(reason: "Secure QR login failed")
        )

        XCTAssertNil(try vault.loadSession())
        XCTAssertNil(try vault.loadedStoreKey())
        let resetAccountKeys = await factory.resetAccountKeys()
        XCTAssertEqual(resetAccountKeys, [provisionalNamespace])
    }

    func testPasswordSignInResetsAbandonedCryptoStoreWhenNoSessionRemains() async throws {
        let accountKey = MatrixRustSDKChatService.accountKey(
            username: "beaver",
            homeserver: MatrixProductConfiguration.production.homeserver
        )
        let abandonedStoreKey = Data(repeating: 0xA5, count: 32)
        let replacementStoreKey = Data(repeating: 0xB6, count: 32)
        let vault = MemorySessionVault()
        try vault.saveStoreKey(abandonedStoreKey, accountKey: accountKey)
        let factory = FakeLiveClientFactory(client: FakeLiveClient())
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: factory,
            randomStoreKey: { replacementStoreKey }
        )

        _ = try await service.signIn(username: "beaver", password: "not-recorded")

        let resetAccountKeys = await factory.resetAccountKeys()
        let madeStoreKeys = await factory.madeStoreKeys()
        XCTAssertEqual(resetAccountKeys, [accountKey])
        XCTAssertEqual(madeStoreKeys, [replacementStoreKey])
        XCTAssertEqual(try vault.loadedStoreKey(), replacementStoreKey)
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

    func testSignInMapsHomeserverApprovalGateToActionableFailure() async throws {
        let client = FakeLiveClient(loginError: ClientError.MatrixApi(
            kind: .unknown,
            code: "M_USER_AWAITING_APPROVAL",
            msg: "redacted homeserver message",
            details: nil
        ))
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        await XCTAssertThrowsMatrixError(
            try await service.signIn(username: "alice", password: "not-recorded"),
            expected: .unavailable(reason: "Account is awaiting homeserver approval")
        )
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

    func testRestoreQuarantinesIncompleteAdministratorOAuthJournalBeforeOpeningSDKStore() async throws {
        let vault = MemorySessionVault()
        let original = MatrixSDKSessionRecord.fixture()
        let provisional = MatrixSDKSessionRecord.fixture(
            accountKey: original.accountKey,
            accessToken: "provisional-primary-token",
            refreshToken: "provisional-primary-refresh",
            userID: original.userId,
            deviceID: original.deviceId,
            oauthData: "provisional-oauth-metadata",
            slidingSyncVersion: original.slidingSyncVersion,
            storeNamespace: original.storeNamespace
        )
        try vault.saveSession(original)
        try vault.saveStoreKey(Data(repeating: 0xA5, count: 32), accountKey: original.accountKey)
        try vault.saveProvisionalSession(provisional)
        try vault.markPendingOAuthCompletion(accountKey: original.accountKey)
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        do {
            _ = try await service.restore()
            XCTFail("Expected incomplete OAuth transaction to require recovery")
        } catch {
            XCTAssertEqual(error as? MatrixChatServiceError, .recoveryRequired)
        }
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertTrue(restoredSessions.isEmpty)
        XCTAssertEqual(try vault.loadSession(), original)
        XCTAssertEqual(try vault.loadProvisionalSession(accountKey: original.accountKey), provisional)
    }

    func testRestoreReconcilesCanonicalPromotionCompletedBeforeJournalCleanup() async throws {
        let vault = MemorySessionVault()
        let promoted = MatrixSDKSessionRecord.fixture(accessToken: "promoted-primary-token")
        try vault.saveSession(promoted)
        try vault.saveStoreKey(Data(repeating: 0xA5, count: 32), accountKey: promoted.accountKey)
        try vault.saveProvisionalSession(promoted)
        try vault.markPendingOAuthCompletion(accountKey: promoted.accountKey)
        let liveClient = FakeLiveClient()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: vault,
            clientFactory: FakeLiveClientFactory(client: liveClient),
            randomStoreKey: { Data(repeating: 0xA5, count: 32) }
        )

        _ = try await service.restore()

        XCTAssertFalse(try vault.hasPendingOAuthCompletion(accountKey: promoted.accountKey))
        XCTAssertNil(try vault.loadProvisionalSession(accountKey: promoted.accountKey))
        XCTAssertEqual(try vault.loadSession(), promoted)
        let restoredSessions = await liveClient.restoredSessions()
        XCTAssertEqual(restoredSessions.last, promoted)
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

    func testServiceStoresAndReadsRepositoryAttachmentForJoinedRoom() async throws {
        let room = MatrixRoomSummary(
            id: "!repo:example.org",
            name: "Repository room",
            isEncrypted: true,
            hasInvite: false
        )
        let attachment = MatrixRoomRepositoryAttachment(
            repository: "git@github.com:ZenithResearch/Hypha.git",
            name: "Hypha"
        )
        let client = FakeLiveClient()
        await client.setRooms([room])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        try await service.setRoomRepositoryAttachment(attachment, roomID: room.id)

        let storedAttachment = try await service.roomRepositoryAttachment(roomID: room.id)
        let writes = await client.observedRepositoryAttachmentWrites()
        XCTAssertEqual(storedAttachment, attachment)
        XCTAssertEqual(writes, [attachment])
    }

    func testServiceForwardsInviteOnlyForCachedEligibleRoom() async throws {
        let room = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )
        let request = MatrixRoomInviteRequest(
            roomID: room.id,
            userIDs: ["@bob:example.org"]
        )
        let client = FakeLiveClient()
        await client.setRooms([room])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        try await service.inviteUsers(request)

        let observedRequests = await client.observedRoomInviteRequests()
        XCTAssertEqual(observedRequests, [request])
    }

    func testServiceForwardsExactUserLookupOnlyForCachedEligibleRoom() async throws {
        let room = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )
        let expected = MatrixUserLookupResult.exists(userID: "@mgpi:example.org", displayName: "MGPI")
        let client = FakeLiveClient(userLookupResult: expected)
        await client.setRooms([room])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        let result = try await service.lookupInviteUser(userID: "@mgpi:example.org", roomID: room.id)

        let observedRequests = await client.observedUserLookupRequests()
        XCTAssertEqual(result, expected)
        XCTAssertEqual(observedRequests, ["@mgpi:example.org"])
    }

    func testServiceFailsClosedWhenLiveInvitePermissionChanged() async throws {
        let room = MatrixRoomSummary(
            id: "!eligible:example.org",
            name: "Eligible",
            isEncrypted: true,
            hasInvite: false,
            canInviteMembers: true
        )
        let client = FakeLiveClient(invitationError: MatrixChatServiceError.unavailable(reason: "Invite permission changed"))
        await client.setRooms([room])
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "secret")

        do {
            try await service.inviteUsers(
                MatrixRoomInviteRequest(roomID: room.id, userIDs: ["@bob:example.org"])
            )
            XCTFail("Expected changed invite permission to fail closed")
        } catch {}
        let observedRequests = await client.observedRoomInviteRequests()
        XCTAssertEqual(observedRequests, [])
    }

    func testServiceRejectsCachedPendingInvitationAndSpaceBeforeLiveInvite() async throws {
        for blockedRoom in [
            MatrixRoomSummary(
                id: "!pending:example.org",
                name: "Pending",
                isEncrypted: true,
                hasInvite: true,
                canInviteMembers: true
            ),
            MatrixRoomSummary(
                id: "!space:example.org",
                name: "Space",
                isEncrypted: false,
                hasInvite: false,
                isSpace: true,
                canInviteMembers: true
            ),
        ] {
            let client = FakeLiveClient()
            await client.setRooms([blockedRoom])
            let service = MatrixRustSDKChatService(
                configuration: .production,
                vault: MemorySessionVault(),
                clientFactory: FakeLiveClientFactory(client: client),
                randomStoreKey: { Data(repeating: 2, count: 32) }
            )
            _ = try await service.signIn(username: "alice", password: "secret")

            do {
                try await service.inviteUsers(
                    MatrixRoomInviteRequest(roomID: blockedRoom.id, userIDs: ["@bob:example.org"])
                )
                XCTFail("Expected cached pending invitation or Space to fail closed")
            } catch {}
            let observedRequests = await client.observedRoomInviteRequests()
            XCTAssertEqual(observedRequests, [])
        }
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

        _ = await service.suspend()
        let stopCount = await client.continuousSyncStopCount()

        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(try vault.loadSession(), savedBeforeSuspend)
    }

    func testSuspendDoesNotClearPrimarySessionWhileOrdinaryOperationIsInFlight() async throws {
        let client = FakeLiveClient(trustState: .verifiedByCurrentSelfSigningKey)
        await client.setRooms([
            MatrixRoomSummary(
                id: "!encrypted:example.org",
                name: "Encrypted",
                isEncrypted: true,
                hasInvite: false
            )
        ])
        await client.suspendSend()
        let service = MatrixRustSDKChatService(
            configuration: .production,
            vault: MemorySessionVault(),
            clientFactory: FakeLiveClientFactory(client: client),
            randomStoreKey: { Data(repeating: 2, count: 32) }
        )
        _ = try await service.signIn(username: "alice", password: "not-recorded")
        let send = Task { try await service.sendText("in flight", to: "!encrypted:example.org") }
        await client.waitUntilSendStarted()

        let suspendedWhileSendIsInFlight = await service.suspend()
        XCTAssertFalse(suspendedWhileSendIsInFlight)
        let stopsWhileSendIsInFlight = await client.continuousSyncStopCount()
        XCTAssertEqual(stopsWhileSendIsInFlight, 0)

        await client.resumeSend()
        try await send.value
        let suspendedAfterSendSettles = await service.suspend()
        XCTAssertTrue(suspendedAfterSendSettles)
        let stopsAfterSendSettles = await client.continuousSyncStopCount()
        XCTAssertEqual(stopsAfterSendSettles, 1)
        await XCTAssertThrowsMatrixError(
            try await service.deviceTrustState(),
            expected: .sessionExpired
        )
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
        let session = MatrixSASVerificationSession(controller: controller, stageObserver: { stage in
            stages.append(stage)
        })
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

    func testSASSessionRequiresConsentBeforeAcceptingIncomingRequest() async throws {
        let controller = DiagnosticSessionVerificationController()
        let states = LockedVerificationStates()
        let session = MatrixSASVerificationSession(
            controller: controller,
            incomingStateObserver: { states.append($0) }
        )

        controller.deliverIncomingRequest(senderID: "@alice:example.org", flowID: "flow-1")
        await states.waitUntilContains(.incomingRequest)
        XCTAssertFalse(controller.incomingWasAcknowledged())
        XCTAssertFalse(controller.incomingWasAccepted())

        try await session.acceptIncomingRequest()
        await controller.waitUntilIncomingAccepted()
        controller.deliverVerificationData(.decimals(values: [111, 222, 333]))
        await states.waitUntilContains(.challenge(.decimals([111, 222, 333])))

        XCTAssertEqual(states.snapshot(), [
            .incomingRequest,
            .challenge(.decimals([111, 222, 333])),
        ])
        withExtendedLifetime(session) {}
    }

    func testSASSessionCanDeclineIncomingRequestBeforeProtocolAcceptance() async {
        let controller = DiagnosticSessionVerificationController()
        let states = LockedVerificationStates()
        let session = MatrixSASVerificationSession(
            controller: controller,
            incomingStateObserver: { states.append($0) }
        )

        controller.deliverIncomingRequest(senderID: "@alice:example.org", flowID: "flow-1")
        await states.waitUntilContains(.incomingRequest)
        await session.declineOrCancel()

        XCTAssertFalse(controller.incomingWasAcknowledged())
        XCTAssertFalse(controller.incomingWasAccepted())
    }
}

private final class LockedVerificationStates: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [MatrixVerificationFlowState] = []

    func append(_ value: MatrixVerificationFlowState) { lock.withLock { values.append(value) } }
    func snapshot() -> [MatrixVerificationFlowState] { lock.withLock { values } }
    func waitUntilContains(_ state: MatrixVerificationFlowState) async {
        while !lock.withLock({ values.contains(state) }) { await Task.yield() }
    }
}

private final class LockedValues<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    func append(_ value: Value) { lock.withLock { stored.append(value) } }
    func values() -> [Value] { lock.withLock { stored } }
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
    private var acknowledgedIncoming = false
    private var acceptedIncoming = false

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

    override func acknowledgeVerificationRequest(senderId: String, flowId: String) async throws {
        lock.withLock { acknowledgedIncoming = true }
    }

    override func acceptVerificationRequest() async throws {
        let currentDelegate = lock.withLock {
            acceptedIncoming = true
            return delegate
        }
        currentDelegate?.didAcceptVerificationRequest()
    }

    override func cancelVerification() async throws {}
    override func declineVerification() async throws {}

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

    func deliverIncomingRequest(senderID: String, flowID: String) {
        let details = SessionVerificationRequestDetails(
            senderProfile: UserProfile(
                userId: senderID,
                displayName: nil,
                avatarUrl: nil,
                status: nil,
                call: nil
            ),
            flowId: flowID,
            deviceId: "DEVICE",
            deviceDisplayName: "Other Hypha",
            firstSeenTimestamp: 0
        )
        lock.withLock { delegate }?.didReceiveVerificationRequest(details: details)
    }

    func deliverVerificationData(_ data: SessionVerificationData) {
        lock.withLock { delegate }?.didReceiveVerificationData(data: data)
    }

    func waitUntilIncomingAccepted() async {
        while !lock.withLock({ acknowledgedIncoming && acceptedIncoming }) { await Task.yield() }
    }

    func incomingWasAcknowledged() -> Bool { lock.withLock { acknowledgedIncoming } }
    func incomingWasAccepted() -> Bool { lock.withLock { acceptedIncoming } }

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

private final class LockedQrProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [MatrixQrLoginProgress] = []

    func append(_ update: MatrixQrLoginProgress) {
        lock.withLock { updates.append(update) }
    }

    func values() -> [MatrixQrLoginProgress] {
        lock.withLock { updates }
    }
}

private final class MemorySessionVault: MatrixSDKSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MatrixSDKSessionRecord?
    private var provisionalSession: MatrixSDKSessionRecord?
    private var pendingOAuthCompletionAccountKey: String?
    private var storeKey: Data?
    private let saveSessionError: Error?
    private var nextSaveSessionError: Error?

    init(saveSessionError: Error? = nil) {
        self.saveSessionError = saveSessionError
    }

    func loadSession() throws -> MatrixSDKSessionRecord? { lock.withLock { session } }
    func loadSession(accountKey: String) throws -> MatrixSDKSessionRecord? {
        lock.withLock { session?.accountKey == accountKey ? session : nil }
    }
    func saveSession(_ value: MatrixSDKSessionRecord) throws {
        if let saveSessionError { throw saveSessionError }
        try lock.withLock {
            if let nextSaveSessionError {
                self.nextSaveSessionError = nil
                throw nextSaveSessionError
            }
            session = value
        }
    }
    func loadProvisionalSession(accountKey: String) throws -> MatrixSDKSessionRecord? {
        lock.withLock { provisionalSession?.accountKey == accountKey ? provisionalSession : nil }
    }
    func saveProvisionalSession(_ value: MatrixSDKSessionRecord) throws {
        lock.withLock { provisionalSession = value }
    }
    func deleteProvisionalSession(accountKey: String) throws {
        lock.withLock {
            if provisionalSession?.accountKey == accountKey { provisionalSession = nil }
        }
    }
    func hasPendingOAuthCompletion(accountKey: String) throws -> Bool {
        lock.withLock { pendingOAuthCompletionAccountKey == accountKey }
    }
    func markPendingOAuthCompletion(accountKey: String) throws {
        lock.withLock { pendingOAuthCompletionAccountKey = accountKey }
    }
    func clearPendingOAuthCompletion(accountKey: String) throws {
        lock.withLock {
            if pendingOAuthCompletionAccountKey == accountKey { pendingOAuthCompletionAccountKey = nil }
        }
    }
    func failNextSessionSave(with error: Error) {
        lock.withLock { nextSaveSessionError = error }
    }
    func deleteSession() throws { lock.withLock { session = nil } }
    func loadStoreKey(accountKey: String) throws -> Data? { lock.withLock { storeKey } }
    func saveStoreKey(_ value: Data, accountKey: String) throws { lock.withLock { storeKey = value } }
    func deleteStoreKey(accountKey: String) throws { lock.withLock { storeKey = nil } }
    func loadedStoreKey() throws -> Data? { lock.withLock { storeKey } }
}

private actor FakeLiveClient: MatrixLiveClient {
    struct OAuthUpgradeInvocation: Equatable, Sendable {
        let deviceID: String
        let loginHint: String
        let additionalScopes: [String]
    }

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
    private var recoveryIdentityResetBegins = 0
    private var recoveryIdentityResetContinuations = 0
    private var replacementRecoveryKeys = 0
    private var recoveryKeys: [String] = []
    private var passwordChange: PasswordChangeRequest?
    private var restored: [MatrixSDKSessionRecord] = []
    private var currentSession: MatrixSDKSessionRecord?
    private var oauthCompletionSession: MatrixSDKSessionRecord?
    private var oauthCompletionErrorAfterMutation: Error?
    private var restoredSlidingSyncVersionOverride: String?
    private var omitRestoredStoreNamespace = false
    private var shouldSuspendOAuthCompletion = false
    private var oauthCompletionStarted = false
    private var oauthCompletionStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var oauthCompletionWaiters: [CheckedContinuation<Void, Never>] = []
    private var shouldSuspendSync = false
    private var syncStarted = false
    private var syncStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var syncWaiters: [CheckedContinuation<Void, Never>] = []
    private var oauthInvocations: [OAuthUpgradeInvocation] = []
    private var shouldSuspendOAuthBegin = false
    private var oauthBeginStarted = false
    private var oauthBeginFinished = false
    private var oauthBeginStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var oauthBeginWaiters: [CheckedContinuation<Void, Never>] = []
    private var oauthBeginFinishWaiters: [CheckedContinuation<Void, Never>] = []
    private var oauthCancellations = 0
    private var logouts = 0
    private var roomCreationRequests: [MatrixRoomCreationRequest] = []
    private var roomInviteRequests: [MatrixRoomInviteRequest] = []
    private var userLookupRequests: [String] = []
    private var roomRemovalRequests: [String] = []
    private var sends: [String] = []
    private var shouldSuspendSend = false
    private var sendStarted = false
    private var sendStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var sendWaiters: [CheckedContinuation<Void, Never>] = []
    private var repositoryAttachment: MatrixRoomRepositoryAttachment?
    private var repositoryAttachmentWrites: [MatrixRoomRepositoryAttachment] = []
    private let trustState: MatrixDeviceTrustState
    private let peerVerificationEligibility: MatrixPeerVerificationEligibility
    private let peerVerificationEligibilityError: Error?
    private let bootstrapState: MatrixFirstDeviceTrustBootstrapState
    private let bootstrapContinuationState: MatrixFirstDeviceTrustBootstrapState
    private let verificationChallenge: MatrixVerificationChallenge
    private let recoveryState: MatrixRecoveryState
    private let createdRoom: MatrixRoomSummary?
    private let sessionHomeserverURL: String
    private let sessionUserID: String
    private let qrLoginUpdates: [MatrixQrLoginProgress]
    private let loginError: Error?
    private let sessionError: Error?
    private let syncError: Error?
    private let roomLoadError: Error?
    private let invitationError: Error?
    private let incomingVerificationHandlerError: Error?
    private let userLookupResult: MatrixUserLookupResult
    private var suspendBootstrap: Bool
    private var bootstrapWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        sessionHomeserverURL: String = "https://synapse.zenith-research.ca",
        sessionUserID: String = "@alice:example.org",
        qrLoginUpdates: [MatrixQrLoginProgress] = [],
        loginError: Error? = nil,
        sessionError: Error? = nil,
        syncError: Error? = nil,
        roomLoadError: Error? = nil,
        invitationError: Error? = nil,
        incomingVerificationHandlerError: Error? = nil,
        userLookupResult: MatrixUserLookupResult = .unavailable,
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
        self.sessionUserID = sessionUserID
        self.qrLoginUpdates = qrLoginUpdates
        self.loginError = loginError
        self.sessionError = sessionError
        self.syncError = syncError
        self.roomLoadError = roomLoadError
        self.invitationError = invitationError
        self.incomingVerificationHandlerError = incomingVerificationHandlerError
        self.userLookupResult = userLookupResult
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
    func setOAuthCompletionSession(_ value: MatrixSDKSessionRecord) {
        oauthCompletionSession = value
    }
    func setOAuthCompletionErrorAfterMutation(_ error: Error) {
        oauthCompletionErrorAfterMutation = error
    }
    func setRestoredSlidingSyncVersionOverride(_ value: String) {
        restoredSlidingSyncVersionOverride = value
    }
    func setOmitRestoredStoreNamespace(_ value: Bool) {
        omitRestoredStoreNamespace = value
    }
    func suspendOAuthCompletion() {
        shouldSuspendOAuthCompletion = true
    }
    func waitUntilOAuthCompletionStarted() async {
        if oauthCompletionStarted { return }
        await withCheckedContinuation { oauthCompletionStartWaiters.append($0) }
    }
    func resumeOAuthCompletion() {
        shouldSuspendOAuthCompletion = false
        let waiters = oauthCompletionWaiters
        oauthCompletionWaiters = []
        waiters.forEach { $0.resume() }
    }
    func suspendOAuthBegin() { shouldSuspendOAuthBegin = true }
    func waitUntilOAuthBeginStarted() async {
        if oauthBeginStarted { return }
        await withCheckedContinuation { oauthBeginStartWaiters.append($0) }
    }
    func resumeOAuthBegin() {
        shouldSuspendOAuthBegin = false
        let waiters = oauthBeginWaiters
        oauthBeginWaiters = []
        waiters.forEach { $0.resume() }
    }
    func waitUntilOAuthBeginFinished() async {
        if oauthBeginFinished { return }
        await withCheckedContinuation { oauthBeginFinishWaiters.append($0) }
    }
    func suspendSync() {
        shouldSuspendSync = true
    }
    func waitUntilSyncStarted() async {
        if syncStarted { return }
        await withCheckedContinuation { syncStartWaiters.append($0) }
    }
    func resumeSync() {
        shouldSuspendSync = false
        let waiters = syncWaiters
        syncWaiters = []
        waiters.forEach { $0.resume() }
    }
    func suspendSend() { shouldSuspendSend = true }
    func waitUntilSendStarted() async {
        if sendStarted { return }
        await withCheckedContinuation { sendStartWaiters.append($0) }
    }
    func resumeSend() {
        shouldSuspendSend = false
        let waiters = sendWaiters
        sendWaiters = []
        waiters.forEach { $0.resume() }
    }
    func login(username: String, password: String) async throws {
        if let loginError { throw loginError }
        logins += 1
    }
    func beginOAuthReauthorization(
        deviceID: String,
        loginHint: String,
        additionalScopes: [String]
    ) async throws -> URL {
        oauthInvocations.append(.init(
            deviceID: deviceID,
            loginHint: loginHint,
            additionalScopes: additionalScopes
        ))
        oauthBeginStarted = true
        let startWaiters = oauthBeginStartWaiters
        oauthBeginStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if shouldSuspendOAuthBegin {
            await withCheckedContinuation { oauthBeginWaiters.append($0) }
        }
        oauthBeginFinished = true
        let finishWaiters = oauthBeginFinishWaiters
        oauthBeginFinishWaiters = []
        finishWaiters.forEach { $0.resume() }
        return URL(string: "https://auth.example.org/authorize")!
    }
    func completeOAuthReauthorization(callbackURL: URL) async throws {
        currentSession = oauthCompletionSession
        oauthCompletionStarted = true
        let startWaiters = oauthCompletionStartWaiters
        oauthCompletionStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if shouldSuspendOAuthCompletion {
            await withCheckedContinuation { oauthCompletionWaiters.append($0) }
        }
        if let oauthCompletionErrorAfterMutation { throw oauthCompletionErrorAfterMutation }
    }
    func cancelOAuthReauthorization() async { oauthCancellations += 1 }
    func signInWithQrCode(
        _ qrCodeData: Data,
        progress: @escaping MatrixQrLoginProgressHandler
    ) async throws {
        qrLoginUpdates.forEach(progress)
    }
    func restore(session: MatrixSDKSessionRecord) async throws {
        restored.append(session)
        currentSession = MatrixSDKSessionRecord(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            userId: session.userId,
            deviceId: session.deviceId,
            homeserverURL: session.homeserverURL,
            oauthData: session.oauthData,
            slidingSyncVersion: restoredSlidingSyncVersionOverride ?? session.slidingSyncVersion,
            accountKey: session.accountKey,
            storeNamespace: omitRestoredStoreNamespace ? nil : session.storeNamespace
        )
    }
    func sessionRecord(accountKey: String) async throws -> MatrixSDKSessionRecord {
        if let sessionError { throw sessionError }
        if let currentSession { return currentSession }
        return .fixture(accountKey: accountKey, homeserverURL: sessionHomeserverURL, userID: sessionUserID)
    }
    func syncOnce() async throws {
        if let syncError { throw syncError }
        syncs += 1
        syncStarted = true
        let startWaiters = syncStartWaiters
        syncStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if shouldSuspendSync {
            await withCheckedContinuation { syncWaiters.append($0) }
        }
    }
    func startContinuousSync() async { continuousSyncStarts += 1 }
    func stopContinuousSync() async { continuousSyncStops += 1 }
    func joinedRooms() async throws -> [MatrixRoomSummary] {
        if let roomLoadError { throw roomLoadError }
        return rooms
    }
    func timeline(roomID: String) async throws -> [MatrixTimelineEvent] { [] }
    func sendText(_ body: String, roomID: String) async throws {
        sendStarted = true
        let startWaiters = sendStartWaiters
        sendStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if shouldSuspendSend {
            await withCheckedContinuation { sendWaiters.append($0) }
        }
        sends.append(body)
    }
    func roomRepositoryAttachment(roomID: String) async throws -> MatrixRoomRepositoryAttachment? {
        repositoryAttachment
    }
    func setRoomRepositoryAttachment(
        _ attachment: MatrixRoomRepositoryAttachment,
        roomID: String
    ) async throws {
        repositoryAttachment = attachment
        repositoryAttachmentWrites.append(attachment)
    }
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        roomCreationRequests.append(request)
        guard let createdRoom else {
            throw MatrixChatServiceError.unavailable(reason: "Room creation unavailable")
        }
        return createdRoom
    }
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult {
        userLookupRequests.append(userID)
        return userLookupResult
    }
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws {
        if let invitationError { throw invitationError }
        roomInviteRequests.append(request)
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
    func beginEncryptionIdentityReset() async throws -> MatrixRecoveryIdentityResetAuthorization {
        recoveryIdentityResetBegins += 1
        return .password
    }
    func continueEncryptionIdentityReset(password: String) async throws -> Bool {
        recoveryIdentityResetContinuations += 1
        return true
    }
    func continueEncryptionIdentityResetAfterOAuth() async throws {}
    func createReplacementEncryptionRecoveryKey() async throws -> String {
        replacementRecoveryKeys += 1
        return "not-a-real-replacement-key"
    }
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
    func setIncomingDeviceVerificationHandler(
        _ handler: (@Sendable (MatrixVerificationFlowState) -> Void)?
    ) async throws {
        if let incomingVerificationHandlerError { throw incomingVerificationHandlerError }
    }
    func approveDeviceVerification() async throws { verificationApprovals += 1 }
    func declineDeviceVerification() async { verificationDeclines += 1 }
    func logout() async throws { logouts += 1 }
    func loginCount() -> Int { logins }
    func restoredSessions() -> [MatrixSDKSessionRecord] { restored }
    func oauthUpgradeInvocations() -> [OAuthUpgradeInvocation] { oauthInvocations }
    func oauthCancellationCount() -> Int { oauthCancellations }
    func logoutCount() -> Int { logouts }
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
    func recoveryIdentityResetBeginCount() -> Int { recoveryIdentityResetBegins }
    func recoveryIdentityResetContinuationCount() -> Int { recoveryIdentityResetContinuations }
    func replacementRecoveryKeyCount() -> Int { replacementRecoveryKeys }
    func observedRecoveryKeys() -> [String] { recoveryKeys }
    func observedPasswordChange() -> PasswordChangeRequest? { passwordChange }
    func observedRoomCreationRequests() -> [MatrixRoomCreationRequest] { roomCreationRequests }
    func observedRoomInviteRequests() -> [MatrixRoomInviteRequest] { roomInviteRequests }
    func observedUserLookupRequests() -> [String] { userLookupRequests }
    func observedRoomRemovalRequests() -> [String] { roomRemovalRequests }
    func sentBodies() -> [String] { sends }
    func observedRepositoryAttachmentWrites() -> [MatrixRoomRepositoryAttachment] {
        repositoryAttachmentWrites
    }
}

private actor FakeMatrixAdminClient: MatrixAdminClient {
    private let administrator: Bool
    private let administratorError: MatrixAdminClientError?
    private var shouldSuspendAdministratorProbe: Bool
    private var administratorProbeStarted = false
    private var administratorProbeStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var administratorProbeWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        isAdministrator: Bool,
        administratorError: MatrixAdminClientError? = nil,
        suspendAdministratorProbe: Bool = false
    ) {
        self.administrator = isAdministrator
        self.administratorError = administratorError
        self.shouldSuspendAdministratorProbe = suspendAdministratorProbe
    }

    func isAdministrator() async throws -> Bool {
        administratorProbeStarted = true
        let startWaiters = administratorProbeStartWaiters
        administratorProbeStartWaiters = []
        startWaiters.forEach { $0.resume() }
        if shouldSuspendAdministratorProbe {
            await withCheckedContinuation { administratorProbeWaiters.append($0) }
        }
        if let administratorError { throw administratorError }
        return administrator
    }
    func waitUntilAdministratorProbeStarted() async {
        if administratorProbeStarted { return }
        await withCheckedContinuation { administratorProbeStartWaiters.append($0) }
    }
    func resumeAdministratorProbe() {
        shouldSuspendAdministratorProbe = false
        let waiters = administratorProbeWaiters
        administratorProbeWaiters = []
        waiters.forEach { $0.resume() }
    }
    func snapshot() async throws -> MatrixAdminSnapshot { .init(users: [], rooms: []) }
    func createAccount(localpart: String, temporaryPassword: String, administrator: Bool) async throws -> MatrixAdminUserSummary {
        .init(userID: "@\(localpart):example.org", isAdministrator: administrator, isDeactivated: false, isGuest: false, userType: nil)
    }
    func createRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary {
        .init(roomID: "!fixture:example.org", name: name, joinedMemberCount: 1)
    }
    func logoutAccount(userID: String) async throws {}
    func deactivateAccount(userID: String) async throws {}
    func purgeRoom(roomID: String) async throws {}
    func requestPasswordReset(requestID: String, requestedAtMilliseconds: Int64) async throws -> MatrixPasswordResetRequest {
        .init(userID: "@fixture:example.org", requestID: requestID, requestedAtMilliseconds: requestedAtMilliseconds)
    }
    func currentPasswordResetRequest() async throws -> MatrixPasswordResetRequest? { nil }
    func completePasswordResetRequest(completedAtMilliseconds: Int64) async throws {}
    func passwordResetRequests(users: [MatrixAdminUserSummary]) async throws -> [MatrixPasswordResetRequest] { [] }
    func resetPassword(for request: MatrixPasswordResetRequest, temporaryPassword: String) async throws {}
}

private actor FakeLiveClientFactory: MatrixLiveClientFactory {
    private let client: FakeLiveClient
    private var makes = 0
    private var resets: [String] = []
    private var storeKeys: [Data] = []
    private var qrNamespaces: [String] = []
    private let supportsQrLogin: Bool

    init(client: FakeLiveClient, qrLoginSupported: Bool = false) {
        self.client = client
        self.supportsQrLogin = qrLoginSupported
    }
    func make(accountKey: String, storeKey: Data) async throws -> any MatrixLiveClient {
        makes += 1
        storeKeys.append(storeKey)
        return client
    }
    func makeForQrLogin(
        qrCodeData: Data,
        storeNamespace: String,
        storeKey: Data
    ) async throws -> any MatrixLiveClient {
        makes += 1
        qrNamespaces.append(storeNamespace)
        storeKeys.append(storeKey)
        return client
    }
    func qrLoginSupported() async throws -> Bool { supportsQrLogin }
    func resetStore(accountKey: String) async throws { resets.append(accountKey) }
    func makeCount() -> Int { makes }
    func resetAccountKeys() -> [String] { resets }
    func madeStoreKeys() -> [Data] { storeKeys }
    func qrStoreNamespaces() -> [String] { qrNamespaces }
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
        refreshToken: String? = nil,
        homeserverURL: String = "https://synapse.zenith-research.ca",
        userID: String = "@alice:example.org",
        deviceID: String = "FIXTURE",
        oauthData: String? = nil,
        slidingSyncVersion: String = "native",
        storeNamespace: String? = nil
    ) -> Self {
        .init(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userID,
            deviceId: deviceID,
            homeserverURL: homeserverURL,
            oauthData: oauthData,
            slidingSyncVersion: slidingSyncVersion,
            accountKey: accountKey,
            storeNamespace: storeNamespace
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
