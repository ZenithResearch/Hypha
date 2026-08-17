import XCTest
@testable import HyphaCore

final class MatrixLiveSessionSmokeTests: XCTestCase {
    func testSavedProductionSessionRestoresRoomsAndOpensEncryptedTimeline() async throws {
        guard ProcessInfo.processInfo.environment["ZENITH_MATRIX_LIVE_SESSION"] == "1" else {
            throw XCTSkip("Set ZENITH_MATRIX_LIVE_SESSION=1 to exercise the Keychain-backed production session")
        }

        let configuration = MatrixProductConfiguration.production
        mark("live-smoke: constructing production service")
        let service = MatrixRustSDKChatService(
            configuration: configuration,
            vault: MatrixKeychainSessionVault(),
            clientFactory: MatrixRustLiveClientFactory(configuration: configuration)
        )

        mark("live-smoke: restoring saved session")
        let rooms = try await service.restore()
        mark("live-smoke: restored \(rooms.count) joined room(s)")
        XCTAssertFalse(rooms.isEmpty, "The saved production session should expose joined rooms")
        let trustState = try await service.deviceTrustState()
        XCTAssertNotEqual(trustState, .unknown, "Production device trust state should resolve after sync")
        mark("live-smoke: authoritative device trust state resolved")

        let encryptedRooms = rooms.filter(\.isEncrypted)
        guard !encryptedRooms.isEmpty else {
            return XCTFail("The saved production session has no joined encrypted room")
        }

        mark("live-smoke: opening encrypted timelines")
        var roomWithDecryptedText: MatrixRoomSummary?
        var decryptedTextCount = 0
        var totalEventCount = 0
        var ownAuthenticityCounts: [MatrixEventAuthenticity: Int] = [:]
        var latestOwnEvent: MatrixTimelineEvent?
        for room in encryptedRooms {
            let events = try await service.timeline(for: room.id)
            totalEventCount += events.count
            for event in events where event.isOwn {
                ownAuthenticityCounts[event.authenticity, default: 0] += 1
                if event.timestamp > (latestOwnEvent?.timestamp ?? 0) {
                    latestOwnEvent = event
                }
            }
            let roomDecryptedTextCount = events.reduce(into: 0) { count, event in
                if case .text = event.content { count += 1 }
            }
            if roomDecryptedTextCount > 0 {
                roomWithDecryptedText = room
                decryptedTextCount = roomDecryptedTextCount
                break
            }
        }
        mark("live-smoke: encrypted timelines opened with \(totalEventCount) event(s), \(decryptedTextCount) decrypted text event(s)")
        for (authenticity, count) in ownAuthenticityCounts.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
            mark("live-smoke: own event authenticity \(authenticity)=\(count)")
        }
        if let latestOwnEvent {
            mark("live-smoke: latest own event authenticity \(latestOwnEvent.authenticity)")
        }
        XCTAssertGreaterThan(decryptedTextCount, 0, "Expected at least one decrypted text event in the production encrypted room")

        if ProcessInfo.processInfo.environment["ZENITH_MATRIX_LIVE_SEND"] == "1" {
            guard let encryptedRoom = roomWithDecryptedText else {
                return XCTFail("No encrypted room was selected for the live send")
            }
            let body = "Zenith Matrix Rust SDK live send verification \(UUID().uuidString)"
            mark("live-smoke: sending encrypted text")
            try await service.sendText(body, to: encryptedRoom.id)

            var acknowledged = false
            for _ in 0..<20 where !acknowledged {
                try await Task<Never, Never>.sleep(for: .milliseconds(500))
                let refreshed = try await service.timeline(for: encryptedRoom.id)
                acknowledged = refreshed.contains { event in
                    guard case let .text(value) = event.content else { return false }
                    return value == body && !event.id.hasPrefix("txn-")
                }
            }
            XCTAssertTrue(acknowledged, "Encrypted Matrix send did not receive a remote event id")
            mark("live-smoke: encrypted text acknowledged by the homeserver")
        }
    }

    func testLiveEncryptedRoomSharesKeysWithNewlyJoinedPeer() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["HYPHA_MATRIX_LIVE_CROSS_ACCOUNT"] == "1" else {
            throw XCTSkip("Set HYPHA_MATRIX_LIVE_CROSS_ACCOUNT=1 with disposable production credentials")
        }
        guard let senderUsername = environment["HYPHA_MATRIX_LIVE_SENDER_USERNAME"],
              let senderPassword = environment["HYPHA_MATRIX_LIVE_SENDER_PASSWORD"],
              let receiverUsername = environment["HYPHA_MATRIX_LIVE_RECEIVER_USERNAME"],
              let receiverPassword = environment["HYPHA_MATRIX_LIVE_RECEIVER_PASSWORD"] else {
            throw XCTSkip("Disposable sender and receiver credentials are required")
        }

        let configuration = MatrixProductConfiguration.production
        let senderRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-live-sender-\(UUID().uuidString)", isDirectory: true)
        let receiverRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-live-receiver-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: senderRoot)
            try? FileManager.default.removeItem(at: receiverRoot)
        }

        let senderVault = LiveRegistrationSessionVault()
        let receiverVault = LiveRegistrationSessionVault()
        var sender: MatrixRustSDKChatService! = MatrixRustSDKChatService(
            configuration: configuration,
            vault: senderVault,
            clientFactory: MatrixRustLiveClientFactory(configuration: configuration, rootDirectory: senderRoot)
        )
        let receiver = MatrixRustSDKChatService(
            configuration: configuration,
            vault: receiverVault,
            clientFactory: MatrixRustLiveClientFactory(configuration: configuration, rootDirectory: receiverRoot)
        )

        _ = try await receiver.signIn(username: receiverUsername, password: receiverPassword)
        _ = try await sender.signIn(username: senderUsername, password: senderPassword)
        let roomName = "Hypha live E2EE \(UUID().uuidString)"
        let senderRoom = try await sender.createEncryptedRoom(.init(name: roomName))
        _ = try await sender.refreshRooms()
        try await sender.inviteUsers(.init(
            roomID: senderRoom.id,
            userIDs: ["@\(receiverUsername):synapse.zenith-research.ca"]
        ))
        let invitedRooms = try await receiver.refreshRooms()
        let invitation = try XCTUnwrap(invitedRooms.first { $0.id == senderRoom.id && $0.hasInvite })
        try await receiver.acceptInvitation(roomID: invitation.id)
        let receiverRooms = try await receiver.refreshRooms()
        XCTAssertTrue(receiverRooms.contains { $0.id == senderRoom.id && !$0.hasInvite && $0.isEncrypted })
        _ = try await sender.refreshRooms()

        let body = "Hypha cross-account E2EE verification \(UUID().uuidString)"
        try await sender.sendText(body, to: senderRoom.id)
        _ = try await receiver.refreshRooms()

        var matchingContent: MatrixTimelineEvent.Content?
        for _ in 0..<40 {
            let events = try await receiver.timeline(for: senderRoom.id)
            matchingContent = events.first(where: { event in
                if case let .text(value) = event.content { return value == body }
                return false
            })?.content
            if matchingContent != nil { break }
            try await Task<Never, Never>.sleep(for: .milliseconds(500))
        }
        guard case let .text(value)? = matchingContent else {
            return XCTFail("The post-sync cross-account event did not decrypt on the receiving session")
        }
        XCTAssertEqual(value, body)

        _ = await sender.suspend()
        sender = nil
        try await Task<Never, Never>.sleep(for: .milliseconds(100))
        let returnBody = "Hypha restored-account sync verification \(UUID().uuidString)"
        try await receiver.sendText(returnBody, to: senderRoom.id)

        let restoredSender = MatrixRustSDKChatService(
            configuration: configuration,
            vault: senderVault,
            clientFactory: MatrixRustLiveClientFactory(configuration: configuration, rootDirectory: senderRoot)
        )
        _ = try await restoredSender.restore()
        var restoredContent: MatrixTimelineEvent.Content?
        for _ in 0..<40 {
            let events = try await restoredSender.timeline(for: senderRoom.id)
            restoredContent = events.first(where: { event in
                if case let .text(value) = event.content { return value == returnBody }
                return false
            })?.content
            if restoredContent != nil { break }
            try await Task<Never, Never>.sleep(for: .milliseconds(500))
        }
        if let resultPath = environment["HYPHA_MATRIX_LIVE_RESULT_FILE"] {
            try senderRoom.id.write(toFile: resultPath, atomically: true, encoding: .utf8)
        }
        _ = try? await receiver.removeRoom(roomID: senderRoom.id)
        _ = try? await restoredSender.removeRoom(roomID: senderRoom.id)
        try? await restoredSender.logout()
        try? await receiver.logout()

        guard case let .text(restoredValue)? = restoredContent else {
            return XCTFail("The restored account consumed the peer event during sync without publishing it to the timeline")
        }
        XCTAssertEqual(restoredValue, returnBody)
    }

    func testDisposableFirstRunRegistrationCreatesOneDurableEncryptedSession() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["ZENITH_MATRIX_LIVE_REGISTRATION"] == "1" else {
            throw XCTSkip("Set ZENITH_MATRIX_LIVE_REGISTRATION=1 with disposable registration credentials")
        }
        guard let homeserverValue = environment["ZENITH_MATRIX_REGISTRATION_HOMESERVER"],
              let homeserver = URL(string: homeserverValue),
              homeserver.scheme?.lowercased() == "https",
              let username = environment["ZENITH_MATRIX_REGISTRATION_USERNAME"],
              let password = environment["ZENITH_MATRIX_REGISTRATION_PASSWORD"],
              let token = environment["ZENITH_MATRIX_REGISTRATION_TOKEN"] else {
            throw XCTSkip("Disposable registration environment is incomplete")
        }

        let configuration = MatrixProductConfiguration(homeserver: homeserver)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenith-registration-live-\(UUID().uuidString)", isDirectory: true)
        let vault = LiveRegistrationSessionVault()
        defer { try? FileManager.default.removeItem(at: root) }

        mark("registration-live: discovering supported homeserver capability")
        let registrationClient = MatrixInviteRegistrationClient(homeserver: homeserver)
        guard case .inviteToken = await registrationClient.capability() else {
            return XCTFail("Homeserver does not expose the supported token-only registration flow")
        }
        _ = try await registrationClient.register(.init(
            username: username,
            password: password,
            registrationToken: token
        ))

        let createdRoomID: String
        do {
            let service = MatrixRustSDKChatService(
                configuration: configuration,
                vault: vault,
                clientFactory: MatrixRustLiveClientFactory(configuration: configuration, rootDirectory: root)
            )
            mark("registration-live: performing the single deliberate SDK sign-in")
            _ = try await service.signIn(username: username, password: password)
            let initialBootstrapState = try await service.bootstrapFirstDeviceTrust()
            let completedBootstrapState: MatrixFirstDeviceTrustBootstrapState
            if initialBootstrapState == .passwordRequired {
                completedBootstrapState = try await service.continueFirstDeviceTrust(password: password)
            } else {
                completedBootstrapState = initialBootstrapState
            }
            XCTAssertEqual(completedBootstrapState, .verifiedByCurrentSelfSigningKey)
            let confirmedTrustState = try await service.deviceTrustState()
            XCTAssertEqual(confirmedTrustState, .verifiedByCurrentSelfSigningKey)
            mark("registration-live: first device signed by the new account identity")
            let room = try await service.createEncryptedRoom(
                MatrixRoomCreationRequest(name: "Zenith disposable first-run proof")
            )
            XCTAssertTrue(room.isEncrypted)
            try await service.sendText("first-run encrypted send", to: room.id)
            createdRoomID = room.id
        }

        try await Task<Never, Never>.sleep(for: .milliseconds(250))
        let restoredService = MatrixRustSDKChatService(
            configuration: configuration,
            vault: vault,
            clientFactory: MatrixRustLiveClientFactory(configuration: configuration, rootDirectory: root)
        )
        let restoredRooms = try await restoredService.restore()
        XCTAssertTrue(restoredRooms.contains { $0.id == createdRoomID && $0.isEncrypted })
        let restoredTrustState = try await restoredService.deviceTrustState()
        XCTAssertEqual(restoredTrustState, .verifiedByCurrentSelfSigningKey)
        mark("registration-live: durable first-device identity and encrypted session restored")
    }

    private func mark(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}

private final class LiveRegistrationSessionVault: MatrixSDKSessionVault, @unchecked Sendable {
    private let lock = NSLock()
    private var session: MatrixSDKSessionRecord?
    private var storeKeys: [String: Data] = [:]

    func loadSession() throws -> MatrixSDKSessionRecord? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    func saveSession(_ value: MatrixSDKSessionRecord) throws {
        lock.lock(); defer { lock.unlock() }
        session = value
    }

    func deleteSession() throws {
        lock.lock(); defer { lock.unlock() }
        session = nil
    }

    func loadStoreKey(accountKey: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storeKeys[accountKey]
    }

    func saveStoreKey(_ value: Data, accountKey: String) throws {
        lock.lock(); defer { lock.unlock() }
        storeKeys[accountKey] = value
    }
}
