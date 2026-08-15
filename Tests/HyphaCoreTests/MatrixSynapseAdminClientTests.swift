import Foundation
import XCTest
@testable import HyphaCore

final class MatrixSynapseAdminClientTests: XCTestCase {
    func testAdministratorAccessRequiresAuthoritativeTrueResponse() async throws {
        let deniedTransport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["admin": false]),
        ])
        let denied = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: deniedTransport
        )
        let deniedResult = try await denied.isAdministrator()
        XCTAssertFalse(deniedResult)

        let allowedTransport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["admin": true]),
        ])
        let allowed = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: allowedTransport
        )
        let allowedResult = try await allowed.isAdministrator()
        XCTAssertTrue(allowedResult)
    }

    func testAdministratorAccessFallsBackToAuthoritativeUserDetailWhenLegacyEndpointIsUnavailable() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 404, body: ["errcode": "M_UNRECOGNIZED"]),
            .json(status: 200, body: [
                "name": "@operator:example.org",
                "admin": false,
                "deactivated": false,
            ]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let authorized = try await client.isAdministrator()
        XCTAssertTrue(authorized)
        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.url?.path), [
            "/_synapse/admin/v1/users/@operator:example.org/admin",
            "/_synapse/admin/v2/users/@operator:example.org",
        ])
    }

    func testAdministratorFallbackRejectsMalformedUserDetail() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 404, body: ["errcode": "M_UNRECOGNIZED"]),
            .json(status: 200, body: ["name": "@operator:example.org"]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        await XCTAssertThrowsAdminError(
            try await client.isAdministrator(),
            expected: .invalidResponse
        )
    }

    func testAccountCreationUsesCurrentServerNameAndRequestedAdministratorRole() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: [
                "name": "@new.user:example.org",
                "admin": true,
                "deactivated": false,
                "is_guest": false,
                "user_type": NSNull(),
            ]),
            .json(status: 200, body: [
                "name": "@new.user:example.org",
                "admin": true,
                "deactivated": false,
                "is_guest": false,
                "user_type": NSNull(),
                "password_hash": "stored-hash-redacted",
                "approved": true,
            ]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let user = try await client.createAccount(
            localpart: "new.user",
            temporaryPassword: "temporary-password-value",
            administrator: true
        )

        XCTAssertEqual(user.userID, "@new.user:example.org")
        XCTAssertTrue(user.isAdministrator)
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 2)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/_synapse/admin/v2/users/@new.user:example.org")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token-material")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["admin"] as? Bool, true)
        XCTAssertEqual(json["password"] as? String, "temporary-password-value")
        XCTAssertEqual(json["approved"] as? Bool, true)
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains("secret-token-material") == true)
        XCTAssertEqual(requests.last?.httpMethod, "GET")
        XCTAssertEqual(requests.last?.url?.path, "/_synapse/admin/v2/users/@new.user:example.org")
    }

    func testAccountCreationFailsClosedWhenSynapseDoesNotConfirmStoredLocalPassword() async {
        let account = [
            "name": "@new.user:example.org",
            "admin": false,
            "deactivated": false,
            "is_guest": false,
            "user_type": NSNull(),
        ] as [String: Any]
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: account),
            .json(status: 200, body: account),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        await XCTAssertThrowsAdminError(
            try await client.createAccount(
                localpart: "new.user",
                temporaryPassword: "temporary-password-value",
                administrator: false
            ),
            expected: .credentialNotEstablished
        )
    }

    func testAccountCreationFailsClosedWhenSynapseDoesNotApprovePasswordLogin() async {
        let created = [
            "name": "@new.user:example.org",
            "admin": false,
            "deactivated": false,
            "is_guest": false,
            "user_type": NSNull(),
        ] as [String: Any]
        var unapproved = created
        unapproved["password_hash"] = "stored-hash-redacted"
        unapproved["approved"] = false
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: created),
            .json(status: 200, body: unapproved),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        await XCTAssertThrowsAdminError(
            try await client.createAccount(
                localpart: "new.user",
                temporaryPassword: "temporary-password-value",
                administrator: false
            ),
            expected: .credentialNotEstablished
        )
    }

    func testInvalidLocalpartFailsBeforeTransportOrCredentialUse() async {
        let transport = RecordingAdminTransport(responses: [])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        await XCTAssertThrowsAdminError(
            try await client.createAccount(
                localpart: "bad/name",
                temporaryPassword: "temporary-password-value",
                administrator: false
            ),
            expected: .invalidInput
        )
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testUserCreatesAuthenticatedHomeserverPasswordResetRequest() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: [:]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@member:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let request = try await client.requestPasswordReset(
            requestID: "01234567-89AB-CDEF-0123-456789ABCDEF",
            requestedAtMilliseconds: 1_786_000_000_000
        )

        XCTAssertEqual(request.userID, "@member:example.org")
        let recordedRequests = await transport.requests()
        let recorded = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(recorded.httpMethod, "PUT")
        XCTAssertEqual(
            recorded.url?.path,
            "/_matrix/client/v3/user/@member:example.org/account_data/ca.zenithresearch.hypha.password_reset_request"
        )
        let body = try XCTUnwrap(recorded.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["status"] as? String, "pending")
        XCTAssertEqual(json["request_id"] as? String, request.requestID)
        XCTAssertEqual(json["requested_at_ms"] as? Int, 1_786_000_000_000)
    }

    func testUserReadsPendingHomeserverPasswordResetRequestFromOwnAccountData() async throws {
        let requestID = "27EF43D8-A08B-4A58-9B45-F11D06E82A61"
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: [
                "status": "pending",
                "request_id": requestID,
                "requested_at_ms": 1_786_000_000_000,
            ]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@member:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let pendingRequest = try await client.currentPasswordResetRequest()
        let request = try XCTUnwrap(pendingRequest)

        XCTAssertEqual(request.userID, "@member:example.org")
        XCTAssertEqual(request.requestID, requestID)
        let requests = await transport.requests()
        XCTAssertEqual(requests.first?.httpMethod, "GET")
        XCTAssertEqual(
            requests.first?.url?.path,
            "/_matrix/client/v3/user/@member:example.org/account_data/ca.zenithresearch.hypha.password_reset_request"
        )
    }

    func testAdministratorListsOnlyValidPendingPasswordResetRequests() async throws {
        let users = [
            MatrixAdminUserSummary(userID: "@pending:example.org", isAdministrator: false, isDeactivated: false, isGuest: false, userType: nil),
            MatrixAdminUserSummary(userID: "@completed:example.org", isAdministrator: false, isDeactivated: false, isGuest: false, userType: nil),
        ]
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["admin": true]),
            .json(status: 200, body: [
                "status": "pending",
                "request_id": "01234567-89AB-CDEF-0123-456789ABCDEF",
                "requested_at_ms": 1_786_000_000_000,
            ]),
            .json(status: 200, body: [
                "status": "completed",
                "request_id": "11234567-89AB-CDEF-0123-456789ABCDEF",
                "requested_at_ms": 1_786_000_000_100,
            ]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let requests = try await client.passwordResetRequests(users: users)

        XCTAssertEqual(requests.map(\.userID), ["@pending:example.org"])
    }

    func testAdministratorResetRevalidatesPendingRequestAndPreservesRole() async throws {
        let target = "@member:example.org"
        let requestID = "01234567-89AB-CDEF-0123-456789ABCDEF"
        let account: [String: Any] = [
            "name": target,
            "admin": false,
            "deactivated": false,
            "is_guest": false,
            "approved": true,
            "locked": false,
            "password_hash": "old-hash-redacted",
            "user_type": NSNull(),
        ]
        var verified = account
        verified["password_hash"] = "new-hash-redacted"
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["admin": true]),
            .json(status: 200, body: [
                "status": "pending", "request_id": requestID, "requested_at_ms": 1_786_000_000_000,
            ]),
            .json(status: 200, body: account),
            .json(status: 200, body: account),
            .json(status: 200, body: verified),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        try await client.resetPassword(
            for: MatrixPasswordResetRequest(userID: target, requestID: requestID, requestedAtMilliseconds: 1_786_000_000_000),
            temporaryPassword: "replacement-password-value"
        )

        let requests = await transport.requests()
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "GET", "GET", "PUT", "GET"])
        let resetBody = try XCTUnwrap(requests[3].httpBody)
        let resetJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: resetBody) as? [String: Any])
        XCTAssertEqual(resetJSON["admin"] as? Bool, false)
        XCTAssertEqual(resetJSON["approved"] as? Bool, true)
        XCTAssertEqual(resetJSON["logout_devices"] as? Bool, true)
        XCTAssertEqual(resetJSON["password"] as? String, "replacement-password-value")
    }

    func testRoomPurgeRequestsBlockPurgeAndForcePurge() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: [:]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        try await client.purgeRoom(roomID: "!room:example.org")

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "DELETE")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["block"] as? Bool, true)
        XCTAssertEqual(json["purge"] as? Bool, true)
        XCTAssertEqual(json["force_purge"] as? Bool, true)
    }

    func testUserDeactivationCannotTargetCurrentAdministrator() async {
        let transport = RecordingAdminTransport(responses: [])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        await XCTAssertThrowsAdminError(
            try await client.deactivateAccount(userID: "@operator:example.org"),
            expected: .protectedAccount
        )
        let requests = await transport.requests()
        XCTAssertEqual(requests.count, 0)
    }

    func testAdministratorCanDeactivateAnotherAdministrator() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["id_server_unbind_result": "no-support"]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        try await client.deactivateAccount(userID: "@other.admin:example.org")

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/_synapse/admin/v1/deactivate/@other.admin:example.org")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["erase"] as? Bool, true)
    }

    func testAdministratorCreatesPrivateEncryptedRoomThroughClientAPI() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["room_id": "!created:example.org"]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        let room = try await client.createRoom(name: "Operations", topic: "Private work", asSpace: false)

        XCTAssertEqual(room.roomID, "!created:example.org")
        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/_matrix/client/v3/createRoom")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["visibility"] as? String, "private")
        XCTAssertEqual(json["preset"] as? String, "private_chat")
        let initialState = try XCTUnwrap(json["initial_state"] as? [[String: Any]])
        XCTAssertEqual(initialState.first?["type"] as? String, "m.room.encryption")
    }

    func testAdministratorCreatesPrivateSpaceThroughClientAPI() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["room_id": "!space:example.org"]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        _ = try await client.createRoom(name: "Community", topic: "Rooms", asSpace: true)

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let creationContent = try XCTUnwrap(json["creation_content"] as? [String: Any])
        XCTAssertEqual(creationContent["type"] as? String, "m.space")
        XCTAssertNil(json["initial_state"])
    }

    func testAdministratorCreatesPublicSpaceThroughClientAPI() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: ["room_id": "!public-space:example.org"]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        _ = try await client.createRoom(
            name: "Public Community",
            topic: "Open rooms",
            asSpace: true,
            visibility: .public
        )

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["visibility"] as? String, "public")
        XCTAssertEqual(json["preset"] as? String, "public_chat")
        let creationContent = try XCTUnwrap(json["creation_content"] as? [String: Any])
        XCTAssertEqual(creationContent["type"] as? String, "m.space")
    }

    func testAdministratorCanLogOutEveryDeviceForAnyAccount() async throws {
        let transport = RecordingAdminTransport(responses: [
            .json(status: 200, body: [:]),
        ])
        let client = MatrixSynapseAdminClient(
            homeserver: URL(string: "https://synapse.example.org")!,
            currentUserID: "@operator:example.org",
            accessToken: "secret-token-material",
            transport: transport
        )

        try await client.logoutAccount(userID: "@other:example.org")

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/_synapse/admin/v1/users/@other:example.org/logout")
    }
}

private actor RecordingAdminTransport: MatrixAdminHTTPTransport {
    private var queuedResponses: [MatrixAdminHTTPResponse]
    private var recordedRequests: [URLRequest] = []

    init(responses: [MatrixAdminHTTPResponse]) {
        queuedResponses = responses
    }

    func send(_ request: URLRequest) async throws -> MatrixAdminHTTPResponse {
        recordedRequests.append(request)
        guard !queuedResponses.isEmpty else { throw MatrixAdminClientError.invalidResponse }
        return queuedResponses.removeFirst()
    }

    func requests() -> [URLRequest] { recordedRequests }
}

private extension MatrixAdminHTTPResponse {
    static func json(status: Int, body: [String: Any]) -> Self {
        .init(
            statusCode: status,
            body: try! JSONSerialization.data(withJSONObject: body),
            responseURL: URL(string: "https://synapse.example.org")!
        )
    }
}

private func XCTAssertThrowsAdminError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: MatrixAdminClientError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected Matrix admin error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? MatrixAdminClientError, expected, file: file, line: line)
        XCTAssertFalse(String(describing: error).contains("secret-token-material"), file: file, line: line)
        XCTAssertFalse(String(describing: error).contains("temporary-password-value"), file: file, line: line)
    }
}
