import Foundation
import XCTest
@testable import ZenithMacOSClientCore
import MatrixRustSDK

final class MatrixRustSDKCompatibilityTests: XCTestCase {
    func testExactSDKCanConstructFixedHomeserverBuilder() {
        let builder = ClientBuilder()
            .homeserverUrl(url: MatrixProductConfiguration.production.homeserver.absoluteString)
        XCTAssertNotNil(builder)
    }

    func testLiveFactoryAcceptsSDKCanonicalURLForSameHomeserver() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenith-matrix-factory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = MatrixProductConfiguration.production
        let factory = MatrixRustLiveClientFactory(
            configuration: configuration,
            rootDirectory: root
        )

        _ = try await factory.make(
            accountKey: "compatibility-fixture",
            storeKey: Data(repeating: 0x7A, count: 32)
        )
    }

    func testFactoryMigratesLegacyCryptoStoreDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenith-client-rename-\(UUID().uuidString)", isDirectory: true)
        let legacy = root.appendingPathComponent("legacy", isDirectory: true)
        let renamed = root.appendingPathComponent("renamed", isDirectory: true)
        let marker = legacy.appendingPathComponent("marker")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("preserved".utf8).write(to: marker)

        try MatrixRustLiveClientFactory.migrateLegacyRootIfNeeded(from: legacy, to: renamed)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("marker")), Data("preserved".utf8))
    }

    func testLiveAuthoritativeTrustMappingIsExplicit() {
        XCTAssertEqual(
            MatrixRustLiveClient.mapAuthoritativeDeviceVerificationState(.verifiedByCurrentSelfSigningKey),
            .verifiedByCurrentSelfSigningKey
        )
        XCTAssertEqual(MatrixRustLiveClient.mapAuthoritativeDeviceVerificationState(.unsigned), .unsigned)
        XCTAssertEqual(
            MatrixRustLiveClient.mapAuthoritativeDeviceVerificationState(.invalidSignature),
            .invalidSignature
        )
        XCTAssertEqual(MatrixRustLiveClient.mapAuthoritativeDeviceVerificationState(.unavailable), .unavailable)
    }

    func testLivePeerEligibilityUsesPinnedSDKAuthority() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("client.encryption().hasDevicesToVerifyAgainst()"))
        XCTAssertTrue(source.contains("? .eligiblePeer"))
        XCTAssertTrue(source.contains(": .noEligiblePeer"))
    }

    func testLiveRecoveryStateMappingUsesAuthoritativeTrust() {
        XCTAssertEqual(MatrixRustLiveClient.mapRecoveryState(.unknown, trustState: .unknown), .unknown)
        XCTAssertEqual(MatrixRustLiveClient.mapRecoveryState(.enabled, trustState: .unsigned), .available)
        XCTAssertEqual(
            MatrixRustLiveClient.mapRecoveryState(.enabled, trustState: .verifiedByCurrentSelfSigningKey),
            .ready
        )
        XCTAssertEqual(
            MatrixRustLiveClient.mapRecoveryState(.disabled, trustState: .verifiedByCurrentSelfSigningKey),
            .unavailable
        )
        XCTAssertEqual(
            MatrixRustLiveClient.mapRecoveryState(.incomplete, trustState: .verifiedByCurrentSelfSigningKey),
            .incomplete
        )
    }

    func testRecoveryUsesSDKBackupRepairPath() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("recover(recoveryKey: recoveryKey)"))
        XCTAssertTrue(source.contains("try await encryption.authoritativeDeviceVerificationState()"))
        XCTAssertTrue(source.contains("recoverAndFixBackup(recoveryKey: recoveryKey)"))
        XCTAssertTrue(source.contains("crossSigningStatus()"))
        XCTAssertTrue(source.contains("status.hasSelfSigningKey"))
        XCTAssertTrue(source.contains("let recoveryImportSucceeded"))
        XCTAssertTrue(source.contains("!recoveryImportSucceeded && !status.hasSelfSigningKey"))
        XCTAssertTrue(source.contains("diagnoseAndSignOwnDevice()"))
        XCTAssertFalse(source.contains("refreshVerificationState()"))
        XCTAssertTrue(source.contains("throw MatrixChatServiceError.recoveryRequired"))
        XCTAssertTrue(source.contains("await encryption.waitForE2eeInitializationTasks()"))
        XCTAssertFalse(source.contains("client.encryption().recover(recoveryKey: recoveryKey)"))
    }

    func testRestoredClientBindsKnownRoomTimelinesBeforeConsumingSyncEvents() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/ZenithMacOSClientCore/MatrixRustSDKChatService.swift"
            ),
            encoding: .utf8
        )
        let syncStart = try XCTUnwrap(source.range(of: "    public func syncOnce() async throws {"))
        let continuousStart = try XCTUnwrap(
            source.range(of: "    public func startContinuousSync()", range: syncStart.upperBound..<source.endIndex)
        )
        let syncSource = String(source[syncStart.lowerBound..<continuousStart.lowerBound])
        let bindingCall = try XCTUnwrap(syncSource.range(of: "prepareKnownRoomTimelinesForSync"))
        let syncCall = try XCTUnwrap(syncSource.range(of: "client.syncOnceV2"))
        XCTAssertLessThan(bindingCall.lowerBound, syncCall.lowerBound)
    }

    func testRemoteSendAcknowledgementRejectsLocalEchoesAndPreexistingEvents() {
        let preexisting = MatrixTimelineEvent(
            id: "$old",
            senderDisplayName: "Me",
            content: .text("same body"),
            isOwn: true
        )
        let localEcho = MatrixTimelineEvent(
            id: "txn-new",
            senderDisplayName: "Me",
            content: .text("same body"),
            isOwn: true
        )
        let remoteEcho = MatrixTimelineEvent(
            id: "$new",
            senderDisplayName: "Me",
            content: .text("same body"),
            isOwn: true
        )

        XCTAssertFalse(MatrixRustLiveClient.hasRemoteSendAcknowledgement(
            events: [preexisting, localEcho],
            baselineEventIDs: [preexisting.id],
            body: "same body"
        ))
        XCTAssertTrue(MatrixRustLiveClient.hasRemoteSendAcknowledgement(
            events: [preexisting, localEcho, remoteEcho],
            baselineEventIDs: [preexisting.id],
            body: "same body"
        ))
    }

    func testLiveTimelineMapperExposesDecryptedTextAndUnableToDecryptEvents() {
        let text = makeTimelineEvent(
            id: "$text",
            kind: .message(content: MessageContent(
                msgType: .text(content: TextMessageContent(body: "hello", formatted: nil)),
                body: "hello",
                isEdited: false,
                mentions: nil
            ))
        )
        let unableToDecrypt = makeTimelineEvent(
            id: "$utd",
            kind: .unableToDecrypt(msg: .unknown)
        )

        XCTAssertEqual(
            MatrixRustLiveClient.mapTimelineEvent(text),
            MatrixTimelineEvent(
                id: "$text",
                senderDisplayName: "Alice",
                senderID: "@alice:example.org",
                content: .text("hello"),
                timestamp: 1
            )
        )
        XCTAssertEqual(
            MatrixRustLiveClient.mapTimelineEvent(unableToDecrypt),
            MatrixTimelineEvent(
                id: "$utd",
                senderDisplayName: "Alice",
                senderID: "@alice:example.org",
                content: .undecryptable(reason: "Waiting for Matrix room keys"),
                timestamp: 1
            )
        )

        let unsignedOwnEvent = makeTimelineEvent(
            id: "$unsigned-own",
            kind: .message(content: MessageContent(
                msgType: .text(content: TextMessageContent(body: "new", formatted: nil)),
                body: "new",
                isEdited: false,
                mentions: nil
            )),
            isOwn: true,
            shield: .red(code: .unsignedDevice)
        )
        XCTAssertEqual(
            MatrixRustLiveClient.mapTimelineEvent(unsignedOwnEvent)?.authenticity,
            .unsignedDevice
        )
        XCTAssertEqual(MatrixRustLiveClient.mapTimelineEvent(unsignedOwnEvent)?.isOwn, true)
        XCTAssertEqual(MatrixRustLiveClient.mapTimelineEvent(unsignedOwnEvent)?.timestamp, 1)
    }

    private func makeTimelineEvent(
        id: String,
        kind: MsgLikeKind,
        isOwn: Bool = false,
        shield: ShieldState = .none
    ) -> EventTimelineItem {
        EventTimelineItem(
            isRemote: true,
            eventOrTransactionId: .eventId(eventId: id),
            sender: "@alice:example.org",
            senderProfile: .ready(
                displayName: "Alice",
                displayNameAmbiguous: false,
                avatarUrl: nil,
                status: nil,
                call: nil
            ),
            forwarder: nil,
            forwarderProfile: nil,
            isOwn: isOwn,
            isEditable: false,
            content: .msgLike(content: MsgLikeContent(
                kind: kind,
                reactions: [],
                inReplyTo: nil,
                threadRoot: nil,
                threadSummary: nil
            )),
            eventTypeRaw: "m.room.message",
            timestamp: 1,
            localSendState: nil,
            localCreatedAt: nil,
            readReceipts: [:],
            origin: nil,
            canBeRepliedTo: true,
            lazyProvider: StubLazyTimelineItemProvider(shield: shield)
        )
    }

    func testHomeserverMatchAcceptsOnlyCanonicalizationNotAuthorityChanges() {
        let configured = MatrixProductConfiguration.production.homeserver

        XCTAssertTrue(
            MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                "https://synapse.zenith-research.ca/",
                configured: configured
            )
        )
        XCTAssertFalse(
            MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                "https://attacker.example/",
                configured: configured
            )
        )
    }
}

private final class StubLazyTimelineItemProvider: LazyTimelineItemProvider, @unchecked Sendable {
    private let shield: ShieldState

    init(shield: ShieldState) {
        self.shield = shield
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        fatalError("StubLazyTimelineItemProvider does not accept FFI handles")
    }

    override func getShields(strict: Bool) -> ShieldState {
        shield
    }
}
