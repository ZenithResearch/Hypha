import Foundation
import XCTest
@testable import HyphaCore

final class HyphaAdminBrokerClientTests: XCTestCase {
    private let sessionToken = "opaque-session-token-value-12345678"

    func testAuthenticationPostsDedicatedSecretAndRetainsOnlyReturnedSessionInMemory() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        let session = try await client.authenticate(secret: "dedicated-administration-secret-value")

        XCTAssertEqual(session.expiresInSeconds, 600)
        XCTAssertEqual(session.idleTimeoutSeconds, 120)
        let hasActiveSession = await client.hasActiveSession
        XCTAssertTrue(hasActiveSession)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.absoluteString, "https://matrix.example.org/_hypha/admin/v1/session")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(requests[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["secret"] as? String, "dedicated-administration-secret-value")
        XCTAssertFalse(String(describing: client).contains("dedicated-administration-secret-value"))
        XCTAssertFalse(String(describing: client).contains(sessionToken))
    }

    func testSnapshotUsesOnlyBrokerBearerTokenAndExactTypedPath() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            response(
                status: 200,
                json: [
                    "users": [[
                        "user_id": "@alice:example.org",
                        "is_administrator": false,
                        "is_deactivated": false,
                        "is_guest": false,
                        "user_type": NSNull(),
                    ]],
                    "rooms": [[
                        "room_id": "!room:example.org",
                        "name": "Room",
                        "joined_member_count": 1,
                        "owner_user_id": "@alice:example.org",
                        "visibility": "public",
                    ]],
                ]
            ),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        let snapshot = try await client.snapshot()

        XCTAssertEqual(snapshot.currentUserID, "")
        XCTAssertEqual(snapshot.users.map(\.userID), ["@alice:example.org"])
        XCTAssertEqual(snapshot.rooms.map(\.roomID), ["!room:example.org"])
        XCTAssertEqual(snapshot.rooms.first?.ownerUserID, "@alice:example.org")
        XCTAssertEqual(snapshot.rooms.first?.visibility, .public)
        let requests = await transport.requests()
        XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertEqual(requests[1].url?.path, "/_hypha/admin/v1/snapshot")
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer \(sessionToken)"
        )
        XCTAssertNil(requests[1].httpBody)
    }

    func testLogoutRevokesServerSessionBeforeClearingLocalAuthority() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            response(status: 204),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        try await client.endSession()

        let hasActiveSession = await client.hasActiveSession
        XCTAssertFalse(hasActiveSession)
        let requests = await transport.requests()
        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertEqual(requests[1].url?.path, "/_hypha/admin/v1/session")
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer \(sessionToken)"
        )
    }

    func testUnexpectedBodyOnNoContentOperationFailsClosed() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            MatrixAdminHTTPResponse(
                statusCode: 204,
                body: Data("unexpected".utf8),
                responseURL: URL(string: "https://matrix.example.org/_hypha/admin/v1/users/logout")!,
                headers: [:]
            ),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        do {
            try await client.logoutAccount(userID: "@alice:example.org")
            XCTFail("Expected a malformed no-content response to fail closed")
        } catch {
            XCTAssertEqual(error as? HyphaAdminBrokerError, .invalidResponse)
        }
        let hasActiveSession = await client.hasActiveSession
        XCTAssertFalse(hasActiveSession)
    }

    func testRejectedOrExpiredSessionClearsLocalAuthorityAndFailsClosed() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            response(status: 401),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        do {
            _ = try await client.snapshot()
            XCTFail("Expected the expired broker session to fail closed")
        } catch {
            XCTAssertEqual(error as? HyphaAdminBrokerError, .sessionExpired)
        }
        let hasActiveSession = await client.hasActiveSession
        XCTAssertFalse(hasActiveSession)
    }

    func testAuthenticationFailureAndRateLimitUseStableSafeErrors() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(status: 401),
            response(status: 429),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        for expected in [HyphaAdminBrokerError.authenticationRejected, .rateLimited] {
            do {
                _ = try await client.authenticate(secret: "not-the-real-administration-secret")
                XCTFail("Expected administration authentication to fail")
            } catch {
                XCTAssertEqual(error as? HyphaAdminBrokerError, expected)
                XCTAssertFalse(String(describing: error).contains("not-the-real-administration-secret"))
            }
        }
        let hasActiveSession = await client.hasActiveSession
        XCTAssertFalse(hasActiveSession)
    }

    func testTypedAdministrationOperationsUseOnlyBrokerAllowlist() async throws {
        let userJSON: [String: Any] = [
            "user_id": "@alice:example.org",
            "is_administrator": false,
            "is_deactivated": false,
            "is_guest": false,
            "user_type": NSNull(),
        ]
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            response(status: 201, json: userJSON),
            response(status: 200, json: userJSON.merging(["is_administrator": true]) { _, new in new }),
            response(status: 200, jsonArray: [[
                "user_id": "@alice:example.org",
                "request_id": "11111111-1111-4111-8111-111111111111",
                "requested_at_ms": 1_786_000_000_000,
            ]]),
            response(status: 204),
            response(status: 201, json: [
                "room_id": "!room:example.org",
                "name": "Operations",
                "joined_member_count": 1,
            ]),
            response(status: 204),
            response(status: 204),
            response(status: 204),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        _ = try await client.createAccount(
            localpart: "alice",
            temporaryPassword: "temporary-password-value",
            administrator: false
        )
        _ = try await client.setAdministrator(userID: "@alice:example.org", administrator: true)
        let pending = try await client.passwordResetRequests()
        try await client.resetPassword(
            for: pending[0],
            temporaryPassword: "replacement-password-value"
        )
        _ = try await client.createRoom(
            name: "Operations",
            topic: "Private work",
            asSpace: false,
            visibility: .inviteOnly
        )
        try await client.logoutAccount(userID: "@alice:example.org")
        try await client.deactivateAccount(userID: "@alice:example.org")
        try await client.purgeRoom(roomID: "!room:example.org")

        let requests = await transport.requests()
        XCTAssertEqual(requests.dropFirst().map(\.httpMethod), [
            "POST", "PUT", "GET", "PUT", "POST", "POST", "POST", "POST",
        ])
        XCTAssertEqual(requests.dropFirst().map(\.url?.path), [
            "/_hypha/admin/v1/users",
            "/_hypha/admin/v1/users/administrator",
            "/_hypha/admin/v1/password-reset-requests",
            "/_hypha/admin/v1/users/password",
            "/_hypha/admin/v1/rooms",
            "/_hypha/admin/v1/users/logout",
            "/_hypha/admin/v1/users/deactivate",
            "/_hypha/admin/v1/rooms/purge",
        ])
        XCTAssertTrue(requests.dropFirst().allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(sessionToken)"
        })
        let createAccountBody = try XCTUnwrap(requests[1].httpBody)
        let createAccountJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: createAccountBody) as? [String: Any]
        )
        XCTAssertEqual(createAccountJSON["temporary_password"] as? String, "temporary-password-value")
        let resetBody = try XCTUnwrap(requests[4].httpBody)
        let resetJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: resetBody) as? [String: Any])
        XCTAssertEqual(resetJSON["request_id"] as? String, pending[0].requestID)
        XCTAssertEqual(resetJSON["temporary_password"] as? String, "replacement-password-value")
    }

    func testClientRejectsUnsafeHomeserverAndSecretBeforeNetwork() async throws {
        for rawURL in [
            "http://matrix.example.org",
            "https://operator@matrix.example.org",
            "https://matrix.example.org/path",
            "https://matrix.example.org?secret=value",
            "https://matrix.example.org#fragment",
        ] {
            XCTAssertThrowsError(
                try HyphaAdminBrokerClient(
                    homeserver: URL(string: rawURL)!,
                    transport: RecordingBrokerTransport(responses: [])
                )
            ) { error in
                XCTAssertEqual(error as? HyphaAdminBrokerError, .invalidConfiguration)
            }
        }

        let transport = RecordingBrokerTransport(responses: [])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        for secret in [
            "",
            "short",
            "control-character-secret-value\n",
            String(repeating: "x", count: 513),
        ] {
            do {
                _ = try await client.authenticate(secret: secret)
                XCTFail("Expected invalid administration secret input")
            } catch {
                XCTAssertEqual(error as? HyphaAdminBrokerError, .authenticationRejected)
            }
        }
        let observedRequests = await transport.requests()
        XCTAssertTrue(observedRequests.isEmpty)
    }

    func testOversizedResponseFailsClosedAndRevokesLocalSession() async throws {
        let transport = RecordingBrokerTransport(responses: [
            response(
                status: 201,
                json: [
                    "session_token": sessionToken,
                    "expires_in_seconds": 600,
                    "idle_timeout_seconds": 120,
                ]
            ),
            MatrixAdminHTTPResponse(
                statusCode: 200,
                body: Data(repeating: 0x78, count: 1024 * 1024 + 1),
                responseURL: URL(string: "https://matrix.example.org/_hypha/admin/v1/snapshot")!,
                headers: ["content-type": "application/json"]
            ),
        ])
        let client = try HyphaAdminBrokerClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )
        _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

        do {
            _ = try await client.snapshot()
            XCTFail("Expected the oversized broker response to fail closed")
        } catch {
            XCTAssertEqual(error as? HyphaAdminBrokerError, .invalidResponse)
        }
        let hasActiveSession = await client.hasActiveSession
        XCTAssertFalse(hasActiveSession)
    }

    func testSnapshotRejectsMalformedMatrixIdentifiersAndRevokesLocalSession() async throws {
        let invalidIdentifiers = [
            "@:example.org",
            "@alice:",
            "@ali\nce:example.org",
            "!:example.org",
            "!room:",
            "!room:example.org\u{7F}",
        ]

        for identifier in invalidIdentifiers {
            let isUser = identifier.first == "@"
            let transport = RecordingBrokerTransport(responses: [
                response(
                    status: 201,
                    json: [
                        "session_token": sessionToken,
                        "expires_in_seconds": 600,
                        "idle_timeout_seconds": 120,
                    ]
                ),
                response(
                    status: 200,
                    json: [
                        "users": isUser ? [[
                            "user_id": identifier,
                            "is_administrator": false,
                            "is_deactivated": false,
                            "is_guest": false,
                            "user_type": NSNull(),
                        ]] : [],
                        "rooms": isUser ? [] : [[
                            "room_id": identifier,
                            "name": "Malformed",
                            "joined_member_count": 1,
                        ]],
                    ]
                ),
            ])
            let client = try HyphaAdminBrokerClient(
                homeserver: URL(string: "https://matrix.example.org")!,
                transport: transport
            )
            _ = try await client.authenticate(secret: "dedicated-administration-secret-value")

            do {
                _ = try await client.snapshot()
                XCTFail("Expected malformed Matrix identifier to fail closed: \(identifier.debugDescription)")
            } catch {
                XCTAssertEqual(error as? HyphaAdminBrokerError, .invalidResponse)
            }
            let hasActiveSession = await client.hasActiveSession
            XCTAssertFalse(hasActiveSession)
        }
    }

    private func response(
        status: Int,
        json: [String: Any]? = nil,
        jsonArray: [[String: Any]]? = nil
    ) -> MatrixAdminHTTPResponse {
        let object: Any? = json ?? jsonArray
        let body = object.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return MatrixAdminHTTPResponse(
            statusCode: status,
            body: body,
            responseURL: URL(string: "https://matrix.example.org/_hypha/admin/v1/test")!,
            headers: ["content-type": "application/json"]
        )
    }
}

private actor RecordingBrokerTransport: MatrixAdminHTTPTransport {
    private var queuedResponses: [MatrixAdminHTTPResponse]
    private var observed: [URLRequest] = []

    init(responses: [MatrixAdminHTTPResponse]) {
        self.queuedResponses = responses
    }

    func send(_ request: URLRequest) async throws -> MatrixAdminHTTPResponse {
        observed.append(request)
        guard !queuedResponses.isEmpty else {
            throw HyphaAdminBrokerError.offline
        }
        return queuedResponses.removeFirst()
    }

    func requests() -> [URLRequest] {
        observed
    }
}
