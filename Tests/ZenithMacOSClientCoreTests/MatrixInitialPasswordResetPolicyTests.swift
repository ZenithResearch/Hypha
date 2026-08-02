import XCTest
@testable import ZenithMacOSClientCore

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
}
