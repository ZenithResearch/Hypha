import Foundation

public enum MatrixAdminClientError: Error, Equatable, Sendable {
    case invalidInput
    case notAdministrator
    case protectedAccount
    case sessionExpired
    case offline
    case invalidResponse
    case serverRejected
    case credentialNotEstablished
}

public struct MatrixAdminUserSummary: Identifiable, Equatable, Sendable {
    public let userID: String
    public let isAdministrator: Bool
    public let isDeactivated: Bool
    public let isGuest: Bool
    public let userType: String?

    public var id: String { userID }

    public init(
        userID: String,
        isAdministrator: Bool,
        isDeactivated: Bool,
        isGuest: Bool,
        userType: String?
    ) {
        self.userID = userID
        self.isAdministrator = isAdministrator
        self.isDeactivated = isDeactivated
        self.isGuest = isGuest
        self.userType = userType
    }
}

public struct MatrixPasswordResetRequest: Identifiable, Equatable, Sendable {
    public let userID: String
    public let requestID: String
    public let requestedAtMilliseconds: Int64

    public var id: String { requestID }

    public init(userID: String, requestID: String, requestedAtMilliseconds: Int64) {
        self.userID = userID
        self.requestID = requestID
        self.requestedAtMilliseconds = requestedAtMilliseconds
    }
}

public struct MatrixAdminRoomSummary: Identifiable, Equatable, Sendable {
    public let roomID: String
    public let name: String
    public let joinedMemberCount: Int

    public var id: String { roomID }

    public init(roomID: String, name: String, joinedMemberCount: Int) {
        self.roomID = roomID
        self.name = name
        self.joinedMemberCount = joinedMemberCount
    }
}

public struct MatrixAdminSnapshot: Equatable, Sendable {
    public let currentUserID: String
    public let users: [MatrixAdminUserSummary]
    public let rooms: [MatrixAdminRoomSummary]

    public init(
        currentUserID: String = "",
        users: [MatrixAdminUserSummary],
        rooms: [MatrixAdminRoomSummary]
    ) {
        self.currentUserID = currentUserID
        self.users = users
        self.rooms = rooms
    }
}

public protocol MatrixAdminClient: Sendable {
    func isAdministrator() async throws -> Bool
    func snapshot() async throws -> MatrixAdminSnapshot
    func createAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary
    func createRoom(
        name: String,
        topic: String,
        asSpace: Bool,
        visibility: MatrixRoomVisibility
    ) async throws -> MatrixAdminRoomSummary
    func logoutAccount(userID: String) async throws
    func deactivateAccount(userID: String) async throws
    func purgeRoom(roomID: String) async throws
    func requestPasswordReset(requestID: String, requestedAtMilliseconds: Int64) async throws -> MatrixPasswordResetRequest
    func currentPasswordResetRequest() async throws -> MatrixPasswordResetRequest?
    func completePasswordResetRequest(completedAtMilliseconds: Int64) async throws
    func passwordResetRequests(users: [MatrixAdminUserSummary]) async throws -> [MatrixPasswordResetRequest]
    func resetPassword(for request: MatrixPasswordResetRequest, temporaryPassword: String) async throws
}

public struct MatrixAdminHTTPResponse: Sendable {
    public let statusCode: Int
    public let body: Data
    public let responseURL: URL

    public init(statusCode: Int, body: Data, responseURL: URL) {
        self.statusCode = statusCode
        self.body = body
        self.responseURL = responseURL
    }
}

public protocol MatrixAdminHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> MatrixAdminHTTPResponse
}

private final class MatrixAdminRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public actor MatrixURLSessionAdminTransport: MatrixAdminHTTPTransport {
    private let delegate: MatrixAdminRedirectRejectingDelegate
    private let session: URLSession

    public init() {
        let delegate = MatrixAdminRedirectRejectingDelegate()
        self.delegate = delegate
        self.session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> MatrixAdminHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  let responseURL = httpResponse.url else {
                throw MatrixAdminClientError.invalidResponse
            }
            return MatrixAdminHTTPResponse(
                statusCode: httpResponse.statusCode,
                body: data,
                responseURL: responseURL
            )
        } catch let error as MatrixAdminClientError {
            throw error
        } catch {
            throw MatrixAdminClientError.offline
        }
    }
}

public struct MatrixSynapseAdminClient: MatrixAdminClient, Sendable {
    private static let localpartPattern = try! NSRegularExpression(pattern: "^[a-z0-9._=-]+$")
    private static let passwordResetAccountDataType = "ca.zenithresearch.hypha.password_reset_request"

    private let homeserver: URL
    private let currentUserID: String
    private let accessToken: String
    private let transport: any MatrixAdminHTTPTransport

    public init(
        homeserver: URL,
        currentUserID: String,
        accessToken: String,
        transport: any MatrixAdminHTTPTransport = MatrixURLSessionAdminTransport()
    ) {
        self.homeserver = homeserver
        self.currentUserID = currentUserID
        self.accessToken = accessToken
        self.transport = transport
    }

    public func isAdministrator() async throws -> Bool {
        let response = try await perform(
            method: "GET",
            path: "/_synapse/admin/v1/users/\(encoded(currentUserID))/admin"
        )
        guard response.statusCode == 200,
              let object = jsonObject(response.body),
              let administrator = object["admin"] as? Bool else {
            throw mappedError(for: response.statusCode)
        }
        return administrator
    }

    public func snapshot() async throws -> MatrixAdminSnapshot {
        guard try await isAdministrator() else { throw MatrixAdminClientError.notAdministrator }
        async let users = listUsers()
        async let rooms = listRooms()
        return try await MatrixAdminSnapshot(
            currentUserID: currentUserID,
            users: users,
            rooms: rooms
        )
    }

    public func createAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        let userIDParts = currentUserID.split(separator: ":", maxSplits: 1)
        guard validLocalpart(localpart), validPassword(temporaryPassword),
              userIDParts.count == 2,
              userIDParts[0].hasPrefix("@"),
              !userIDParts[1].isEmpty else {
            throw MatrixAdminClientError.invalidInput
        }
        let serverName = userIDParts[1]
        let expectedUserID = "@\(localpart):\(serverName)"
        let response = try await perform(
            method: "PUT",
            path: "/_synapse/admin/v2/users/\(encoded(expectedUserID))",
            json: [
                "password": temporaryPassword,
                "admin": administrator,
                "deactivated": false,
                "approved": true,
            ]
        )
        guard response.statusCode == 200,
              let user = parseUser(response.body),
              user.userID == expectedUserID,
              user.isAdministrator == administrator,
              !user.isDeactivated else {
            throw mappedError(for: response.statusCode)
        }
        let verification = try await perform(
            method: "GET",
            path: "/_synapse/admin/v2/users/\(encoded(expectedUserID))"
        )
        guard verification.statusCode == 200,
              let object = jsonObject(verification.body),
              let verifiedUser = parseUser(object),
              verifiedUser.userID == expectedUserID,
              verifiedUser.isAdministrator == administrator,
              !verifiedUser.isDeactivated,
              object["locked"] as? Bool != true,
              object["approved"] as? Bool != false,
              let passwordHash = object["password_hash"] as? String,
              !passwordHash.isEmpty else {
            throw MatrixAdminClientError.credentialNotEstablished
        }
        return verifiedUser
    }

    public func requestPasswordReset(
        requestID: String = UUID().uuidString,
        requestedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) async throws -> MatrixPasswordResetRequest {
        guard validUserID(currentUserID), UUID(uuidString: requestID) != nil, requestedAtMilliseconds > 0 else {
            throw MatrixAdminClientError.invalidInput
        }
        let request = MatrixPasswordResetRequest(
            userID: currentUserID,
            requestID: requestID,
            requestedAtMilliseconds: requestedAtMilliseconds
        )
        let response = try await perform(
            method: "PUT",
            path: passwordResetClientPath(userID: currentUserID),
            json: [
                "status": "pending",
                "request_id": request.requestID,
                "requested_at_ms": request.requestedAtMilliseconds,
            ]
        )
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
        return request
    }

    public func currentPasswordResetRequest() async throws -> MatrixPasswordResetRequest? {
        guard validUserID(currentUserID) else { throw MatrixAdminClientError.invalidInput }
        let response = try await perform(
            method: "GET",
            path: passwordResetClientPath(userID: currentUserID)
        )
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
        return parsePasswordResetRequest(response.body, expectedUserID: currentUserID)
    }

    public func completePasswordResetRequest(
        completedAtMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) async throws {
        guard validUserID(currentUserID), completedAtMilliseconds > 0 else {
            throw MatrixAdminClientError.invalidInput
        }
        let response = try await perform(
            method: "PUT",
            path: passwordResetClientPath(userID: currentUserID),
            json: [
                "status": "completed",
                "completed_at_ms": completedAtMilliseconds,
            ]
        )
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
    }

    public func passwordResetRequests(
        users: [MatrixAdminUserSummary]
    ) async throws -> [MatrixPasswordResetRequest] {
        guard try await isAdministrator() else { throw MatrixAdminClientError.notAdministrator }
        var requests: [MatrixPasswordResetRequest] = []
        for user in users where !user.isDeactivated && !user.isGuest {
            let response = try await perform(
                method: "GET",
                path: passwordResetAdminPath(userID: user.userID)
            )
            if response.statusCode == 404 { continue }
            guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
            if let request = parsePasswordResetRequest(response.body, expectedUserID: user.userID) {
                requests.append(request)
            }
        }
        return requests.sorted {
            if $0.requestedAtMilliseconds == $1.requestedAtMilliseconds { return $0.userID < $1.userID }
            return $0.requestedAtMilliseconds < $1.requestedAtMilliseconds
        }
    }

    public func resetPassword(
        for request: MatrixPasswordResetRequest,
        temporaryPassword: String
    ) async throws {
        guard validUserID(request.userID), request.userID != currentUserID,
              UUID(uuidString: request.requestID) != nil, validPassword(temporaryPassword) else {
            throw MatrixAdminClientError.invalidInput
        }
        guard try await isAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        let requestResponse = try await perform(
            method: "GET",
            path: passwordResetAdminPath(userID: request.userID)
        )
        guard requestResponse.statusCode == 200,
              parsePasswordResetRequest(requestResponse.body, expectedUserID: request.userID) == request else {
            throw MatrixAdminClientError.serverRejected
        }
        let accountResponse = try await perform(
            method: "GET",
            path: "/_synapse/admin/v2/users/\(encoded(request.userID))"
        )
        guard accountResponse.statusCode == 200,
              let account = jsonObject(accountResponse.body),
              let user = parseUser(account),
              user.userID == request.userID,
              !user.isDeactivated,
              account["locked"] as? Bool != true,
              account["approved"] as? Bool != false,
              let previousHash = account["password_hash"] as? String,
              !previousHash.isEmpty else {
            throw MatrixAdminClientError.credentialNotEstablished
        }
        let resetResponse = try await perform(
            method: "PUT",
            path: "/_synapse/admin/v2/users/\(encoded(request.userID))",
            json: [
                "password": temporaryPassword,
                "admin": user.isAdministrator,
                "deactivated": false,
                "approved": true,
                "logout_devices": true,
            ]
        )
        guard resetResponse.statusCode == 200 else { throw mappedError(for: resetResponse.statusCode) }
        let verification = try await perform(
            method: "GET",
            path: "/_synapse/admin/v2/users/\(encoded(request.userID))"
        )
        guard verification.statusCode == 200,
              let verified = jsonObject(verification.body),
              let verifiedUser = parseUser(verified),
              verifiedUser.userID == request.userID,
              verifiedUser.isAdministrator == user.isAdministrator,
              !verifiedUser.isDeactivated,
              verified["locked"] as? Bool != true,
              verified["approved"] as? Bool != false,
              let newHash = verified["password_hash"] as? String,
              !newHash.isEmpty,
              newHash != previousHash else {
            throw MatrixAdminClientError.credentialNotEstablished
        }
    }

    public func createRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility = .inviteOnly) async throws -> MatrixAdminRoomSummary {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 255, cleanTopic.count <= 1_000 else {
            throw MatrixAdminClientError.invalidInput
        }
        var body: [String: Any] = [
            "name": cleanName,
            "visibility": visibility == .public ? "public" : "private",
            "preset": visibility == .public ? "public_chat" : "private_chat",
        ]
        if !cleanTopic.isEmpty { body["topic"] = cleanTopic }
        if asSpace {
            body["creation_content"] = ["type": "m.space"]
        } else {
            body["initial_state"] = [[
                "type": "m.room.encryption",
                "state_key": "",
                "content": ["algorithm": "m.megolm.v1.aes-sha2"],
            ]]
        }
        let response = try await perform(method: "POST", path: "/_matrix/client/v3/createRoom", json: body)
        guard response.statusCode == 200,
              let roomID = jsonObject(response.body)?["room_id"] as? String,
              roomID.hasPrefix("!") else {
            throw mappedError(for: response.statusCode)
        }
        return MatrixAdminRoomSummary(roomID: roomID, name: cleanName, joinedMemberCount: 1)
    }

    public func logoutAccount(userID: String) async throws {
        guard userID.hasPrefix("@"), userID.contains(":") else {
            throw MatrixAdminClientError.invalidInput
        }
        let response = try await perform(
            method: "POST",
            path: "/_synapse/admin/v1/users/\(encoded(userID))/logout",
            json: [:]
        )
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
    }

    public func deactivateAccount(userID: String) async throws {
        guard userID != currentUserID, userID.hasPrefix("@"), userID.contains(":") else {
            throw MatrixAdminClientError.protectedAccount
        }
        let response = try await perform(
            method: "POST",
            path: "/_synapse/admin/v1/deactivate/\(encoded(userID))",
            json: ["erase": true]
        )
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
    }

    public func purgeRoom(roomID: String) async throws {
        guard roomID.hasPrefix("!"), roomID.contains(":") else {
            throw MatrixAdminClientError.invalidInput
        }
        let response = try await perform(
            method: "DELETE",
            path: "/_synapse/admin/v2/rooms/\(encoded(roomID))",
            json: [
                "block": true,
                "purge": true,
                "force_purge": true,
            ]
        )
        guard response.statusCode == 200 else { throw mappedError(for: response.statusCode) }
        guard let object = jsonObject(response.body), let deleteID = object["delete_id"] as? String else {
            return
        }
        try await waitForRoomDeletion(deleteID: deleteID)
    }

    private func listUsers() async throws -> [MatrixAdminUserSummary] {
        var users: [MatrixAdminUserSummary] = []
        var offset = "0"
        while true {
            let response = try await perform(
                method: "GET",
                path: "/_synapse/admin/v2/users",
                queryItems: [
                    URLQueryItem(name: "from", value: offset),
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "guests", value: "false"),
                    URLQueryItem(name: "deactivated", value: "false"),
                ]
            )
            guard response.statusCode == 200,
                  let object = jsonObject(response.body),
                  let page = object["users"] as? [[String: Any]] else {
                throw mappedError(for: response.statusCode)
            }
            users.append(contentsOf: page.compactMap(parseUser))
            guard let next = object["next_token"] else { break }
            offset = String(describing: next)
        }
        return users.sorted { $0.userID.localizedCaseInsensitiveCompare($1.userID) == .orderedAscending }
    }

    private func listRooms() async throws -> [MatrixAdminRoomSummary] {
        var rooms: [MatrixAdminRoomSummary] = []
        var offset = "0"
        while true {
            let response = try await perform(
                method: "GET",
                path: "/_synapse/admin/v1/rooms",
                queryItems: [
                    URLQueryItem(name: "from", value: offset),
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "order_by", value: "name"),
                    URLQueryItem(name: "dir", value: "f"),
                ]
            )
            guard response.statusCode == 200,
                  let object = jsonObject(response.body),
                  let page = object["rooms"] as? [[String: Any]] else {
                throw mappedError(for: response.statusCode)
            }
            rooms.append(contentsOf: page.compactMap { room in
                guard let roomID = room["room_id"] as? String else { return nil }
                let name = (room["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? roomID
                let members = room["joined_members"] as? Int ?? 0
                return MatrixAdminRoomSummary(roomID: roomID, name: name, joinedMemberCount: members)
            })
            guard let next = object["next_batch"] else { break }
            offset = String(describing: next)
        }
        return rooms.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func waitForRoomDeletion(deleteID: String) async throws {
        for _ in 0..<60 {
            let response = try await perform(
                method: "GET",
                path: "/_synapse/admin/v2/rooms/delete_status/\(encoded(deleteID))"
            )
            guard response.statusCode == 200, let object = jsonObject(response.body),
                  let status = object["status"] as? String else {
                throw mappedError(for: response.statusCode)
            }
            if status == "complete" { return }
            if status == "failed" { throw MatrixAdminClientError.serverRejected }
            try await Task.sleep(for: .seconds(1))
        }
        throw MatrixAdminClientError.serverRejected
    }

    private func perform(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        json: [String: Any]? = nil
    ) async throws -> MatrixAdminHTTPResponse {
        guard validHomeserver(homeserver), var components = URLComponents(url: homeserver, resolvingAgainstBaseURL: false) else {
            throw MatrixAdminClientError.invalidInput
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = basePath.isEmpty ? path : "/\(basePath)\(path)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw MatrixAdminClientError.invalidInput }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try await transport.send(request)
        guard sameOrigin(url, response.responseURL) else { throw MatrixAdminClientError.invalidResponse }
        if response.statusCode == 401 { throw MatrixAdminClientError.sessionExpired }
        if response.statusCode == 403 { throw MatrixAdminClientError.notAdministrator }
        return response
    }

    private func validLocalpart(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 255 else { return false }
        let range = NSRange(value.startIndex..., in: value)
        return Self.localpartPattern.firstMatch(in: value, range: range)?.range == range
    }

    private func validPassword(_ value: String) -> Bool {
        !value.isEmpty && value.count >= 12 && value.count <= 512 && !value.unicodeScalars.contains { $0.value < 0x20 }
    }

    private func validHomeserver(_ url: URL) -> Bool {
        if url.scheme == "https" { return url.host != nil && url.user == nil && url.password == nil }
        return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host)
    }

    private func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhs.port == rhs.port
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }

    private func validUserID(_ value: String) -> Bool {
        guard value.hasPrefix("@"), value.count <= 512,
              let separator = value.firstIndex(of: ":"), separator > value.startIndex else { return false }
        return value.index(after: separator) < value.endIndex
    }

    private func passwordResetClientPath(userID: String) -> String {
        "/_matrix/client/v3/user/\(encoded(userID))/account_data/\(encoded(Self.passwordResetAccountDataType))"
    }

    private func passwordResetAdminPath(userID: String) -> String {
        "/_synapse/admin/v1/users/\(encoded(userID))/accountdata/\(encoded(Self.passwordResetAccountDataType))"
    }

    private func parsePasswordResetRequest(
        _ data: Data,
        expectedUserID: String
    ) -> MatrixPasswordResetRequest? {
        guard let object = jsonObject(data),
              object["status"] as? String == "pending",
              let requestID = object["request_id"] as? String,
              UUID(uuidString: requestID) != nil,
              let timestamp = (object["requested_at_ms"] as? NSNumber)?.int64Value,
              timestamp > 0 else { return nil }
        return MatrixPasswordResetRequest(
            userID: expectedUserID,
            requestID: requestID,
            requestedAtMilliseconds: timestamp
        )
    }

    private func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func parseUser(_ data: Data) -> MatrixAdminUserSummary? {
        guard let object = jsonObject(data) else { return nil }
        return parseUser(object)
    }

    private func parseUser(_ object: [String: Any]) -> MatrixAdminUserSummary? {
        guard let userID = object["name"] as? String else { return nil }
        return MatrixAdminUserSummary(
            userID: userID,
            isAdministrator: object["admin"] as? Bool ?? false,
            isDeactivated: object["deactivated"] as? Bool ?? false,
            isGuest: object["is_guest"] as? Bool ?? false,
            userType: object["user_type"] as? String
        )
    }

    private func mappedError(for statusCode: Int) -> MatrixAdminClientError {
        switch statusCode {
        case 401: .sessionExpired
        case 403: .notAdministrator
        case 400, 404, 409: .serverRejected
        default: .invalidResponse
        }
    }
}
