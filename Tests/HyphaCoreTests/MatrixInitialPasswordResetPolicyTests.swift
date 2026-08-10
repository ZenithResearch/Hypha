import XCTest
@testable import HyphaCore

final class MatrixInitialPasswordResetPolicyTests: XCTestCase {
    func testPendingServerResetRequestRequiresImmediateReset() {
        XCTAssertTrue(
            MatrixInitialPasswordResetPolicy.requiresReset(
                serverRequestID: "request-2",
                completedRequestID: nil,
                authorityQuerySucceeded: true
            )
        )
    }

    func testCompletionSuppressesOnlyTheExactServerResetRequest() {
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(
                serverRequestID: "request-1",
                completedRequestID: "request-1",
                authorityQuerySucceeded: true
            )
        )
        XCTAssertTrue(
            MatrixInitialPasswordResetPolicy.requiresReset(
                serverRequestID: "request-2",
                completedRequestID: "request-1",
                authorityQuerySucceeded: true
            )
        )
    }

    func testNoServerResetRequestDoesNotInferTemporaryPassword() {
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(
                serverRequestID: nil,
                completedRequestID: nil,
                authorityQuerySucceeded: true
            )
        )
    }

    func testUnavailableResetAuthorityFailsClosed() {
        XCTAssertTrue(
            MatrixInitialPasswordResetPolicy.requiresReset(
                serverRequestID: nil,
                completedRequestID: nil,
                authorityQuerySucceeded: false
            )
        )
    }

    func testPendingResetMigrationUnionsLegacyAndCurrentAccounts() {
        XCTAssertEqual(
            MatrixPasswordResetPersistencePolicy.mergedPendingAccountKeys(
                current: ["current", "shared"],
                legacy: ["legacy", "shared"]
            ),
            ["current", "legacy", "shared"]
        )
    }

    func testCompletionPersistenceIsScopedToAccountAndRequest() {
        XCTAssertEqual(
            MatrixPasswordResetPersistencePolicy.recordingCompletion(
                accountKey: "alice",
                requestID: "request-2",
                in: ["alice": "request-1", "bob": "request-9"]
            ),
            ["alice": "request-2", "bob": "request-9"]
        )
    }

    func testPasswordLoginNormalizesLocalUsernamesAgainstTheActiveHomeserver() {
        XCTAssertEqual(
            MatrixPasswordLoginPolicy.normalizeUsername(" banana ", activeServerName: "synapse.zenith-research.ca"),
            "@banana:synapse.zenith-research.ca"
        )
        XCTAssertEqual(
            MatrixPasswordLoginPolicy.normalizeUsername("@banana", activeServerName: "synapse.zenith-research.ca"),
            "@banana:synapse.zenith-research.ca"
        )
        XCTAssertEqual(
            MatrixPasswordLoginPolicy.normalizeUsername("@banana:synapse.zenith-research.ca", activeServerName: "synapse.zenith-research.ca"),
            "@banana:synapse.zenith-research.ca"
        )
        XCTAssertNil(MatrixPasswordLoginPolicy.normalizeUsername("bad/name", activeServerName: "synapse.zenith-research.ca"))
        XCTAssertNil(MatrixPasswordLoginPolicy.normalizeUsername("@banana:remote.example", activeServerName: "synapse.zenith-research.ca"))
    }
}
