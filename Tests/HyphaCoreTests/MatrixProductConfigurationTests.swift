import XCTest
@testable import HyphaCore

final class MatrixProductConfigurationTests: XCTestCase {
    func testProductionUsesCanonicalHTTPSHomeserverAndNeverAllowsPlaintextFallback() {
        let configuration = MatrixProductConfiguration.production

        XCTAssertEqual(configuration.homeserver.scheme, "https")
        XCTAssertEqual(configuration.homeserver.host, "synapse.zenith-research.ca")
        XCTAssertFalse(configuration.allowsPlaintextFallback)
    }
}
