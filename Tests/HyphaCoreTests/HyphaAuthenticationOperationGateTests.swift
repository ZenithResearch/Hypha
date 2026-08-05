import XCTest
@testable import HyphaCore

final class HyphaAuthenticationOperationGateTests: XCTestCase {
    func testGateRejectsOverlappingAuthenticationUntilTheActiveOperationFinishes() {
        var gate = HyphaAuthenticationOperationGate()

        XCTAssertFalse(gate.isInFlight)
        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.isInFlight)
        XCTAssertFalse(gate.begin())

        gate.finish()

        XCTAssertFalse(gate.isInFlight)
        XCTAssertTrue(gate.begin())
    }
}
