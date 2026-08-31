import XCTest
@testable import HyphaCore

final class MatrixProductConfigurationTests: XCTestCase {
    func testEnvironmentProvidesDefaultHomeserver() throws {
        let configuration = try XCTUnwrap(MatrixProductConfiguration.defaultConfiguration(
            environment: [
                MatrixProductConfiguration.defaultHomeserverEnvironmentKey:
                    " https://matrix.example.org "
            ],
            bundleValue: nil
        ))

        XCTAssertEqual(configuration.homeserver.scheme, "https")
        XCTAssertEqual(configuration.homeserver.host, "matrix.example.org")
        XCTAssertFalse(configuration.allowsPlaintextFallback)
    }

    func testRuntimeEnvironmentOverridesPackagedDefault() throws {
        let configuration = try XCTUnwrap(MatrixProductConfiguration.defaultConfiguration(
            environment: [
                MatrixProductConfiguration.defaultHomeserverEnvironmentKey:
                    "https://runtime.example.org"
            ],
            bundleValue: "https://packaged.example.org"
        ))

        XCTAssertEqual(configuration.homeserver.host, "runtime.example.org")
    }

    func testPackagedDefaultIsUsedWhenEnvironmentIsAbsent() throws {
        let configuration = try XCTUnwrap(MatrixProductConfiguration.defaultConfiguration(
            environment: [:],
            bundleValue: "https://packaged.example.org"
        ))

        XCTAssertEqual(configuration.homeserver.host, "packaged.example.org")
        XCTAssertFalse(configuration.allowsPlaintextFallback)
    }

    func testMissingDefaultLeavesHomeserverUnconfigured() {
        XCTAssertNil(MatrixProductConfiguration.defaultConfiguration(
            environment: [:],
            bundleValue: nil
        ))
    }

    func testInvalidExplicitEnvironmentDoesNotFallBackToBundle() {
        XCTAssertNil(MatrixProductConfiguration.defaultConfiguration(
            environment: [
                MatrixProductConfiguration.defaultHomeserverEnvironmentKey:
                    "http://runtime.example.org"
            ],
            bundleValue: "https://packaged.example.org"
        ))
    }

    func testDefaultRejectsCredentialsQueryAndFragment() {
        for value in [
            "https://user:password@matrix.example.org",
            "https://matrix.example.org?tenant=zenith",
            "https://matrix.example.org#fragment"
        ] {
            XCTAssertNil(
                MatrixProductConfiguration.defaultConfiguration(
                    environment: [
                        MatrixProductConfiguration.defaultHomeserverEnvironmentKey: value
                    ],
                    bundleValue: nil
                ),
                value
            )
        }
    }
}
