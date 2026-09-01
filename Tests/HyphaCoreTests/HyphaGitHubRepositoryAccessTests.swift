import Foundation
import XCTest
@testable import HyphaCore

final class HyphaGitHubRepositoryAccessTests: XCTestCase {
    func testGitHubConnectionAuthenticatesTheGlobalAccountThroughUserEndpoint() async throws {
        let transport = RecordingGitHubTransport(
            statusCode: 200,
            body: Data(#"{"login":"banana"}"#.utf8)
        )
        let client = HyphaGitHubRepositoryAccessClient(transport: transport)

        let account = try await client.connect(token: "github-test-token")

        XCTAssertEqual(account.login, "banana")
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github-test-token")
    }

    func testPrivateRepositoryAccessUsesBoundedGitHubAPIRequest() async throws {
        let transport = RecordingGitHubTransport(
            statusCode: 200,
            body: Data(#"{"full_name":"ZenithResearch/Hypha","private":true}"#.utf8)
        )
        let client = HyphaGitHubRepositoryAccessClient(transport: transport)

        let result = try await client.verify(
            remote: "git@github.com:ZenithResearch/Hypha.git",
            token: "github-test-token"
        )

        XCTAssertEqual(result.fullName, "ZenithResearch/Hypha")
        XCTAssertTrue(result.isPrivate)
        let capturedRequest = await transport.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/ZenithResearch/Hypha")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer github-test-token")
        XCTAssertNil(request.url?.query)
    }

    func testGitHubRepositoryAccessRejectsNonGitHubOrInsecureRemotesBeforeNetwork() async {
        let transport = RecordingGitHubTransport(statusCode: 200, body: Data())
        let client = HyphaGitHubRepositoryAccessClient(transport: transport)

        for remote in [
            "http://github.com/owner/repo",
            "https://example.com/owner/repo",
            "https://github.com/owner",
        ] {
            do {
                _ = try await client.verify(remote: remote, token: "github-test-token")
                XCTFail("Expected remote rejection: \(remote)")
            } catch {
                XCTAssertEqual(error as? HyphaGitHubRepositoryAccessError, .invalidRemote)
            }
        }
        let capturedRequest = await transport.lastRequest()
        XCTAssertNil(capturedRequest)
    }

    func testGitHubRepositoryAccessRejectsEmptyWhitespaceAndControlBearingTokens() async {
        let transport = RecordingGitHubTransport(statusCode: 200, body: Data())
        let client = HyphaGitHubRepositoryAccessClient(transport: transport)

        for token in ["", " token", "token ", "token\nvalue"] {
            do {
                _ = try await client.verify(
                    remote: "https://github.com/owner/repo",
                    token: token
                )
                XCTFail("Expected token rejection")
            } catch {
                XCTAssertEqual(error as? HyphaGitHubRepositoryAccessError, .invalidToken)
            }
        }
        let capturedRequest = await transport.lastRequest()
        XCTAssertNil(capturedRequest)
    }

    func testGitHubRepositoryAccessMapsDeniedResponsesWithoutRawServerErrors() async {
        let transport = RecordingGitHubTransport(
            statusCode: 404,
            body: Data(#"{"message":"sensitive provider detail"}"#.utf8)
        )
        let client = HyphaGitHubRepositoryAccessClient(transport: transport)

        do {
            _ = try await client.verify(
                remote: "https://github.com/owner/private-repo",
                token: "github-test-token"
            )
            XCTFail("Expected inaccessible repository")
        } catch {
            XCTAssertEqual(error as? HyphaGitHubRepositoryAccessError, .repositoryUnavailable)
        }
    }

    func testGlobalGitHubCredentialRoundTripsWithSecretSeparatedFromMetadata() throws {
        let storage = RecordingGitHubPasswordStorage()
        let store = HyphaGitHubKeychainCredentialStore(storage: storage)
        let credential = HyphaGitHubCredential(login: "banana", token: "github-test-token")

        try store.save(credential)

        XCTAssertEqual(try store.credential(), credential)
        let metadata = try XCTUnwrap(storage.savedMetadata())
        let metadataText = try XCTUnwrap(String(data: metadata, encoding: .utf8))
        XCTAssertTrue(metadataText.contains("banana"))
        XCTAssertFalse(metadataText.contains("github-test-token"))
        XCTAssertEqual(storage.savedLabel(), "Hypha — GitHub")

        try store.delete()
        XCTAssertNil(try store.credential())
    }

    func testGlobalGitHubCredentialRejectsUnsafeValuesBeforeKeychainWrite() throws {
        let storage = RecordingGitHubPasswordStorage()
        let store = HyphaGitHubKeychainCredentialStore(storage: storage)

        for credential in [
            HyphaGitHubCredential(login: "", token: "token"),
            HyphaGitHubCredential(login: "banana", token: " token"),
            HyphaGitHubCredential(login: "banana", token: "token\nvalue"),
        ] {
            XCTAssertThrowsError(try store.save(credential)) { error in
                XCTAssertEqual(error as? HyphaGitHubCredentialStoreError, .invalidCredential)
            }
        }
        XCTAssertNil(storage.savedMetadata())
    }
}

private actor RecordingGitHubTransport: HyphaGitHubRepositoryAccessTransport {
    private let statusCode: Int
    private let body: Data
    private var request: URLRequest?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }

    func lastRequest() -> URLRequest? { request }
}

private final class RecordingGitHubPasswordStorage: HyphaPasswordStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: Data?
    private var metadata: Data?
    private var label: String?

    func readSecret(service: String, account: String) throws -> Data? {
        lock.withLock { secret }
    }

    func writeSecret(
        _ secret: Data,
        service: String,
        account: String,
        label: String,
        description: String,
        metadata: Data
    ) throws {
        lock.withLock {
            self.secret = secret
            self.metadata = metadata
            self.label = label
        }
    }

    func delete(service: String, account: String) throws {
        lock.withLock {
            secret = nil
            metadata = nil
            label = nil
        }
    }

    func itemMetadata(service: String, accountPrefix: String) throws -> [Data] {
        lock.withLock { metadata.map { [$0] } ?? [] }
    }

    func savedMetadata() -> Data? {
        lock.withLock { metadata }
    }

    func savedLabel() -> String? {
        lock.withLock { label }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
