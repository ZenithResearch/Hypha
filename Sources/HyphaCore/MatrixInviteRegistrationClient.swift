import Foundation

public enum MatrixRegistrationAvailability: Equatable, Sendable {
    case unavailable
    case inviteToken
}

public enum MatrixUnsupportedRegistrationReason: Equatable, Sendable {
    case singleSignOn
    case oauth
    case captcha
    case uiaa
}

public enum MatrixRegistrationCapabilityFailure: Equatable, Sendable {
    case redirectRejected
    case originMismatch
    case invalidResponse
    case transportFailure
    case serverRejected
}

public enum MatrixRegistrationCapability: Equatable, Sendable {
    case inviteToken(stages: [String])
    case unsupported(MatrixUnsupportedRegistrationReason)
    case unavailable(MatrixRegistrationCapabilityFailure)
}

public enum MatrixAccountRegistrationError: Error, Equatable, Sendable {
    case unavailable
    case invalidInput
    case invalidToken
    case unsupportedAuthentication
    case unsupportedSingleSignOn
    case unsupportedOAuth
    case captchaRequired
    case redirectRejected
    case originMismatch
    case invalidResponse
    case unexpectedServerSession
    case identityMismatch
    case transportFailure
    case serverRejected

    public var stableCode: String {
        switch self {
        case .unavailable: "registration_unavailable"
        case .invalidInput: "registration_invalid_input"
        case .invalidToken: "registration_invalid_token"
        case .unsupportedAuthentication: "registration_uiaa_unsupported"
        case .unsupportedSingleSignOn: "registration_sso_unsupported"
        case .unsupportedOAuth: "registration_oauth_unsupported"
        case .captchaRequired: "registration_captcha_unsupported"
        case .redirectRejected: "registration_redirect_rejected"
        case .originMismatch: "registration_origin_mismatch"
        case .invalidResponse: "registration_invalid_response"
        case .unexpectedServerSession: "registration_unexpected_server_session"
        case .identityMismatch: "registration_identity_mismatch"
        case .transportFailure: "registration_transport_failure"
        case .serverRejected: "registration_server_rejected"
        }
    }
}

public struct MatrixAccountRegistrationRequest: Sendable {
    public let username: String
    public let password: String
    public let registrationToken: String

    public init(username: String, password: String, registrationToken: String) {
        self.username = username
        self.password = password
        self.registrationToken = registrationToken
    }
}

public struct MatrixAccountRegistrationResult: Equatable, Sendable {
    public let userID: String

    public init(userID: String) {
        self.userID = userID
    }
}

public protocol MatrixRegistrationTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public actor MatrixInviteRegistrationClient {
    private let endpoint: URL
    private let transport: any MatrixRegistrationTransport

    public init(homeserver: URL, transport: any MatrixRegistrationTransport = MatrixURLSessionRegistrationTransport()) {
        self.endpoint = homeserver
            .appendingPathComponent("_matrix")
            .appendingPathComponent("client")
            .appendingPathComponent("v3")
            .appendingPathComponent("register")
        self.transport = transport
    }

    public func availability() async -> MatrixRegistrationAvailability {
        if case .inviteToken = await capability() { return .inviteToken }
        return .unavailable
    }

    public func capability() async -> MatrixRegistrationCapability {
        do {
            let response = try await send(body: ["inhibit_login": true])
            guard response.http.statusCode == 401 else { return .unavailable(.serverRejected) }
            let challenge: UIAChallenge
            do { challenge = try decodeChallenge(response.data) }
            catch { return .unavailable(.invalidResponse) }
            if let flow = challenge.inviteTokenOnlyFlow {
                return .inviteToken(stages: flow.stages)
            }
            return .unsupported(challenge.unsupportedReason)
        } catch let error as MatrixAccountRegistrationError {
            switch error {
            case .redirectRejected: return .unavailable(.redirectRejected)
            case .originMismatch: return .unavailable(.originMismatch)
            case .invalidResponse: return .unavailable(.invalidResponse)
            case .transportFailure: return .unavailable(.transportFailure)
            default: return .unavailable(.serverRejected)
            }
        } catch {
            return .unavailable(.transportFailure)
        }
    }

    public func register(_ request: MatrixAccountRegistrationRequest) async throws -> MatrixAccountRegistrationResult {
        let username = request.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty,
              !request.password.isEmpty,
              !request.registrationToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MatrixAccountRegistrationError.invalidInput
        }

        let baseBody: [String: Any] = [
            "username": username,
            "password": request.password,
            "inhibit_login": true
        ]
        var response: (data: Data, http: HTTPURLResponse)
        do {
            response = try await send(body: baseBody)
        } catch let error as MatrixAccountRegistrationError {
            throw error
        } catch {
            throw MatrixAccountRegistrationError.transportFailure
        }
        if response.http.statusCode == 200 {
            return try reconcileSuccessfulRegistration(response.data, expectedUsername: username)
        }
        guard response.http.statusCode == 401 else {
            throw mapFailure(statusCode: response.http.statusCode, data: response.data)
        }

        let challenge: UIAChallenge
        do {
            challenge = try decodeChallenge(response.data)
        } catch {
            throw MatrixAccountRegistrationError.invalidResponse
        }
        guard let flow = challenge.inviteTokenOnlyFlow else {
            throw challenge.unsupportedRegistrationError
        }

        let completed = Set(challenge.completed ?? [])
        for stage in flow.stages where !completed.contains(stage) {
            var stageBody = baseBody
            switch stage {
            case "m.login.registration_token":
                stageBody["auth"] = [
                    "type": stage,
                    "session": challenge.session,
                    "token": request.registrationToken
                ]
            case "m.login.dummy":
                stageBody["auth"] = [
                    "type": stage,
                    "session": challenge.session
                ]
            default:
                throw MatrixAccountRegistrationError.unsupportedAuthentication
            }

            do {
                response = try await send(body: stageBody)
            } catch let error as MatrixAccountRegistrationError {
                throw error
            } catch {
                throw MatrixAccountRegistrationError.transportFailure
            }
            if response.http.statusCode == 200 {
                return try reconcileSuccessfulRegistration(response.data, expectedUsername: username)
            }
            guard response.http.statusCode == 401 else {
                throw mapFailure(statusCode: response.http.statusCode, data: response.data)
            }
            guard let continuation = try? decodeChallenge(response.data),
                  continuation.session == challenge.session,
                  continuation.inviteTokenOnlyFlow?.stages == flow.stages,
                  Set(continuation.completed ?? []).contains(stage) else {
                throw MatrixAccountRegistrationError.invalidResponse
            }
        }
        throw MatrixAccountRegistrationError.serverRejected
    }

    private func reconcileSuccessfulRegistration(
        _ data: Data,
        expectedUsername: String
    ) throws -> MatrixAccountRegistrationResult {
        guard let response = try? JSONDecoder().decode(MatrixRegistrationResponse.self, from: data) else {
            throw MatrixAccountRegistrationError.invalidResponse
        }
        guard response.accessToken == nil, response.deviceID == nil else {
            throw MatrixAccountRegistrationError.unexpectedServerSession
        }
        guard response.userID.first == "@",
              let separator = response.userID.firstIndex(of: ":"),
              String(response.userID[response.userID.index(after: response.userID.startIndex)..<separator]) == expectedUsername else {
            throw MatrixAccountRegistrationError.identityMismatch
        }
        return MatrixAccountRegistrationResult(userID: response.userID)
    }

    private func send(body: [String: Any]) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await transport.send(request)
        guard !(300...399).contains(response.statusCode) else {
            throw MatrixAccountRegistrationError.redirectRejected
        }
        guard Self.sameOrigin(response.url, endpoint) else {
            throw MatrixAccountRegistrationError.originMismatch
        }
        return (data, response)
    }

    private func decodeChallenge(_ data: Data) throws -> UIAChallenge {
        try JSONDecoder().decode(UIAChallenge.self, from: data)
    }

    private func mapFailure(statusCode: Int, data: Data) -> MatrixAccountRegistrationError {
        if statusCode == 403 {
            let matrixError = try? JSONDecoder().decode(MatrixErrorBody.self, from: data)
            if matrixError?.errcode == "M_FORBIDDEN" { return .invalidToken }
        }
        if statusCode == 400 { return .invalidInput }
        if statusCode == 404 || statusCode == 405 { return .unavailable }
        return .serverRejected
    }

    private static func sameOrigin(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else { return false }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

private struct UIAChallenge: Decodable {
    struct Flow: Decodable { let stages: [String] }
    let session: String
    let flows: [Flow]
    let completed: [String]?

    var inviteTokenOnlyFlow: Flow? {
        flows
            .filter { flow in
                flow.stages.contains("m.login.registration_token")
                    && flow.stages.allSatisfy { $0 == "m.login.registration_token" || $0 == "m.login.dummy" }
            }
            .sorted {
                if $0.stages.count != $1.stages.count { return $0.stages.count < $1.stages.count }
                return $0.stages.joined(separator: "\u{0}") < $1.stages.joined(separator: "\u{0}")
            }
            .first
    }

    var unsupportedReason: MatrixUnsupportedRegistrationReason {
        let stages = Set(flows.flatMap(\.stages))
        if stages.contains("m.login.recaptcha") { return .captcha }
        if stages.contains("m.login.oauth2") { return .oauth }
        if stages.contains("m.login.sso") { return .singleSignOn }
        return .uiaa
    }

    var unsupportedRegistrationError: MatrixAccountRegistrationError {
        switch unsupportedReason {
        case .singleSignOn: .unsupportedSingleSignOn
        case .oauth: .unsupportedOAuth
        case .captcha: .captchaRequired
        case .uiaa: .unsupportedAuthentication
        }
    }
}

private struct MatrixErrorBody: Decodable {
    let errcode: String?
}

private struct MatrixRegistrationResponse: Decodable {
    let userID: String
    let accessToken: String?
    let deviceID: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accessToken = "access_token"
        case deviceID = "device_id"
    }
}

public actor MatrixURLSessionRegistrationTransport: MatrixRegistrationTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(
            configuration: configuration,
            delegate: MatrixNoRedirectSessionDelegate(),
            delegateQueue: nil
        )
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MatrixAccountRegistrationError.transportFailure
        }
        return (data, http)
    }
}

private final class MatrixNoRedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
