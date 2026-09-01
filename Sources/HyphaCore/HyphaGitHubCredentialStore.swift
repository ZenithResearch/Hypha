import Foundation

public struct HyphaGitHubCredential: Equatable, Sendable {
    public let login: String
    public let token: String

    public init(login: String, token: String) {
        self.login = login
        self.token = token
    }
}

public enum HyphaGitHubCredentialStoreError: Error, Equatable, Sendable {
    case invalidCredential
    case persistenceFailed
}

public protocol HyphaGitHubCredentialStore: Sendable {
    func credential() throws -> HyphaGitHubCredential?
    func save(_ credential: HyphaGitHubCredential) throws
    func delete() throws
}

public final class HyphaGitHubKeychainCredentialStore: HyphaGitHubCredentialStore, @unchecked Sendable {
    private struct Metadata: Codable, Equatable {
        let login: String
    }

    private static let service = "Hypha"
    private static let account = "github-token:global"
    private let storage: any HyphaPasswordStorage

    public convenience init() {
        self.init(storage: SecurityHyphaPasswordStorage())
    }

    init(storage: any HyphaPasswordStorage) {
        self.storage = storage
    }

    public func credential() throws -> HyphaGitHubCredential? {
        guard let tokenData = try storage.readSecret(
            service: Self.service,
            account: Self.account
        ) else { return nil }
        guard let token = String(data: tokenData, encoding: .utf8),
              let metadataData = try storage.itemMetadata(
                service: Self.service,
                accountPrefix: Self.account
              ).first,
              let metadata = try? JSONDecoder().decode(Metadata.self, from: metadataData),
              Self.valid(login: metadata.login, token: token) else {
            throw HyphaGitHubCredentialStoreError.persistenceFailed
        }
        return HyphaGitHubCredential(login: metadata.login, token: token)
    }

    public func save(_ credential: HyphaGitHubCredential) throws {
        guard Self.valid(login: credential.login, token: credential.token) else {
            throw HyphaGitHubCredentialStoreError.invalidCredential
        }
        let metadata: Data
        do {
            metadata = try JSONEncoder().encode(Metadata(login: credential.login))
        } catch {
            throw HyphaGitHubCredentialStoreError.persistenceFailed
        }
        do {
            try storage.writeSecret(
                Data(credential.token.utf8),
                service: Self.service,
                account: Self.account,
                label: "Hypha — GitHub",
                description: "Global GitHub repository access for \(credential.login)",
                metadata: metadata
            )
        } catch {
            throw HyphaGitHubCredentialStoreError.persistenceFailed
        }
    }

    public func delete() throws {
        do {
            try storage.delete(service: Self.service, account: Self.account)
        } catch {
            throw HyphaGitHubCredentialStoreError.persistenceFailed
        }
    }

    private static func valid(login: String, token: String) -> Bool {
        login == login.trimmingCharacters(in: .whitespacesAndNewlines)
            && !login.isEmpty
            && login.utf8.count <= 100
            && !login.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && token == token.trimmingCharacters(in: .whitespacesAndNewlines)
            && !token.isEmpty
            && token.utf8.count <= 4_096
            && !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
