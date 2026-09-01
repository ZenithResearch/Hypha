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
    private let credentialStore: any HyphaGitHubCredentialStore
    private var sessionToken: String?

    init(
        client: HyphaGitHubRepositoryAccessClient = HyphaGitHubRepositoryAccessClient(),
        credentialStore: any HyphaGitHubCredentialStore = HyphaGitHubKeychainCredentialStore()
    ) {
        self.client = client
        self.credentialStore = credentialStore
        do {
            if let credential = try credentialStore.credential() {
                accountLogin = credential.login
                sessionToken = credential.token
            }
        } catch {
            accountLogin = nil
            sessionToken = nil
            statusMessage = "The saved GitHub connection could not be read. Connect again."
            statusIsError = true
        }
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
                try credentialStore.save(
                    HyphaGitHubCredential(login: account.login, token: token)
                )
                sessionToken = token
                accountLogin = account.login
                statusMessage = "Connected to GitHub as \(account.login). This device will reuse the connection."
                statusIsError = false
            } catch let error as HyphaGitHubRepositoryAccessError {
                sessionToken = nil
                accountLogin = nil
                statusMessage = Self.message(for: error)
                statusIsError = true
            } catch is HyphaGitHubCredentialStoreError {
                sessionToken = nil
                accountLogin = nil
                statusMessage = "GitHub approved the token, but Hypha could not save it securely."
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
        do {
            try credentialStore.delete()
        } catch {
            statusMessage = "Hypha could not remove the saved GitHub connection."
            statusIsError = true
            return
        }
        sessionToken = nil
        accountLogin = nil
        statusMessage = "GitHub disconnected from this device."
        statusIsError = false
    }

    func repositories() async throws -> [HyphaGitHubRepositoryChoice] {
        guard let sessionToken else {
            throw HyphaGitHubRepositoryAccessError.invalidToken
        }
        return try await client.repositories(token: sessionToken)
    }

    func verify(remote: String) async throws -> HyphaGitHubRepositoryAccess {
        guard let sessionToken else {
            throw HyphaGitHubRepositoryAccessError.invalidToken
        }
        return try await client.verify(remote: remote, token: sessionToken)
    }

    func credential() -> HyphaGitHubCredential? {
        guard let accountLogin, let sessionToken else { return nil }
        return HyphaGitHubCredential(login: accountLogin, token: sessionToken)
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
            "GitHub returned an invalid response."
        }
    }
}
