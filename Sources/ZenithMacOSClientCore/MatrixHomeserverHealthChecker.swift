import Foundation

public enum MatrixHomeserverConnectionError: Error, Equatable, Sendable {
    case invalidURL
    case insecureTransport
    case unreachable
    case httpStatus(Int)
    case invalidMatrixResponse
}

extension MatrixHomeserverConnectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid Matrix homeserver URL."
        case .insecureTransport:
            return "Remote homeservers must use HTTPS."
        case .unreachable:
            return "The homeserver could not be reached."
        case let .httpStatus(status):
            return "The homeserver health check returned HTTP \(status)."
        case .invalidMatrixResponse:
            return "The server did not return a valid Matrix client versions response."
        }
    }
}

public struct MatrixHomeserverHealthChecker: Sendable {
    public typealias Request = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let request: Request

    public init() {
        self.request = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw MatrixHomeserverConnectionError.invalidMatrixResponse
            }
            return (data, httpResponse)
        }
    }

    public init(request: @escaping Request) {
        self.request = request
    }

    public func connect(to input: String) async throws -> MatrixProductConfiguration {
        let homeserver = try Self.normalizedHomeserver(from: input)
        let versionsURL = homeserver.appendingPathComponent("_matrix/client/versions")
        var urlRequest = URLRequest(url: versionsURL, timeoutInterval: 10)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await request(urlRequest)
        } catch {
            throw MatrixHomeserverConnectionError.unreachable
        }

        guard (200..<300).contains(response.statusCode) else {
            throw MatrixHomeserverConnectionError.httpStatus(response.statusCode)
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let versions = object["versions"] as? [String],
            !versions.isEmpty
        else {
            throw MatrixHomeserverConnectionError.invalidMatrixResponse
        }

        return MatrixProductConfiguration(homeserver: homeserver)
    }

    public static func normalizedHomeserver(from input: String) throws -> URL {
        var candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { throw MatrixHomeserverConnectionError.invalidURL }
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw MatrixHomeserverConnectionError.invalidURL
        }

        let loopbackHosts = ["localhost", "127.0.0.1", "::1"]
        guard scheme == "https" || (scheme == "http" && loopbackHosts.contains(host.lowercased())) else {
            throw MatrixHomeserverConnectionError.insecureTransport
        }

        components.scheme = scheme
        components.host = host.lowercased()
        if components.path == "/" {
            components.path = ""
        } else {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }

        guard let url = components.url else {
            throw MatrixHomeserverConnectionError.invalidURL
        }
        return url
    }
}
