import Foundation
import XCTest
@testable import HyphaCore

final class MatrixHomeserverHealthCheckerTests: XCTestCase {
    func testBareHostnameUsesHTTPSAndChecksMatrixVersionsEndpoint() async throws {
        let checker = MatrixHomeserverHealthChecker { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://matrix.example.org/_matrix/client/versions"
            )
            return try response(
                url: request.url!,
                status: 200,
                json: ["versions": ["v1.11"]]
            )
        }

        let configuration = try await checker.connect(to: "matrix.example.org")

        XCTAssertEqual(configuration.homeserver.absoluteString, "https://matrix.example.org")
        XCTAssertFalse(configuration.allowsPlaintextFallback)
    }

    func testExplicitHTTPSHomeserverPreservesBasePath() async throws {
        let checker = MatrixHomeserverHealthChecker { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://example.org/matrix/_matrix/client/versions"
            )
            return try response(
                url: request.url!,
                status: 200,
                json: ["versions": ["v1.10"]]
            )
        }

        let configuration = try await checker.connect(to: " https://example.org/matrix/ ")

        XCTAssertEqual(configuration.homeserver.absoluteString, "https://example.org/matrix")
    }

    func testRejectsInsecureRemoteHomeserverBeforeNetworkRequest() async {
        let checker = MatrixHomeserverHealthChecker { _ in
            XCTFail("Insecure remote homeserver must be rejected before a request")
            throw URLError(.badURL)
        }

        await XCTAssertThrowsErrorAsync(try await checker.connect(to: "http://matrix.example.org")) { error in
            XCTAssertEqual(error as? MatrixHomeserverConnectionError, .insecureTransport)
        }
    }

    func testRejectsSuccessfulNonMatrixResponse() async {
        let checker = MatrixHomeserverHealthChecker { request in
            try response(url: request.url!, status: 200, json: ["status": "ok"])
        }

        await XCTAssertThrowsErrorAsync(try await checker.connect(to: "matrix.example.org")) { error in
            XCTAssertEqual(error as? MatrixHomeserverConnectionError, .invalidMatrixResponse)
        }
    }

    func testReportsHTTPFailureWithoutReturningConfiguration() async {
        let checker = MatrixHomeserverHealthChecker { request in
            try response(url: request.url!, status: 503, json: ["errcode": "M_UNAVAILABLE"])
        }

        await XCTAssertThrowsErrorAsync(try await checker.connect(to: "matrix.example.org")) { error in
            XCTAssertEqual(error as? MatrixHomeserverConnectionError, .httpStatus(503))
        }
    }

    func testConfiguredLiveHomeserverPassesMatrixHealthCheck() async throws {
        guard let homeserver = ProcessInfo.processInfo.environment["ZENITH_MATRIX_LIVE_HOMESERVER"] else {
            throw XCTSkip("Set ZENITH_MATRIX_LIVE_HOMESERVER to run the live health check")
        }

        let configuration = try await MatrixHomeserverHealthChecker().connect(to: homeserver)

        XCTAssertEqual(configuration.homeserver.absoluteString, homeserver)
    }
}

private func response(url: URL, status: Int, json: [String: Any]) throws -> (Data, HTTPURLResponse) {
    let data = try JSONSerialization.data(withJSONObject: json)
    let response = try XCTUnwrap(
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
    )
    return (data, response)
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
