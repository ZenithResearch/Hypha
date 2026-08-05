import XCTest
@testable import HyphaCore

final class MatrixInitialPasswordResetPolicyTests: XCTestCase {
    func testFirstManualPasswordLoginRequiresImmediateReset() {
        XCTAssertTrue(
            MatrixInitialPasswordResetPolicy.requiresReset(
                authenticationMethod: .manualPassword,
                hadExistingSession: false
            )
        )
    }

    func testExistingSessionAndPermanentRegistrationPasswordsDoNotRequireReset() {
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(
                authenticationMethod: .manualPassword,
                hadExistingSession: true
            )
        )
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(
                authenticationMethod: .inviteTokenRegistration,
                hadExistingSession: false
            )
        )
        XCTAssertFalse(
            MatrixInitialPasswordResetPolicy.requiresReset(
                authenticationMethod: .savedCredential,
                hadExistingSession: false
            )
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
