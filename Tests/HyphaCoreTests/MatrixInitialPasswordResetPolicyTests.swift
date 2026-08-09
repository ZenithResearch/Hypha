import XCTest
@testable import HyphaCore

final class MatrixInitialPasswordResetPolicyTests: XCTestCase {
    func testPendingServerResetRequestRequiresImmediateReset() {
        XCTAssertTrue(
            MatrixInitialPasswordResetPolicy.requiresReset(serverRequestPending: true)
        )
    }

    func testFirstLoginWithoutServerResetRequestDoesNotInferTemporaryPassword() {
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(serverRequestPending: false)
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
