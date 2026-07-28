import XCTest
@testable import ZenithMacOSClientCore

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
