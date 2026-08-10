import Combine
import Foundation
import HyphaCore

@MainActor
final class HyphaGitHubConnectionModel: ObservableObject {
    @Published var tokenInput = ""
    @Published private(set) var accountLogin: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var statusIsError = false
    @Published private(set) var isConnecting = false

    private let client: HyphaGitHubRepositoryAccessClient
    private var sessionToken: String?

    init(client: HyphaGitHubRepositoryAccessClient = HyphaGitHubRepositoryAccessClient()) {
        self.client = client
    }

    var isConnected: Bool {
        accountLogin != nil && sessionToken != nil
    }

    func connect() {
        let token = tokenInput
        tokenInput = ""
        statusMessage = nil
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                let account = try await client.connect(token: token)
                sessionToken = token
                accountLogin = account.login
                statusMessage = "Connected to GitHub as \(account.login) for this Hypha session."
                statusIsError = false
            } catch let error as HyphaGitHubRepositoryAccessError {
                sessionToken = nil
                accountLogin = nil
                statusMessage = Self.message(for: error)
                statusIsError = true
            } catch {
                sessionToken = nil
                accountLogin = nil
                statusMessage = "GitHub could not be connected right now."
                statusIsError = true
            }
        }
    }

    func disconnect() {
        tokenInput = ""
        sessionToken = nil
        accountLogin = nil
        statusMessage = "GitHub disconnected from this Hypha session."
        statusIsError = false
    }

    func verify(remote: String) async throws -> HyphaGitHubRepositoryAccess {
        guard let sessionToken else {
            throw HyphaGitHubRepositoryAccessError.invalidToken
        }
        return try await client.verify(remote: remote, token: sessionToken)
    }

    static func message(for error: HyphaGitHubRepositoryAccessError) -> String {
        switch error {
        case .invalidRemote:
            "Enter a valid github.com repository URL."
        case .invalidToken:
            "Enter a valid GitHub personal access token."
        case .authenticationFailed:
            "GitHub did not accept this token."
        case .repositoryUnavailable:
            "The repository was not found or this account cannot read it."
        case .serviceUnavailable:
            "GitHub could not be reached right now."
        case .invalidResponse:
            "GitHub returned an invalid account response."
        }
    }
}
