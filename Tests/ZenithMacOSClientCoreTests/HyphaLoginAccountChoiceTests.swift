import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class HyphaLoginAccountChoiceTests: XCTestCase {
    func testSessionAndSavedCredentialForSameAccountBecomeOneChoiceWithTwoExplicitActions() {
        let session = makeSession(accountKey: "banana-key", userID: "@banana:example.org")
        let credential = HyphaMatrixCredentialDescriptor(
            id: "banana-key",
            username: "banana",
            homeserverURL: "https://example.org"
        )

        let choices = HyphaLoginAccountChoice.grouped(
            sessions: [session],
            credentials: [credential]
        )

        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices[0].id, "banana-key")
        XCTAssertEqual(choices[0].displayAccount, "@banana:example.org")
        XCTAssertEqual(choices[0].session, session)
        XCTAssertEqual(choices[0].credential, credential)
    }

    func testSessionOnlyAndCredentialOnlyAccountsRemainDistinctAndSorted() {
        let session = makeSession(accountKey: "peach-key", userID: "@peach:example.org")
        let credential = HyphaMatrixCredentialDescriptor(
            id: "banana-key",
            username: "banana",
            homeserverURL: "https://example.org"
        )

        let choices = HyphaLoginAccountChoice.grouped(
            sessions: [session],
            credentials: [credential]
        )

        XCTAssertEqual(choices.map(\.displayAccount), ["@peach:example.org", "banana"])
        XCTAssertNil(choices[0].credential)
        XCTAssertNil(choices[1].session)
    }

    private func makeSession(accountKey: String, userID: String) -> MatrixSDKSessionRecord {
        MatrixSDKSessionRecord(
            accessToken: "test-access-token",
            refreshToken: nil,
            userId: userID,
            deviceId: "TESTDEVICE",
            homeserverURL: "https://example.org",
            oauthData: nil,
            slidingSyncVersion: "native",
            accountKey: accountKey
        )
    }
}
