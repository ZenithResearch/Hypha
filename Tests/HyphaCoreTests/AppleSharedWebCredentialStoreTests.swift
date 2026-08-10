import XCTest
@testable import HyphaCore

final class AppleSharedWebCredentialStoreTests: XCTestCase {
    func testSaveForwardsValidatedDomainUsernameAndPassword() async throws {
        let recorder = SharedCredentialRecorder()
        let store = AppleSharedWebCredentialStore { domain, username, password, completion in
            recorder.add(domain: domain, username: username, password: password, completion: completion)
        }

        try await store.save(
            password: "strong-password",
            username: "@beaver:synapse.zenith-research.ca",
            domain: "synapse.zenith-research.ca"
        )

        let request = await recorder.request
        XCTAssertEqual(request?.domain, "synapse.zenith-research.ca")
        XCTAssertEqual(request?.username, "@beaver:synapse.zenith-research.ca")
        XCTAssertEqual(request?.password, "strong-password")
    }

    func testInvalidInputFailsBeforeApplePasswordsRequest() async {
        let recorder = SharedCredentialRecorder()
        let store = AppleSharedWebCredentialStore { domain, username, password, completion in
            recorder.add(domain: domain, username: username, password: password, completion: completion)
        }

        do {
            try await store.save(password: "password", username: "beaver", domain: "https://synapse.zenith-research.ca/path")
            XCTFail("Expected validation failure")
        } catch {
            XCTAssertEqual(error as? AppleSharedWebCredentialError, .invalidInput)
        }
        let request = await recorder.request
        XCTAssertNil(request)
    }

    func testApplePasswordsFailureRemainsDistinctFromMatrixAuthentication() async {
        let store = AppleSharedWebCredentialStore { _, _, _, completion in
            completion(SharedCredentialTestError.rejected)
        }

        do {
            try await store.save(password: "password", username: "beaver", domain: "synapse.zenith-research.ca")
            XCTFail("Expected Apple Passwords failure")
        } catch {
            XCTAssertEqual(error as? AppleSharedWebCredentialError, .saveFailed)
        }
    }

    func testRecoveryKeyIsSavedAsADistinctApplePasswordsEntry() async throws {
        let recorder = SharedCredentialRecorder()
        let store: any HyphaSharedWebCredentialStore = AppleSharedWebCredentialStore {
            domain, username, password, completion in
            recorder.add(domain: domain, username: username, password: password, completion: completion)
        }

        try await store.saveRecoveryKey(
            "not-a-real-recovery-key",
            userID: "@beaver:synapse.zenith-research.ca",
            domain: "synapse.zenith-research.ca"
        )

        let request = await recorder.request
        XCTAssertEqual(request?.domain, "synapse.zenith-research.ca")
        XCTAssertEqual(
            request?.username,
            "@beaver:synapse.zenith-research.ca — Hypha Matrix recovery key"
        )
        XCTAssertEqual(request?.password, "not-a-real-recovery-key")
    }
}

private enum SharedCredentialTestError: Error {
    case rejected
}

private actor SharedCredentialRecorder {
    struct Request: Equatable {
        let domain: String
        let username: String
        let password: String
    }

    private(set) var request: Request?

    nonisolated func add(
        domain: String,
        username: String,
        password: String,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        Task {
            await record(Request(domain: domain, username: username, password: password))
            completion(nil)
        }
    }

    private func record(_ request: Request) {
        self.request = request
    }
}
