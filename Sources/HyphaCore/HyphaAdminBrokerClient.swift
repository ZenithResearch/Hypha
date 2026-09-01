import Foundation

public enum HyphaAdminBrokerError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidInput
    case authenticationRejected
    case rateLimited
    case sessionExpired
    case offline
    case invalidResponse
    case serverRejected
    case rotationOutcomeUnknown
}

public struct HyphaAdminBrokerSession: Equatable, Sendable {
    public let expiresInSeconds: Int
    public let idleTimeoutSeconds: Int

    public init(expiresInSeconds: Int, idleTimeoutSeconds: Int) {
        self.expiresInSeconds = expiresInSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
    }
}

public struct HyphaAdminBrokerCapabilities: Equatable, Sendable {
    public let contractVersion: Int
    public let features: Set<String>

    public init(contractVersion: Int, features: Set<String>) {
        self.contractVersion = contractVersion
        self.features = features
    }

    public var supportsSecretRotation: Bool {
        contractVersion == 1 && features.contains("secret_rotation")
    }
}

public actor HyphaAdminBrokerClient: CustomStringConvertible {
    private static let maximumResponseBytes = 1024 * 1024
    private static let maximumCollectionCount = 10_000

    private struct SessionResponse: Decodable {
        let sessionToken: String
        let expiresInSeconds: Int
        let idleTimeoutSeconds: Int

        enum CodingKeys: String, CodingKey {
            case sessionToken = "session_token"
            case expiresInSeconds = "expires_in_seconds"
            case idleTimeoutSeconds = "idle_timeout_seconds"
        }
    }

    private struct CapabilitiesResponse: Decodable {
        let contractVersion: Int
        let features: [String]

        enum CodingKeys: String, CodingKey {
            case contractVersion = "contract_version"
            case features
        }
    }

    private struct SnapshotResponse: Decodable {
        let users: [UserResponse]
        let rooms: [RoomResponse]
    }

    private struct UserResponse: Decodable {
        let userID: String
        let isAdministrator: Bool
        let isDeactivated: Bool
        let isGuest: Bool
        let userType: String?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case isAdministrator = "is_administrator"
            case isDeactivated = "is_deactivated"
            case isGuest = "is_guest"
            case userType = "user_type"
        }
    }

    private struct RoomResponse: Decodable {
        let roomID: String
        let name: String
        let joinedMemberCount: Int

        enum CodingKeys: String, CodingKey {
            case roomID = "room_id"
            case name
            case joinedMemberCount = "joined_member_count"
        }
    }

    private struct PasswordResetResponse: Decodable {
        let userID: String
        let requestID: String
        let requestedAtMilliseconds: Int64

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case requestID = "request_id"
            case requestedAtMilliseconds = "requested_at_ms"
        }
    }

    private let homeserver: URL
    private let transport: any MatrixAdminHTTPTransport
    private var sessionToken: String?
    private var capabilities: HyphaAdminBrokerCapabilities?

    public nonisolated var description: String {
        "HyphaAdminBrokerClient(session: redacted)"
    }

    public var hasActiveSession: Bool {
        sessionToken != nil
    }

    public var negotiatedCapabilities: HyphaAdminBrokerCapabilities? {
        capabilities
    }

    public init(
        homeserver: URL,
        transport: any MatrixAdminHTTPTransport = MatrixURLSessionAdminTransport()
    ) throws {
        guard Self.validHomeserver(homeserver) else {
            throw HyphaAdminBrokerError.invalidConfiguration
        }
        self.homeserver = homeserver
        self.transport = transport
    }

    public func authenticate(secret: String) async throws -> HyphaAdminBrokerSession {
        sessionToken = nil
        capabilities = nil
        guard Self.validSecret(secret) else {
            throw HyphaAdminBrokerError.authenticationRejected
        }
        let body: Data
        do {
            body = try JSONSerialization.data(
                withJSONObject: ["secret": secret],
                options: [.sortedKeys]
            )
        } catch {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await send(
            method: "POST",
            path: "/_hypha/admin/v1/session",
            body: body,
            authorization: nil
        )
        switch response.statusCode {
        case 201:
            break
        case 401, 403:
            throw HyphaAdminBrokerError.authenticationRejected
        case 429:
            throw HyphaAdminBrokerError.rateLimited
        default:
            throw mappedServerError(response.statusCode)
        }
        let decoded: SessionResponse = try decodeJSON(response)
        guard Self.validToken(decoded.sessionToken),
              (1...900).contains(decoded.expiresInSeconds),
              (1...decoded.expiresInSeconds).contains(decoded.idleTimeoutSeconds) else {
            throw HyphaAdminBrokerError.invalidResponse
        }
        sessionToken = decoded.sessionToken
        return HyphaAdminBrokerSession(
            expiresInSeconds: decoded.expiresInSeconds,
            idleTimeoutSeconds: decoded.idleTimeoutSeconds
        )
    }

    @discardableResult
    public func negotiateCapabilities() async throws -> HyphaAdminBrokerCapabilities {
        let token = try activeToken()
        let response = try await send(
            method: "GET",
            path: "/_hypha/admin/v1/capabilities",
            body: nil,
            authorization: token
        )
        if [404, 405, 501].contains(response.statusCode) {
            let legacy = HyphaAdminBrokerCapabilities(contractVersion: 0, features: [])
            capabilities = legacy
            return legacy
        }
        guard response.statusCode == 200 else {
            throw operationError(response.statusCode)
        }
        let decoded: CapabilitiesResponse = try decodeJSON(response)
        guard (0...32).contains(decoded.contractVersion),
              decoded.features.count <= 64,
              Set(decoded.features).count == decoded.features.count,
              decoded.features.allSatisfy(Self.validFeatureName) else {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        let negotiated = HyphaAdminBrokerCapabilities(
            contractVersion: decoded.contractVersion,
            features: Set(decoded.features)
        )
        capabilities = negotiated
        return negotiated
    }

    public func snapshot() async throws -> MatrixAdminSnapshot {
        let token = try activeToken()
        let response = try await send(
            method: "GET",
            path: "/_hypha/admin/v1/snapshot",
            body: nil,
            authorization: token
        )
        guard response.statusCode == 200 else {
            throw operationError(response.statusCode)
        }
        let decoded: SnapshotResponse = try decodeJSON(response)
        guard decoded.users.count <= Self.maximumCollectionCount,
              decoded.rooms.count <= Self.maximumCollectionCount,
              decoded.users.allSatisfy({ Self.validUserID($0.userID) }),
              decoded.rooms.allSatisfy({ Self.validRoomID($0.roomID) && $0.joinedMemberCount >= 0 }) else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        return MatrixAdminSnapshot(
            users: decoded.users.map {
                MatrixAdminUserSummary(
                    userID: $0.userID,
                    isAdministrator: $0.isAdministrator,
                    isDeactivated: $0.isDeactivated,
                    isGuest: $0.isGuest,
                    userType: $0.userType
                )
            },
            rooms: decoded.rooms.map {
                MatrixAdminRoomSummary(
                    roomID: $0.roomID,
                    name: $0.name.isEmpty ? $0.roomID : $0.name,
                    joinedMemberCount: $0.joinedMemberCount
                )
            }
        )
    }

    public func createAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        guard Self.validLocalpart(localpart), Self.validPassword(temporaryPassword) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "POST",
            path: "/_hypha/admin/v1/users",
            json: [
                "localpart": localpart,
                "temporary_password": temporaryPassword,
                "administrator": administrator,
            ]
        )
        try requireStatus(response, expected: 201)
        let user: UserResponse = try decodeJSON(response)
        guard Self.validUserID(user.userID),
              user.userID.hasPrefix("@\(localpart):"),
              user.isAdministrator == administrator,
              !user.isDeactivated else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        return Self.userSummary(user)
    }

    public func setAdministrator(
        userID: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        guard Self.validUserID(userID) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "PUT",
            path: "/_hypha/admin/v1/users/administrator",
            json: ["user_id": userID, "administrator": administrator]
        )
        try requireStatus(response, expected: 200)
        let user: UserResponse = try decodeJSON(response)
        guard user.userID == userID,
              user.isAdministrator == administrator,
              !user.isDeactivated else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        return Self.userSummary(user)
    }

    public func passwordResetRequests() async throws -> [MatrixPasswordResetRequest] {
        let response = try await authorizedRequest(
            method: "GET",
            path: "/_hypha/admin/v1/password-reset-requests",
            json: nil
        )
        try requireStatus(response, expected: 200)
        let decoded: [PasswordResetResponse] = try decodeJSON(response)
        guard decoded.count <= Self.maximumCollectionCount,
              decoded.allSatisfy({
            Self.validUserID($0.userID)
                && UUID(uuidString: $0.requestID) != nil
                && $0.requestedAtMilliseconds > 0
        }) else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        return decoded.map {
            MatrixPasswordResetRequest(
                userID: $0.userID,
                requestID: $0.requestID,
                requestedAtMilliseconds: $0.requestedAtMilliseconds
            )
        }
    }

    public func resetPassword(
        for request: MatrixPasswordResetRequest,
        temporaryPassword: String
    ) async throws {
        guard Self.validUserID(request.userID),
              UUID(uuidString: request.requestID) != nil,
              Self.validPassword(temporaryPassword) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "PUT",
            path: "/_hypha/admin/v1/users/password",
            json: [
                "user_id": request.userID,
                "request_id": request.requestID,
                "temporary_password": temporaryPassword,
            ]
        )
        try requireStatus(response, expected: 204)
    }

    public func createRoom(
        name: String,
        topic: String,
        asSpace: Bool,
        visibility: MatrixRoomVisibility
    ) async throws -> MatrixAdminRoomSummary {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              cleanName.count <= 255,
              topic.count <= 1_000,
              !topic.unicodeScalars.contains(where: {
                  $0.value < 0x20 && ![0x09, 0x0A, 0x0D].contains($0.value)
              }) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "POST",
            path: "/_hypha/admin/v1/rooms",
            json: [
                "name": cleanName,
                "topic": topic,
                "as_space": asSpace,
                "visibility": visibility == .public ? "public" : "invite_only",
            ]
        )
        try requireStatus(response, expected: 201)
        let room: RoomResponse = try decodeJSON(response)
        guard Self.validRoomID(room.roomID), room.joinedMemberCount >= 0 else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        return MatrixAdminRoomSummary(
            roomID: room.roomID,
            name: room.name.isEmpty ? room.roomID : room.name,
            joinedMemberCount: room.joinedMemberCount
        )
    }

    public func logoutAccount(userID: String) async throws {
        try await userOperation(path: "/_hypha/admin/v1/users/logout", userID: userID)
    }

    public func deactivateAccount(userID: String) async throws {
        try await userOperation(path: "/_hypha/admin/v1/users/deactivate", userID: userID)
    }

    public func purgeRoom(roomID: String) async throws {
        guard Self.validRoomID(roomID) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "POST",
            path: "/_hypha/admin/v1/rooms/purge",
            json: ["room_id": roomID]
        )
        try requireStatus(response, expected: 204)
    }

    public func rotateAdministrationSecret(to replacement: String) async throws {
        guard capabilities?.supportsSecretRotation == true,
              Self.validSecret(replacement) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response: MatrixAdminHTTPResponse
        do {
            response = try await authorizedRequest(
                method: "POST",
                path: "/_hypha/admin/v1/secret/rotate",
                json: [
                    "new_secret": replacement,
                    "confirmation": "rotate_admin_secret",
                ]
            )
        } catch {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.rotationOutcomeUnknown
        }
        guard response.statusCode == 204 else {
            throw operationError(response.statusCode)
        }
        guard response.body.isEmpty else {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        sessionToken = nil
        capabilities = nil
    }

    public func endSession() async throws {
        let token = try activeToken()
        defer {
            sessionToken = nil
            capabilities = nil
        }
        let response = try await send(
            method: "DELETE",
            path: "/_hypha/admin/v1/session",
            body: nil,
            authorization: token
        )
        guard response.statusCode == 204 else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw HyphaAdminBrokerError.sessionExpired
            }
            throw mappedServerError(response.statusCode)
        }
    }

    private func activeToken() throws -> String {
        guard let sessionToken else {
            throw HyphaAdminBrokerError.sessionExpired
        }
        return sessionToken
    }

    private func authorizedRequest(
        method: String,
        path: String,
        json: [String: Any]?
    ) async throws -> MatrixAdminHTTPResponse {
        let body: Data?
        if let json {
            do {
                body = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            } catch {
                throw HyphaAdminBrokerError.invalidInput
            }
        } else {
            body = nil
        }
        return try await send(
            method: method,
            path: path,
            body: body,
            authorization: activeToken()
        )
    }

    private func userOperation(path: String, userID: String) async throws {
        guard Self.validUserID(userID) else {
            throw HyphaAdminBrokerError.invalidInput
        }
        let response = try await authorizedRequest(
            method: "POST",
            path: path,
            json: ["user_id": userID]
        )
        try requireStatus(response, expected: 204)
    }

    private func requireStatus(
        _ response: MatrixAdminHTTPResponse,
        expected: Int
    ) throws {
        guard response.statusCode == expected else {
            throw operationError(response.statusCode)
        }
        guard expected != 204 || response.body.isEmpty else {
            sessionToken = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
    }

    private func operationError(_ statusCode: Int) -> HyphaAdminBrokerError {
        if statusCode == 401 || statusCode == 403 {
            sessionToken = nil
            capabilities = nil
            return .sessionExpired
        }
        return mappedServerError(statusCode)
    }

    private func send(
        method: String,
        path: String,
        body: Data?,
        authorization: String?
    ) async throws -> MatrixAdminHTTPResponse {
        guard var components = URLComponents(url: homeserver, resolvingAgainstBaseURL: false) else {
            throw HyphaAdminBrokerError.invalidConfiguration
        }
        components.percentEncodedPath = path
        guard let url = components.url else {
            throw HyphaAdminBrokerError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let authorization {
            request.setValue("Bearer \(authorization)", forHTTPHeaderField: "Authorization")
        }
        let response: MatrixAdminHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as HyphaAdminBrokerError {
            throw error
        } catch {
            throw HyphaAdminBrokerError.offline
        }
        guard Self.sameOrigin(url, response.responseURL) else {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        guard response.body.count <= Self.maximumResponseBytes else {
            if authorization != nil {
                sessionToken = nil
                capabilities = nil
            }
            throw HyphaAdminBrokerError.invalidResponse
        }
        return response
    }

    private func decodeJSON<Value: Decodable>(_ response: MatrixAdminHTTPResponse) throws -> Value {
        guard !response.body.isEmpty,
              response.body.count <= Self.maximumResponseBytes,
              response.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(Value.self, from: response.body)
        } catch {
            sessionToken = nil
            capabilities = nil
            throw HyphaAdminBrokerError.invalidResponse
        }
    }

    private func mappedServerError(_ statusCode: Int) -> HyphaAdminBrokerError {
        switch statusCode {
        case 400, 404, 405, 409, 413, 415, 422:
            return .serverRejected
        case 429:
            return .rateLimited
        default:
            return .invalidResponse
        }
    }

    private static func validHomeserver(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            return false
        }
        return true
    }

    private static func validSecret(_ secret: String) -> Bool {
        guard let bytes = secret.data(using: .utf8),
              (32...512).contains(bytes.count) else {
            return false
        }
        return !secret.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    private static func validToken(_ token: String) -> Bool {
        guard let bytes = token.data(using: .ascii),
              (32...128).contains(bytes.count) else {
            return false
        }
        return bytes.allSatisfy {
            (0x30...0x39).contains($0)
                || (0x41...0x5A).contains($0)
                || (0x61...0x7A).contains($0)
                || $0 == 0x2D
                || $0 == 0x5F
        }
    }

    private static func validFeatureName(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 64
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_").contains($0)
            }
    }

    private static func validUserID(_ value: String) -> Bool {
        validMatrixID(value, sigil: "@")
    }

    private static func validLocalpart(_ value: String) -> Bool {
        !value.isEmpty
            && value.count <= 255
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._=-").contains($0)
            }
    }

    private static func validPassword(_ value: String) -> Bool {
        guard let bytes = value.data(using: .utf8), (12...512).contains(bytes.count) else {
            return false
        }
        return !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F }
    }

    private static func userSummary(_ user: UserResponse) -> MatrixAdminUserSummary {
        MatrixAdminUserSummary(
            userID: user.userID,
            isAdministrator: user.isAdministrator,
            isDeactivated: user.isDeactivated,
            isGuest: user.isGuest,
            userType: user.userType
        )
    }

    private static func validRoomID(_ value: String) -> Bool {
        validMatrixID(value, sigil: "!")
    }

    private static func validMatrixID(_ value: String, sigil: Character) -> Bool {
        guard value.first == sigil,
              value.count <= 512,
              value.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }),
              let separator = value.firstIndex(of: ":"),
              separator > value.index(after: value.startIndex),
              value.index(after: separator) < value.endIndex else {
            return false
        }
        return true
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && lhs.port == rhs.port
    }
}
