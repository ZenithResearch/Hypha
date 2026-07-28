import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class MatrixInviteRegistrationClientTests: XCTestCase {
    func testAvailabilityProbeContainsNoCredentialsAndRequiresTokenOnlyFlow() async throws {
        let transport = ScriptedRegistrationTransport(responses: [
            response(
                status: 401,
                body: #"{"session":"probe","flows":[{"stages":["m.login.registration_token"]}]}"#
            )
        ])
        let client = MatrixInviteRegistrationClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        let availability = await client.availability()
        let requests = await transport.observedRequests()
        let body = try XCTUnwrap(requests.first?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(availability, .inviteToken)
        XCTAssertEqual(object["inhibit_login"] as? Bool, true)
        XCTAssertNil(object["username"])
        XCTAssertNil(object["password"])
        XCTAssertNil(object["token"])
    }

    func testRegistrationCompletesTokenUIAAndInhibitsUnusedLoginSession() async throws {
        let transport = ScriptedRegistrationTransport(responses: [
            response(
                status: 401,
                body: #"{"session":"register-session","flows":[{"stages":["m.login.registration_token"]}]}"#
            ),
            response(status: 200, body: #"{"user_id":"@alice:example.org"}"#)
        ])
        let client = MatrixInviteRegistrationClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        let result = try await client.register(.init(
            username: "alice",
            password: "not-a-real-password",
            registrationToken: "not-a-real-token"
        ))

        let requests = await transport.observedRequests()
        XCTAssertEqual(requests.count, 2)
        let body = try XCTUnwrap(requests.last?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let auth = try XCTUnwrap(object["auth"] as? [String: Any])
        XCTAssertEqual(object["username"] as? String, "alice")
        XCTAssertEqual(object["password"] as? String, "not-a-real-password")
        XCTAssertEqual(object["inhibit_login"] as? Bool, true)
        XCTAssertEqual(auth["type"] as? String, "m.login.registration_token")
        XCTAssertEqual(auth["session"] as? String, "register-session")
        XCTAssertEqual(auth["token"] as? String, "not-a-real-token")
        XCTAssertEqual(result, MatrixAccountRegistrationResult(userID: "@alice:example.org"))
    }

    func testRegistrationRejectsAnUnexpectedServerSessionInsteadOfAbandoningADevice() async throws {
        let transport = ScriptedRegistrationTransport(responses: [
            response(
                status: 200,
                body: #"{"user_id":"@alice:example.org","access_token":"must-not-be-used","device_id":"ABANDONED"}"#
            )
        ])
        let client = MatrixInviteRegistrationClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        do {
            _ = try await client.register(.init(
                username: "alice",
                password: "not-a-real-password",
                registrationToken: "not-a-real-token"
            ))
            XCTFail("Expected an inhibited-login response")
        } catch {
            XCTAssertEqual(error as? MatrixAccountRegistrationError, .unexpectedServerSession)
        }
    }

    func testRegistrationRejectsMismatchedAccountIdentityBeforeSDKLogin() async throws {
        let transport = ScriptedRegistrationTransport(responses: [
            response(status: 200, body: #"{"user_id":"@other:example.org"}"#)
        ])
        let client = MatrixInviteRegistrationClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: transport
        )

        do {
            _ = try await client.register(.init(
                username: "alice",
                password: "not-a-real-password",
                registrationToken: "not-a-real-token"
            ))
            XCTFail("Expected response identity reconciliation")
        } catch {
            XCTAssertEqual(error as? MatrixAccountRegistrationError, .identityMismatch)
        }
    }

    func testRegistrationRejectsUIAASessionOrFlowDriftBeforeSendingAnotherCredential() async throws {
        let driftedChallenges = [
            #"{"session":"changed","completed":["m.login.registration_token"],"flows":[{"stages":["m.login.registration_token","m.login.dummy"]}]}"#,
            #"{"session":"stable","completed":["m.login.registration_token"],"flows":[{"stages":["m.login.registration_token","m.login.email.identity"]}]}"#,
        ]

        for driftedChallenge in driftedChallenges {
            let transport = ScriptedRegistrationTransport(responses: [
                response(
                    status: 401,
                    body: #"{"session":"stable","flows":[{"stages":["m.login.registration_token","m.login.dummy"]}]}"#
                ),
                response(status: 401, body: driftedChallenge),
            ])
            let client = MatrixInviteRegistrationClient(
                homeserver: URL(string: "https://matrix.example.org")!,
                transport: transport
            )

            do {
                _ = try await client.register(.init(
                    username: "alice",
                    password: "not-a-real-password",
                    registrationToken: "not-a-real-token"
                ))
                XCTFail("Expected UIAA continuation reconciliation to fail closed")
            } catch {
                XCTAssertEqual(error as? MatrixAccountRegistrationError, .invalidResponse)
            }
            let requests = await transport.observedRequests()
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testCapabilityDiscoveryChoosesSupportedFlowDeterministically() async throws {
        let challenge = #"{"session":"probe","flows":[{"stages":["m.login.registration_token","m.login.dummy"]},{"stages":["m.login.registration_token"]},{"stages":["m.login.sso"]}]}"#
        let client = MatrixInviteRegistrationClient(
            homeserver: URL(string: "https://matrix.example.org")!,
            transport: ScriptedRegistrationTransport(responses: [response(status: 401, body: challenge)])
        )

        let capability = await client.capability()
        XCTAssertEqual(capability, .inviteToken(stages: ["m.login.registration_token"]))
    }

    func testCapabilityDiscoveryReturnsTypedUnsupportedOutcomes() async throws {
        let cases: [(String, MatrixRegistrationCapability)] = [
            (#"{"session":"s","flows":[{"stages":["m.login.sso"]}]}"#, .unsupported(.singleSignOn)),
            (#"{"session":"s","flows":[{"stages":["m.login.oauth2"]}]}"#, .unsupported(.oauth)),
            (#"{"session":"s","flows":[{"stages":["m.login.recaptcha"]}]}"#, .unsupported(.captcha)),
            (#"{"session":"s","flows":[{"stages":["m.login.email.identity"]}]}"#, .unsupported(.uiaa))
        ]

        for (body, expected) in cases {
            let client = MatrixInviteRegistrationClient(
                homeserver: URL(string: "https://matrix.example.org")!,
                transport: ScriptedRegistrationTransport(responses: [response(status: 401, body: body)])
            )
            let capability = await client.capability()
            XCTAssertEqual(capability, expected)
        }
    }

    func testRegistrationRejectsUnsupportedUIAWithoutSendingToken() async throws {
        let cases: [(String, MatrixAccountRegistrationError)] = [
            ("m.login.sso", .unsupportedSingleSignOn),
            ("m.login.oauth2", .unsupportedOAuth),
            ("m.login.recaptcha", .captchaRequired),
            ("m.login.email.identity", .unsupportedAuthentication)
        ]

        for (stage, expectedError) in cases {
            let challenge = "{\"session\":\"unsupported\",\"flows\":[{\"stages\":[\"\(stage)\"]}]}"
            let transport = ScriptedRegistrationTransport(responses: [response(status: 401, body: challenge)])
            let client = MatrixInviteRegistrationClient(
                homeserver: URL(string: "https://matrix.example.org")!,
                transport: transport
            )

            do {
                _ = try await client.register(.init(
                    username: "alice",
                    password: "not-a-real-password",
                    registrationToken: "must-not-be-sent"
                ))
                XCTFail("Expected typed unsupported UIAA outcome")
            } catch {
                XCTAssertEqual(error as? MatrixAccountRegistrationError, expectedError)
            }

            let requests = await transport.observedRequests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertFalse(String(data: requests[0].httpBody ?? Data(), encoding: .utf8)?.contains("must-not-be-sent") == true)
        }
    }

    func testRegistrationErrorsHaveStableSafeCodes() {
        let cases: [(MatrixAccountRegistrationError, String)] = [
            (.unavailable, "registration_unavailable"),
            (.invalidInput, "registration_invalid_input"),
            (.invalidToken, "registration_invalid_token"),
            (.unsupportedAuthentication, "registration_uiaa_unsupported"),
            (.unsupportedSingleSignOn, "registration_sso_unsupported"),
            (.unsupportedOAuth, "registration_oauth_unsupported"),
            (.captchaRequired, "registration_captcha_unsupported"),
            (.redirectRejected, "registration_redirect_rejected"),
            (.originMismatch, "registration_origin_mismatch"),
            (.invalidResponse, "registration_invalid_response"),
            (.unexpectedServerSession, "registration_unexpected_server_session"),
            (.identityMismatch, "registration_identity_mismatch"),
            (.transportFailure, "registration_transport_failure"),
            (.serverRejected, "registration_server_rejected")
        ]
        for (error, code) in cases { XCTAssertEqual(error.stableCode, code) }
    }

    func testRedirectAndOriginDriftAreRejectedBeforeUIAAHandling() async throws {
        let endpoint = URL(string: "https://matrix.example.org/_matrix/client/v3/register")!
        let cases: [(ScriptedRegistrationTransport.Response, MatrixRegistrationCapability)] = [
            (.init(status: 302, body: Data(), url: endpoint, headers: ["Location": "https://login.example.org"]), .unavailable(.redirectRejected)),
            (.init(status: 401, body: Data(#"{"session":"s","flows":[{"stages":["m.login.registration_token"]}]}"#.utf8), url: URL(string: "https://evil.example/_matrix/client/v3/register")!), .unavailable(.originMismatch))
        ]
        for (response, expected) in cases {
            let client = MatrixInviteRegistrationClient(
                homeserver: URL(string: "https://matrix.example.org")!,
                transport: ScriptedRegistrationTransport(responses: [response])
            )
            let capability = await client.capability()
            XCTAssertEqual(capability, expected)
        }
    }

    private func response(status: Int, body: String) -> ScriptedRegistrationTransport.Response {
        .init(status: status, body: Data(body.utf8))
    }
}

private actor ScriptedRegistrationTransport: MatrixRegistrationTransport {
    struct Response: Sendable {
        let status: Int
        let body: Data
        let url: URL?
        let headers: [String: String]

        init(status: Int, body: Data, url: URL? = nil, headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.url = url
            self.headers = headers
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw MatrixAccountRegistrationError.transportFailure }
        let response = responses.removeFirst()
        let http = HTTPURLResponse(
            url: response.url ?? request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"].merging(response.headers) { _, new in new }
        )!
        return (response.body, http)
    }

    func observedRequests() -> [URLRequest] { requests }
}
