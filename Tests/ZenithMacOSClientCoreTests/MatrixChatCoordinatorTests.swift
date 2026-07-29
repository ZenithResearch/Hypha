import XCTest
@testable import ZenithMacOSClientCore

@MainActor
final class MatrixChatCoordinatorTests: XCTestCase {
    func testStartupRequiresAccountChoiceWhenMultipleSavedSessionsExist() {
        XCTAssertEqual(
            MatrixSessionStartupPolicy.decision(savedSessionCount: 2, hasActiveSession: true),
            .chooseAccount
        )
        XCTAssertEqual(
            MatrixSessionStartupPolicy.decision(savedSessionCount: 1, hasActiveSession: true),
            .restoreActive
        )
        XCTAssertEqual(
            MatrixSessionStartupPolicy.decision(savedSessionCount: 0, hasActiveSession: false),
            .signedOut
        )
    }
    func testStartsSignedOut() {
        let coordinator = MatrixChatCoordinator(service: FakeMatrixChatService())
        XCTAssertEqual(coordinator.state, .signedOut(message: nil))
    }

    func testRestoreTransitionsThroughRestoringToRooms() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let service = FakeMatrixChatService(restoredRooms: [room])
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .rooms([room]))
    }

    func testManualRoomRefreshReturnsNewInvitesAndUpdatesRoomState() async throws {
        let joined = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let invited = MatrixRoomSummary(id: "room-2", name: "Review", isEncrypted: true, hasInvite: true)
        let service = FakeMatrixChatService(restoredRooms: [joined])
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()
        service.refreshedRooms = [joined, invited]

        let refreshed = try await coordinator.refreshRooms()

        XCTAssertEqual(refreshed, [joined, invited])
        XCTAssertEqual(coordinator.state, .rooms([joined, invited]))
        XCTAssertEqual(service.roomRefreshRequests, 1)
    }

    func testInvalidCredentialsRemainVisibleWithoutBecomingSessionExpiry() async {
        let service = FakeMatrixChatService(signInError: .invalidCredentials)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(coordinator.state, .signedOut(message: .invalidCredentials))
    }

    func testSignInLoadsAuthoritativeDeviceTrustState() async {
        let service = FakeMatrixChatService(trustState: .unsigned)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(coordinator.trustState, .unsigned)
        XCTAssertEqual(coordinator.verificationFlowState, .idle)
    }

    func testFirstClientBootstrapsWithoutRequestingSAS() async {
        let service = FakeMatrixChatService(
            trustState: .unsigned,
            bootstrapResult: .verifiedByCurrentSelfSigningKey
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .notBootstrapped)
        await coordinator.bootstrapFirstDeviceTrust()

        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(coordinator.trustState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(service.bootstrapRequests, 1)
        XCTAssertEqual(service.verificationRequests, 0)
    }

    func testBootstrapFailureRemainsTypedAndDoesNotTrustCachedState() async {
        let service = FakeMatrixChatService(
            trustState: .verifiedByCurrentSelfSigningKey,
            bootstrapResult: .unavailable
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.bootstrapFirstDeviceTrust()

        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .unavailable)
        XCTAssertEqual(coordinator.trustState, .unavailable)
    }

    func testBootstrapInvalidSignatureFailsClosed() async {
        let service = FakeMatrixChatService(
            trustState: .unsigned,
            bootstrapResult: .invalidSignature
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.bootstrapFirstDeviceTrust()

        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .invalidSignature)
        XCTAssertEqual(coordinator.trustState, .invalidSignature)
    }

    func testBootstrapPasswordContinuationDoesNotUsePeerVerification() async {
        let service = FakeMatrixChatService(
            trustState: .unsigned,
            bootstrapResult: .passwordRequired,
            bootstrapContinuationResult: .verifiedByCurrentSelfSigningKey
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.bootstrapFirstDeviceTrust()
        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .passwordRequired)
        XCTAssertEqual(coordinator.trustState, .unsigned)

        await coordinator.continueFirstDeviceTrust(password: "not-recorded")

        XCTAssertEqual(coordinator.firstDeviceTrustBootstrapState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(coordinator.trustState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(service.bootstrapContinuationRequests, 1)
        XCTAssertEqual(service.verificationRequests, 0)
    }

    func testSecurityGuidanceSnapshotDoesNotBecomeChatAuthority() async {
        let service = FakeMatrixChatService(trustState: .unsigned, recoveryState: .incomplete)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(
            coordinator.securityGuidance,
            MatrixSecurityGuidance(
                trustState: .unsigned,
                verificationFlowState: .idle,
                recoveryState: .incomplete
            )
        )
        XCTAssertEqual(coordinator.chatAuthority, .available)
    }

    func testDeviceVerificationPublishesSASChallengeAndRefreshesTrustAfterApproval() async {
        let challenge = MatrixVerificationChallenge.emojis([
            MatrixVerificationEmoji(symbol: "🐶", description: "Dog"),
            MatrixVerificationEmoji(symbol: "🌙", description: "Moon")
        ])
        let service = FakeMatrixChatService(
            trustState: .unsigned,
            trustStateAfterApproval: .verifiedByCurrentSelfSigningKey,
            verificationChallenge: challenge,
            recoveryState: .available,
            recoveryStateAfterApproval: .ready
        )
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.requestDeviceVerification()
        XCTAssertEqual(coordinator.verificationFlowState, .challenge(challenge))
        XCTAssertEqual(coordinator.trustState, .unsigned)

        await coordinator.approveDeviceVerification()
        XCTAssertEqual(coordinator.verificationFlowState, .idle)
        XCTAssertEqual(coordinator.trustState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(coordinator.recoveryState, .ready)
        XCTAssertEqual(service.verificationApprovals, 1)
    }

    func testSASCompletionDoesNotDeclareVerificationWithoutServerEvidence() async {
        let service = FakeMatrixChatService(trustState: .unsigned, trustStateAfterApproval: .unsigned)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.requestDeviceVerification()
        await coordinator.approveDeviceVerification()

        XCTAssertEqual(coordinator.verificationFlowState, .idle)
        XCTAssertEqual(coordinator.trustState, .unsigned)
    }

    func testDeviceVerificationFailureIsExplicitWithoutLeakingSDKDetails() async {
        let service = FakeMatrixChatService(
            trustState: .unsigned,
            verificationRequestError: .unavailable(reason: "secret-sdk-detail")
        )
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.requestDeviceVerification()

        XCTAssertEqual(coordinator.verificationFlowState, .failed(reason: "Device verification failed"))
        XCTAssertEqual(coordinator.trustState, .unsigned)
    }

    func testDeviceVerificationDeclineCancelsChallengeWithoutRewritingTrust() async {
        let challenge = MatrixVerificationChallenge.decimals([111, 222, 333])
        let service = FakeMatrixChatService(trustState: .unsigned, verificationChallenge: challenge)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.requestDeviceVerification()
        await coordinator.declineDeviceVerification()

        XCTAssertEqual(coordinator.verificationFlowState, .idle)
        XCTAssertEqual(coordinator.trustState, .unsigned)
        XCTAssertEqual(service.verificationDeclines, 1)
    }

    func testManualTrustRefreshAlsoRefreshesRecoveryFromSameAuthority() async {
        let service = FakeMatrixChatService(trustState: .unsigned, recoveryState: .available)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        service.trustState = .verifiedByCurrentSelfSigningKey
        service.recoveryState = .ready
        await coordinator.refreshTrustState()

        XCTAssertEqual(coordinator.trustState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(coordinator.recoveryState, .ready)
    }

    func testRecoveryReadyCannotContradictUnsignedAuthoritativeTrust() async {
        let service = FakeMatrixChatService(trustState: .unsigned, recoveryState: .ready)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(coordinator.trustState, .unsigned)
        XCTAssertEqual(coordinator.recoveryState, .available)
    }

    func testRecoveryRestoresIdentityAndBackupUsingProvidedKey() async {
        let service = FakeMatrixChatService(recoveryState: .available)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        XCTAssertEqual(coordinator.recoveryState, .available)
        await coordinator.restoreEncryption(recoveryKey: "not-a-real-recovery-key")

        XCTAssertEqual(coordinator.recoveryState, .ready)
        XCTAssertEqual(coordinator.trustState, .verifiedByCurrentSelfSigningKey)
        XCTAssertEqual(service.recoveryKeys, ["not-a-real-recovery-key"])
    }

    func testRecoveryTrimsAccidentalClipboardWhitespaceBeforeSDKImport() async {
        let service = FakeMatrixChatService(recoveryState: .available)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.restoreEncryption(recoveryKey: "  not-a-real-recovery-key\n")

        XCTAssertEqual(coordinator.recoveryState, .ready)
        XCTAssertEqual(service.recoveryKeys, ["not-a-real-recovery-key"])
    }

    func testRecoveryReportsSafeFailureStageWithoutSDKOrKeyDetails() async {
        let cases: [(MatrixRecoveryFailureStage, String)] = [
            (.identityRefresh, "Current cross-signing identity could not be refreshed"),
            (.secretStorageUnlock, "Secret Storage recovery did not complete"),
            (.selfSigningKeyImport, "Secret Storage opened, but the self-signing key is unavailable"),
            (.deviceSignatureUpload, "Self-signing key imported, but device signature upload failed"),
            (.serverConfirmation, "Device signature was not confirmed by the homeserver"),
            (.backupRepair, "Device verified, but room-key backup repair did not complete")
        ]

        for (stage, expected) in cases {
            let service = FakeMatrixChatService(
                recoveryState: .available,
                recoveryRestoreError: .recoveryFailed(stage: stage)
            )
            let coordinator = MatrixChatCoordinator(service: service)
            await coordinator.signIn(username: "alice", password: "not-recorded")

            await coordinator.restoreEncryption(recoveryKey: "not-a-real-recovery-key")

            XCTAssertEqual(coordinator.recoveryState, .failed(reason: expected))
        }
    }

    func testDiagnosticReceiptSelectsTransportFailureBeforeServerProcessing() {
        let receipt = MatrixCrossSigningDiagnosticReceipt(
            publicIdentityRefreshed: true,
            privateSelfSigningKeyPresent: true,
            privateSelfSigningKeyMatchesCurrentPublicIdentity: true,
            localOwnDeviceKeyMatchesServerDeviceKey: true,
            signedObjectMatchesFreshServerDeviceObject: true,
            generatedSignatureValidLocally: true,
            uploadTransport: .failed,
            uploadProcessing: .otherFailure,
            postUploadServerSignaturePresent: false,
            backupRepair: .notAttempted
        )

        XCTAssertEqual(receipt.stableCode, "SIG-T0")
    }

    func testDiagnosticReceiptSelectsDeviceMismatchBeforeUploadFailure() {
        let receipt = MatrixCrossSigningDiagnosticReceipt(
            publicIdentityRefreshed: true,
            privateSelfSigningKeyPresent: true,
            privateSelfSigningKeyMatchesCurrentPublicIdentity: true,
            localOwnDeviceKeyMatchesServerDeviceKey: false,
            signedObjectMatchesFreshServerDeviceObject: true,
            generatedSignatureValidLocally: true,
            uploadTransport: .accepted,
            uploadProcessing: .invalidSignature,
            postUploadServerSignaturePresent: false,
            backupRepair: .notAttempted
        )

        XCTAssertEqual(receipt.stableCode, "SIG-D2")
    }

    func testRecoverySetupReturnsGeneratedKeyAndMarksLocalIdentityReady() async {
        let service = FakeMatrixChatService(
            recoveryState: .unavailable,
            generatedRecoveryKey: "not-a-real-generated-key"
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        let recoveryKey = await coordinator.setupEncryptionRecovery()

        XCTAssertEqual(recoveryKey, "not-a-real-generated-key")
        XCTAssertEqual(coordinator.recoveryState, .ready)
        XCTAssertEqual(service.recoverySetupCount, 1)
    }

    func testRemovingCreatorOwnedRoomReturnsCoordinatorToRemainingRooms() async {
        let ownedRoom = MatrixRoomSummary(
            id: "!owned:example.org",
            name: "Old room",
            isEncrypted: true,
            hasInvite: false,
            isCreatedByCurrentUser: true
        )
        let service = FakeMatrixChatService(restoredRooms: [ownedRoom])
        service.roomsAfterRemoval = []
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()

        await coordinator.removeRoom(ownedRoom)

        XCTAssertEqual(coordinator.state, .rooms([]))
        XCTAssertEqual(service.roomRemovalRequests, [ownedRoom.id])
    }

    func testFailedRoomRemovalPreservesTheCurrentRoomList() async {
        let ownedRoom = MatrixRoomSummary(
            id: "!owned:example.org",
            name: "Old room",
            isEncrypted: true,
            hasInvite: false,
            isCreatedByCurrentUser: true
        )
        let service = FakeMatrixChatService(restoredRooms: [ownedRoom])
        service.roomRemovalError = .offline
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()

        let removed = await coordinator.removeRoom(ownedRoom)

        XCTAssertFalse(removed)
        XCTAssertEqual(coordinator.state, .rooms([ownedRoom]))
    }

    func testCreateEncryptedPrivateRoomUsesServerConfirmedRoomAndOpensTimeline() async {
        let createdRoom = MatrixRoomSummary(
            id: "!created:example.org",
            name: "Private planning",
            isEncrypted: true,
            hasInvite: false
        )
        let event = MatrixTimelineEvent(id: "$server", senderDisplayName: "Alice", content: .text("ready"))
        let service = FakeMatrixChatService(events: [event], createdRoom: createdRoom)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.createEncryptedRoom(
            MatrixRoomCreationRequest(
                name: "Private planning",
                topic: "Launch",
                invitees: ["@bob:example.org"]
            )
        )

        XCTAssertEqual(service.roomCreationRequests, [
            MatrixRoomCreationRequest(
                name: "Private planning",
                topic: "Launch",
                invitees: ["@bob:example.org"]
            )
        ])
        XCTAssertEqual(
            coordinator.state,
            .thread(room: createdRoom, events: [event], composer: .ready)
        )
    }

    func testUnsignedOrUnavailableTrustAndIncompleteRecoveryDoNotBlockCurrentEncryptedChat() async {
        let trustStates: [MatrixDeviceTrustState] = [.unsigned, .unavailable]
        let recoveryStates: [MatrixRecoveryState] = [.unavailable, .available, .incomplete]

        for trustState in trustStates {
            for recoveryState in recoveryStates {
                let room = MatrixRoomSummary(
                    id: "!current:example.org",
                    name: "Current encrypted chat",
                    isEncrypted: true,
                    hasInvite: false
                )
                let delivered = MatrixTimelineEvent(
                    id: "$delivered",
                    senderDisplayName: "You",
                    content: .text("hello")
                )
                let service = FakeMatrixChatService(
                    eventsAfterSend: [delivered],
                    trustState: trustState,
                    recoveryState: recoveryState,
                    createdRoom: room
                )
                let coordinator = MatrixChatCoordinator(service: service)

                await coordinator.signIn(username: "alice", password: "not-recorded")
                await coordinator.createEncryptedRoom(MatrixRoomCreationRequest(name: room.name))
                await coordinator.send("hello")

                XCTAssertEqual(
                    service.roomCreationRequests,
                    [MatrixRoomCreationRequest(name: room.name)],
                    "Room creation must remain available for \(trustState) / \(recoveryState)"
                )
                XCTAssertEqual(
                    service.sentBodies,
                    ["hello"],
                    "Current encrypted send must remain available for \(trustState) / \(recoveryState)"
                )
                XCTAssertEqual(
                    coordinator.state,
                    .thread(room: room, events: [delivered], composer: .ready)
                )
            }
        }
    }

    func testInvalidSignatureBlocksRoomCreationBeforeServiceMutation() async {
        let service = FakeMatrixChatService(
            trustState: .invalidSignature,
            recoveryState: .incomplete
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")

        await coordinator.createEncryptedRoom(MatrixRoomCreationRequest(name: "Blocked"))

        XCTAssertEqual(service.roomCreationRequests, [])
        XCTAssertEqual(coordinator.state, .unavailable(reason: "Device trust requires review"))
    }

    func testInvalidSignatureBlocksSendBeforeServiceMutation() async {
        let room = MatrixRoomSummary(id: "!secure:example.org", name: "Secure", isEncrypted: true, hasInvite: false)
        let service = FakeMatrixChatService(
            restoredRooms: [room],
            trustState: .invalidSignature,
            recoveryState: .incomplete
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.open(room: room)

        await coordinator.send("blocked")

        XCTAssertEqual(service.sentBodies, [])
        XCTAssertEqual(coordinator.state, .trustBlocked(room: room))
    }

    func testFailedTrustRefreshCannotDowngradeProvenInvalidSignature() async {
        let service = FakeMatrixChatService(
            trustState: .invalidSignature,
            recoveryState: .incomplete
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")
        XCTAssertEqual(coordinator.trustState, .invalidSignature)

        service.trustStateError = .offline
        await coordinator.refreshTrustState()
        await coordinator.createEncryptedRoom(MatrixRoomCreationRequest(name: "Still blocked"))

        XCTAssertEqual(coordinator.trustState, .invalidSignature)
        XCTAssertEqual(coordinator.chatAuthority, .blockedByProvenIdentityViolation)
        XCTAssertEqual(service.roomCreationRequests, [])
        XCTAssertEqual(coordinator.state, .unavailable(reason: "Device trust requires review"))
    }

    func testUnresolvedTrustRefreshCannotDowngradeProvenInvalidSignature() async {
        for unresolvedState in [MatrixDeviceTrustState.unknown, .unavailable] {
            let service = FakeMatrixChatService(
                trustState: .invalidSignature,
                recoveryState: .incomplete
            )
            let coordinator = MatrixChatCoordinator(service: service)
            await coordinator.signIn(username: "alice", password: "not-recorded")

            service.trustState = unresolvedState
            await coordinator.refreshTrustState()
            await coordinator.createEncryptedRoom(MatrixRoomCreationRequest(name: "Still blocked"))

            XCTAssertEqual(coordinator.trustState, .invalidSignature)
            XCTAssertEqual(coordinator.chatAuthority, .blockedByProvenIdentityViolation)
            XCTAssertEqual(service.roomCreationRequests, [])
        }
    }

    func testResolvedTrustRefreshCanClearProvenInvalidSignature() async {
        for resolvedState in [
            MatrixDeviceTrustState.unsigned,
            .verifiedByCurrentSelfSigningKey,
        ] {
            let service = FakeMatrixChatService(
                trustState: .invalidSignature,
                recoveryState: .incomplete
            )
            let coordinator = MatrixChatCoordinator(service: service)
            await coordinator.signIn(username: "alice", password: "not-recorded")

            service.trustState = resolvedState
            await coordinator.refreshTrustState()

            XCTAssertEqual(coordinator.trustState, resolvedState)
            XCTAssertEqual(coordinator.chatAuthority, .available)
        }
    }

    func testUnencryptedRoomCannotSendEvenWhenSecurityGuidanceIsIncomplete() async {
        let room = MatrixRoomSummary(id: "!plain:example.org", name: "Plain", isEncrypted: false, hasInvite: false)
        let service = FakeMatrixChatService(
            restoredRooms: [room],
            trustState: .unsigned,
            recoveryState: .incomplete
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.signIn(username: "alice", password: "not-recorded")
        await coordinator.open(room: room)

        await coordinator.send("must not downgrade")

        XCTAssertEqual(service.sentBodies, [])
        XCTAssertEqual(
            coordinator.state,
            .thread(room: room, events: [], composer: .disabled(reason: "Encrypted rooms only"))
        )
    }

    func testSessionExpiryClearsRoomState() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let service = FakeMatrixChatService(restoredRooms: [room], roomError: .sessionExpired)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()

        await coordinator.open(room: room)

        XCTAssertEqual(coordinator.state, .sessionExpired)
    }

    func testUndecryptableEventsRemainExplicit() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let event = MatrixTimelineEvent(
            id: "event-1",
            senderDisplayName: "Peer",
            content: .undecryptable(reason: "Waiting for room keys")
        )
        let service = FakeMatrixChatService(restoredRooms: [room], events: [event])
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()

        await coordinator.open(room: room)

        XCTAssertEqual(coordinator.state, .thread(room: room, events: [event], composer: .ready))
    }

    func testRefreshOpenRoomAppliesLatestLiveSDKSnapshot() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let initial = MatrixTimelineEvent(id: "$1", senderDisplayName: "Alice", content: .text("first"))
        let latest = MatrixTimelineEvent(id: "$2", senderDisplayName: "Bob", content: .text("latest"))
        let service = FakeMatrixChatService(restoredRooms: [room], events: [initial])
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()
        await coordinator.open(room: room)
        service.events = [initial, latest]

        await coordinator.refreshOpenRoom()

        XCTAssertEqual(coordinator.state, .thread(room: room, events: [initial, latest], composer: .ready))
    }

    func testSendReloadsSDKTimelineInsteadOfCreatingSyntheticEcho() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let delivered = MatrixTimelineEvent(id: "$server", senderDisplayName: "You", content: .text("hello"))
        let service = FakeMatrixChatService(restoredRooms: [room], eventsAfterSend: [delivered])
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()
        await coordinator.open(room: room)

        let sent = await coordinator.send("hello")

        XCTAssertTrue(sent)
        XCTAssertEqual(coordinator.state, .thread(room: room, events: [delivered], composer: .ready))
    }

    func testOrdinarySendFailurePreservesConversationContextForRetry() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let existing = MatrixTimelineEvent(id: "$existing", senderDisplayName: "Alice", content: .text("Earlier"))
        let service = FakeMatrixChatService(
            restoredRooms: [room],
            events: [existing],
            sendError: .offline
        )
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()
        await coordinator.open(room: room)

        let sent = await coordinator.send("retry me")

        XCTAssertFalse(sent)
        XCTAssertEqual(
            coordinator.state,
            .thread(room: room, events: [existing], composer: .ready)
        )
        XCTAssertEqual(service.sentBodies, ["retry me"])
    }

    func testTrustViolationBlocksSendWithoutPlaintextFallback() async {
        let room = MatrixRoomSummary(id: "room-1", name: "Design", isEncrypted: true, hasInvite: false)
        let service = FakeMatrixChatService(restoredRooms: [room], sendError: .trustViolation)
        let coordinator = MatrixChatCoordinator(service: service)
        await coordinator.restore()
        await coordinator.open(room: room)

        let sent = await coordinator.send("hello")

        XCTAssertFalse(sent)
        XCTAssertEqual(coordinator.state, .trustBlocked(room: room))
        XCTAssertEqual(service.sentBodies, ["hello"])
    }

    func testNoSavedSessionReturnsToNormalSignedOutState() async {
        let service = FakeMatrixChatService(restoreError: .noSavedSession)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .signedOut(message: nil))
    }

    func testMissingCryptoStoreRequiresRecovery() async {
        let service = FakeMatrixChatService(restoreError: .recoveryRequired)
        let coordinator = MatrixChatCoordinator(service: service)

        await coordinator.restore()

        XCTAssertEqual(coordinator.state, .recoveryRequired)
    }
}

private final class FakeMatrixChatService: MatrixChatService, @unchecked Sendable {
    var restoredRooms: [MatrixRoomSummary]
    var refreshedRooms: [MatrixRoomSummary]?
    var events: [MatrixTimelineEvent]
    var eventsAfterSend: [MatrixTimelineEvent]?
    var restoreError: MatrixChatServiceError?
    var signInError: MatrixChatServiceError?
    var roomError: MatrixChatServiceError?
    var sendError: MatrixChatServiceError?
    var trustState: MatrixDeviceTrustState
    var trustStateError: MatrixChatServiceError?
    var bootstrapResult: MatrixFirstDeviceTrustBootstrapState
    var bootstrapContinuationResult: MatrixFirstDeviceTrustBootstrapState
    var trustStateAfterApproval: MatrixDeviceTrustState?
    var verificationChallenge: MatrixVerificationChallenge
    var verificationRequestError: MatrixChatServiceError?
    var recoveryState: MatrixRecoveryState
    var recoveryStateAfterApproval: MatrixRecoveryState?
    var generatedRecoveryKey: String
    var recoveryRestoreError: MatrixChatServiceError?
    var createdRoom: MatrixRoomSummary?
    var roomCreationError: MatrixChatServiceError?
    var roomsAfterRemoval: [MatrixRoomSummary]?
    var roomRemovalError: MatrixChatServiceError?
    var verificationApprovals = 0
    var verificationDeclines = 0
    var verificationRequests = 0
    var bootstrapRequests = 0
    var bootstrapContinuationRequests = 0
    var recoverySetupCount = 0
    var recoveryKeys: [String] = []
    var roomCreationRequests: [MatrixRoomCreationRequest] = []
    var roomRemovalRequests: [String] = []
    var sentBodies: [String] = []
    var roomRefreshRequests = 0

    init(
        restoredRooms: [MatrixRoomSummary] = [],
        events: [MatrixTimelineEvent] = [],
        eventsAfterSend: [MatrixTimelineEvent]? = nil,
        restoreError: MatrixChatServiceError? = nil,
        signInError: MatrixChatServiceError? = nil,
        roomError: MatrixChatServiceError? = nil,
        sendError: MatrixChatServiceError? = nil,
        trustState: MatrixDeviceTrustState = .unknown,
        trustStateError: MatrixChatServiceError? = nil,
        bootstrapResult: MatrixFirstDeviceTrustBootstrapState = .unavailable,
        bootstrapContinuationResult: MatrixFirstDeviceTrustBootstrapState = .unavailable,
        trustStateAfterApproval: MatrixDeviceTrustState? = nil,
        verificationChallenge: MatrixVerificationChallenge = .decimals([111, 222, 333]),
        verificationRequestError: MatrixChatServiceError? = nil,
        recoveryState: MatrixRecoveryState = .unknown,
        recoveryStateAfterApproval: MatrixRecoveryState? = nil,
        generatedRecoveryKey: String = "not-a-real-generated-key",
        recoveryRestoreError: MatrixChatServiceError? = nil,
        createdRoom: MatrixRoomSummary? = nil,
        roomCreationError: MatrixChatServiceError? = nil
    ) {
        self.restoredRooms = restoredRooms
        self.events = events
        self.eventsAfterSend = eventsAfterSend
        self.restoreError = restoreError
        self.signInError = signInError
        self.roomError = roomError
        self.sendError = sendError
        self.trustState = trustState
        self.trustStateError = trustStateError
        self.bootstrapResult = bootstrapResult
        self.bootstrapContinuationResult = bootstrapContinuationResult
        self.trustStateAfterApproval = trustStateAfterApproval
        self.verificationChallenge = verificationChallenge
        self.verificationRequestError = verificationRequestError
        self.recoveryState = recoveryState
        self.recoveryStateAfterApproval = recoveryStateAfterApproval
        self.generatedRecoveryKey = generatedRecoveryKey
        self.recoveryRestoreError = recoveryRestoreError
        self.createdRoom = createdRoom
        self.roomCreationError = roomCreationError
    }

    func restore() async throws -> [MatrixRoomSummary] {
        if let restoreError { throw restoreError }
        return restoredRooms
    }

    func signIn(username: String, password: String) async throws -> [MatrixRoomSummary] {
        if let signInError { throw signInError }
        return restoredRooms
    }

    func refreshRooms() async throws -> [MatrixRoomSummary] {
        roomRefreshRequests += 1
        return refreshedRooms ?? restoredRooms
    }

    func timeline(for roomID: String) async throws -> [MatrixTimelineEvent] {
        if let roomError { throw roomError }
        return events
    }

    func sendText(_ body: String, to roomID: String) async throws {
        sentBodies.append(body)
        if let sendError { throw sendError }
        if let eventsAfterSend { events = eventsAfterSend }
    }

    func deviceTrustState() async throws -> MatrixDeviceTrustState {
        if let trustStateError { throw trustStateError }
        return trustState
    }

    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        bootstrapRequests += 1
        return bootstrapResult
    }

    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState {
        bootstrapContinuationRequests += 1
        return bootstrapContinuationResult
    }

    func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        verificationRequests += 1
        if let verificationRequestError { throw verificationRequestError }
        return verificationChallenge
    }
    func approveDeviceVerification() async throws {
        verificationApprovals += 1
        if let trustStateAfterApproval { trustState = trustStateAfterApproval }
        if let recoveryStateAfterApproval { recoveryState = recoveryStateAfterApproval }
    }
    func declineDeviceVerification() async {
        verificationDeclines += 1
    }

    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState {
        recoveryState == .ready && trustState != .verifiedByCurrentSelfSigningKey ? .available : recoveryState
    }

    func restoreEncryption(recoveryKey: String) async throws {
        recoveryKeys.append(recoveryKey)
        if let recoveryRestoreError { throw recoveryRestoreError }
        trustState = .verifiedByCurrentSelfSigningKey
        recoveryState = .ready
    }

    func setupEncryptionRecovery() async throws -> String {
        recoverySetupCount += 1
        trustState = .verifiedByCurrentSelfSigningKey
        recoveryState = .ready
        return generatedRecoveryKey
    }

    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        roomCreationRequests.append(request)
        if let roomCreationError { throw roomCreationError }
        guard let createdRoom else {
            throw MatrixChatServiceError.unavailable(reason: "Room creation unavailable")
        }
        return createdRoom
    }

    func removeRoom(roomID: String) async throws -> [MatrixRoomSummary] {
        roomRemovalRequests.append(roomID)
        if let roomRemovalError { throw roomRemovalError }
        return roomsAfterRemoval ?? restoredRooms.filter { $0.id != roomID }
    }

    func logout() async throws {}
}
