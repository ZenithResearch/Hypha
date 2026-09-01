import Foundation

public enum HyphaGitHubRepositoryAccessError: Error, Equatable, Sendable {
    case invalidRemote
    case invalidToken
    case authenticationFailed
    case repositoryUnavailable
    case serviceUnavailable
    case invalidResponse
}

public struct HyphaGitHubRepositoryAccess: Equatable, Sendable {
    public let fullName: String
    public let isPrivate: Bool

    public init(fullName: String, isPrivate: Bool) {
        self.fullName = fullName
        self.isPrivate = isPrivate
    }
}

public struct HyphaGitHubAccount: Equatable, Sendable {
    public let login: String

    public init(login: String) {
        self.login = login
    }
}

public protocol HyphaGitHubRepositoryAccessTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct HyphaGitHubRepositoryAccessClient: Sendable {
    private struct AccountResponse: Decodable {
        let login: String
    }

    private struct RepositoryResponse: Decodable {
        let fullName: String
        let isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case isPrivate = "private"
        }
    }

    private let transport: any HyphaGitHubRepositoryAccessTransport

    public init(transport: any HyphaGitHubRepositoryAccessTransport = HyphaGitHubURLSessionTransport()) {
        self.transport = transport
    }

    public func connect(token: String) async throws -> HyphaGitHubAccount {
        try Self.validateToken(token)
        guard let url = URL(string: "https://api.github.com/user") else {
            throw HyphaGitHubRepositoryAccessError.invalidResponse
        }
        let (data, response) = try await send(Self.authorizedRequest(url: url, token: token))
        switch response.statusCode {
        case 200:
            guard data.count <= 64 * 1_024,
                  let account = try? JSONDecoder().decode(AccountResponse.self, from: data),
                  !account.login.isEmpty else {
                throw HyphaGitHubRepositoryAccessError.invalidResponse
            }
            return HyphaGitHubAccount(login: account.login)
        case 401, 403:
            throw HyphaGitHubRepositoryAccessError.authenticationFailed
        default:
            throw HyphaGitHubRepositoryAccessError.serviceUnavailable
        }
    }

    public func verify(remote: String, token: String) async throws -> HyphaGitHubRepositoryAccess {
        let reference = try Self.repositoryReference(remote)
        try Self.validateToken(token)

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/repos/\(reference.owner)/\(reference.repository)"
        guard let url = components.url else { throw HyphaGitHubRepositoryAccessError.invalidRemote }

        let (data, response) = try await send(Self.authorizedRequest(url: url, token: token))
        switch response.statusCode {
        case 200:
            guard data.count <= 64 * 1_024,
                  let repository = try? JSONDecoder().decode(RepositoryResponse.self, from: data),
                  !repository.fullName.isEmpty else {
                throw HyphaGitHubRepositoryAccessError.invalidResponse
            }
            return HyphaGitHubRepositoryAccess(
                fullName: repository.fullName,
                isPrivate: repository.isPrivate
            )
        case 401, 403:
            throw HyphaGitHubRepositoryAccessError.authenticationFailed
        case 404:
            throw HyphaGitHubRepositoryAccessError.repositoryUnavailable
        default:
            throw HyphaGitHubRepositoryAccessError.serviceUnavailable
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as HyphaGitHubRepositoryAccessError {
            throw error
        } catch {
            throw HyphaGitHubRepositoryAccessError.serviceUnavailable
        }
    }

    private static func validateToken(_ token: String) throws {
        guard !token.isEmpty,
              token == token.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw HyphaGitHubRepositoryAccessError.invalidToken
        }
    }

    static func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    static func repositoryReference(_ remote: String) throws -> (owner: String, repository: String) {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String

        if value.hasPrefix("git@github.com:") {
            path = String(value.dropFirst("git@github.com:".count))
        } else if let url = URL(string: value),
                  url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "github.com",
                  url.user == nil,
                  url.query == nil,
                  url.fragment == nil {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if let url = URL(string: value),
                  url.scheme?.lowercased() == "ssh",
                  url.host?.lowercased() == "github.com",
                  url.query == nil,
                  url.fragment == nil {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            throw HyphaGitHubRepositoryAccessError.invalidRemote
        }

        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 2 else { throw HyphaGitHubRepositoryAccessError.invalidRemote }
        let owner = parts[0]
        var repository = parts[1]
        if repository.lowercased().hasSuffix(".git") {
            repository.removeLast(4)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !owner.isEmpty,
              !repository.isEmpty,
              owner.unicodeScalars.allSatisfy(allowed.contains),
              repository.unicodeScalars.allSatisfy(allowed.contains) else {
            throw HyphaGitHubRepositoryAccessError.invalidRemote
        }
        return (owner, repository)
    }
}

public actor HyphaGitHubURLSessionTransport: HyphaGitHubRepositoryAccessTransport {
    private let redirectDelegate: HyphaGitHubRedirectDelegate
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let delegate = HyphaGitHubRedirectDelegate()
        self.redirectDelegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme?.lowercased() == "https",
              response.url?.host?.lowercased() == "api.github.com" else {
            throw HyphaGitHubRepositoryAccessError.invalidResponse
        }
        return (data, response)
    }
}

private final class HyphaGitHubRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
