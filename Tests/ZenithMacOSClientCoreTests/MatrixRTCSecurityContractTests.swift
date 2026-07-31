import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class MatrixRTCSecurityContractTests: XCTestCase {
    private static let accountDigest = String(repeating: "1", count: 64)
    private static let homeserverDigest = String(repeating: "2", count: 64)
    private static let originRoomDigest = String(repeating: "3", count: 64)
    private static let presentedRoomDigest = String(repeating: "4", count: 64)
    private static let deviceDigest = String(repeating: "5", count: 64)
    private static let profileDigest = String(repeating: "6", count: 64)
    private static let otherDigest = String(repeating: "a", count: 64)
    private static let generation: UInt64 = 42

    func testPeerTrustClassificationsRemainSemanticallyDistinct() {
        let results: [MatrixRTCPeerTrustClassification] = [
            classify(),
            classify(localSAS: .notVerified),
            classify(currentDeviceChain: .missing),
            classify(authentication: .invalid),
            classify(revocation: .revoked),
            classify(authentication: .missing),
            classify(authentication: .malformed),
        ]
        let expected: [MatrixRTCPeerTrustClassification] = [
            .locallySASVerified, .crossSigned, .authenticated, .invalid, .revoked, .unknown, .malformed,
        ]
        XCTAssertEqual(results, expected)
        for first in results.indices {
            for second in results.indices where first != second {
                XCTAssertNotEqual(results[first], results[second])
            }
        }
    }

    func testRevokedEvidenceHasTerminalPrecedence() {
        XCTAssertEqual(
            classify(
                authentication: .invalid,
                currentDeviceChain: .malformed,
                currentCrossSigningChain: .invalid,
                localSAS: .verified,
                revocation: .revoked
            ),
            .revoked
        )
    }

    func testInvalidChainEvidenceHasTerminalPrecedence() {
        XCTAssertEqual(classify(authentication: .invalid, revocation: .missing), .invalid)
        XCTAssertEqual(classify(currentDeviceChain: .invalid, revocation: .missing), .invalid)
        XCTAssertEqual(classify(currentCrossSigningChain: .invalid, revocation: .missing), .invalid)
    }

    func testMalformedEvidencePrecedesUnknownButNotInvalidOrRevoked() {
        XCTAssertEqual(classify(authentication: .malformed), .malformed)
        XCTAssertEqual(classify(currentDeviceChain: .malformed), .malformed)
        XCTAssertEqual(classify(currentCrossSigningChain: .malformed), .malformed)
        XCTAssertEqual(classify(localSAS: .malformed), .malformed)
        XCTAssertEqual(classify(revocation: .malformed), .malformed)
        XCTAssertEqual(classify(authentication: .invalid, localSAS: .malformed), .invalid)
        XCTAssertEqual(classify(authentication: .invalid, revocation: .revoked), .revoked)
    }

    func testLocalSASNeverRepairsMissingCurrentDeviceOrCrossSigningChain() {
        XCTAssertEqual(classify(currentDeviceChain: .missing), .authenticated)
        XCTAssertEqual(classify(currentCrossSigningChain: .missing), .authenticated)
    }

    func testLocalSASNeverRepairsInvalidCurrentDeviceOrCrossSigningChain() {
        XCTAssertEqual(classify(currentDeviceChain: .invalid), .invalid)
        XCTAssertEqual(classify(currentCrossSigningChain: .invalid), .invalid)
    }

    func testMissingRevocationEvidenceNeverPromotesTrust() {
        XCTAssertEqual(classify(revocation: .missing), .unknown)
    }

    func testCrossSignedWithoutLocalSASRemainsDistinctAndHasNoAuthorityField() throws {
        let classification = classify(localSAS: .notVerified)
        XCTAssertEqual(classification, .crossSigned)
        XCTAssertTrue(Mirror(reflecting: classification).children.isEmpty)

        let source = try securityContractSource()
        XCTAssertFalse(source.contains("mediaKey"))
        XCTAssertFalse(source.contains("mediaAuthority"))
        XCTAssertFalse(source.contains("isAuthorized"))
        XCTAssertFalse(source.contains("isEligible"))
    }

    func testEverySecretKindHasExactEnumOnlyOwnershipMetadata() {
        XCTAssertEqual(MatrixRTCSecretKind.allCases, [
            .matrixAccessToken, .openIDToken, .senderKey, .transportGrant, .authorizationHeader,
        ])
        assertMetadata(.matrixAccessToken, owner: .matrixSession, lifetime: .sessionBound)
        assertMetadata(.openIDToken, owner: .homeserverTokenExchange, lifetime: .singleExchange)
        assertMetadata(.senderKey, owner: .matrixRTCCrypto, lifetime: .membershipGenerationBound)
        assertMetadata(.transportGrant, owner: .transportAuthorization, lifetime: .callLifecycleBound)
        assertMetadata(.authorizationHeader, owner: .requestBoundary, lifetime: .singleRequest)
    }

    func testSecretMetadataContainsNoSecretValueOrRawAuthorizationSurface() throws {
        for kind in MatrixRTCSecretKind.allCases {
            let children = Array(Mirror(reflecting: kind.ownershipMetadata).children)
            XCTAssertEqual(children.compactMap(\.label), ["owner", "lifetime", "redaction"])
            XCTAssertEqual(children.count, 3)
            for child in children {
                XCTAssertEqual(Mirror(reflecting: child.value).displayStyle, .enum)
            }
        }

        let source = try securityContractSource()
        for forbiddenImport in [
            "import Foundation", "import SwiftUI", "import AppKit", "import AVFoundation",
            "import LiveKit", "import MatrixRustSDK", "import MatrixSDKFFI", "import UniFFI",
            "import Security", "import Network", "import FoundationNetworking",
        ] {
            XCTAssertFalse(source.contains(forbiddenImport), forbiddenImport)
        }
        for forbiddenDeclaration in [
            "public let value:", "public let rawValue:", "public let bytes:",
            "public let data:", "public let token:", "public let credential:",
            "public let request:", "public let response:", "public let header:",
            "public let payload:", "public var value:", "public var rawValue:",
        ] {
            XCTAssertFalse(source.localizedCaseInsensitiveContains(forbiddenDeclaration), forbiddenDeclaration)
        }
        XCTAssertFalse(source.contains("public init(owner:"))
    }

    func testPublicDescriptionsContainNoSecretOrIdentityValues() {
        let syntheticValues = [
            Self.accountDigest, Self.homeserverDigest, Self.originRoomDigest,
            Self.deviceDigest, Self.profileDigest, String(Self.generation),
        ]
        let forbiddenVocabulary = [
            "token", "header", "payload", "credential", "secret", "authorization", "bearer",
            "account", "room", "device", "homeserver", "sdk error", "raw response",
        ]
        for reason in MatrixRTCUnsupportedReason.allCases {
            let presentation = MatrixRTCUnsupportedPresentation(reason: reason)
            let text = [
                presentation.title, presentation.description, presentation.recovery,
                presentation.accessibilityLabel, presentation.accessibilityHint,
            ].joined(separator: " ").lowercased()
            for value in syntheticValues {
                XCTAssertFalse(text.contains(value.lowercased()), "Leaked synthetic value for \(reason)")
            }
            for word in forbiddenVocabulary {
                XCTAssertFalse(text.contains(word), "Unsafe vocabulary '\(word)' for \(reason)")
            }
        }
    }

    func testDigestIdentifierRequiresExactlyLowercaseSHA256() {
        XCTAssertNotNil(MatrixRTCDigestIdentifier(sha256: Self.accountDigest))
        XCTAssertNil(MatrixRTCDigestIdentifier(sha256: Self.accountDigest.uppercased()))
        XCTAssertNil(MatrixRTCDigestIdentifier(sha256: String(Self.accountDigest.dropLast())))
        XCTAssertNil(MatrixRTCDigestIdentifier(sha256: Self.accountDigest + "0"))
        XCTAssertNil(MatrixRTCDigestIdentifier(sha256: String(repeating: "g", count: 64)))
        XCTAssertNil(MatrixRTCDigestIdentifier(sha256: String(repeating: "é", count: 32)))
    }

    func testSameAccountRoomNavigationPreservesImmutableOriginPresentation() {
        XCTAssertEqual(
            evaluate(context: makeContext(presentedRoom: identifier(Self.presentedRoomDigest)), request: .present),
            .preservePresentation(returnAction: .returnToOrigin)
        )
    }

    func testReturnToOriginRestoresOriginPresentationDecision() {
        XCTAssertEqual(
            evaluate(context: makeContext(presentedRoom: identifier(Self.presentedRoomDigest)), request: .returnToOrigin),
            .presentAtOrigin
        )
    }

    func testAccountSwitchRequiresLeaveAndSwitchOrCancel() {
        let otherAccount = identifier(Self.otherDigest)
        XCTAssertEqual(
            evaluate(request: .requestAccountSwitch(to: otherAccount)),
            .requireAccountSwitchChoice(confirm: .leaveAndSwitch, cancel: .cancel)
        )
        XCTAssertEqual(evaluate(request: .leaveAndSwitch(to: otherAccount)), .leaveAndSwitch)
    }

    func testCancelPreservesTheOriginBinding() {
        XCTAssertEqual(evaluate(request: .cancelAccountSwitch), .cancelPreservingOrigin)
    }

    func testConflictingSecondCallIsBlocked() {
        XCTAssertEqual(evaluate(request: .beginSecondCall), .blockSecondCall)
    }

    func testOriginMutationsRequireExactAccountHomeserverRoomDeviceProfileAndGeneration() {
        let expected = makeIdentity()
        let mutations: [(MatrixRTCOriginLifecycleIdentity, MatrixRTCOriginInvalidationReason)] = [
            (makeIdentity(account: identifier(Self.otherDigest)), .accountMismatch),
            (makeIdentity(homeserver: identifier(Self.otherDigest)), .homeserverMismatch),
            (makeIdentity(originRoom: identifier(Self.otherDigest)), .originRoomMismatch),
            (makeIdentity(device: identifier(Self.otherDigest)), .deviceMismatch),
            (makeIdentity(profile: identifier(Self.otherDigest)), .profileMismatch),
            (makeIdentity(generation: Self.generation + 1), .generationMismatch),
        ]
        for (identity, reason) in mutations {
            let context = makeContext(identity: identity)
            XCTAssertEqual(
                MatrixRTCOriginLifecycleEvaluator.evaluate(
                    expectedOrigin: expected,
                    context: context,
                    request: .beginSecondCall
                ),
                .invalidated(reason)
            )
        }
    }

    func testMissingInvalidOrMalformedSessionInvalidatesBeforeActions() {
        let cases: [(MatrixRTCOriginEvidenceValidity, MatrixRTCOriginInvalidationReason)] = [
            (.missing, .sessionMissing), (.invalid, .sessionInvalid), (.malformed, .sessionMalformed),
        ]
        for (validity, reason) in cases {
            XCTAssertEqual(evaluate(context: makeContext(session: validity), request: .beginSecondCall), .invalidated(reason))
        }
    }

    func testMissingInvalidOrMalformedOriginRoomInvalidatesBeforeActions() {
        let cases: [(MatrixRTCOriginEvidenceValidity, MatrixRTCOriginInvalidationReason)] = [
            (.missing, .originRoomMissing), (.invalid, .originRoomInvalid), (.malformed, .originRoomMalformed),
        ]
        for (validity, reason) in cases {
            XCTAssertEqual(evaluate(context: makeContext(originRoomValidity: validity), request: .leaveAndSwitch(to: identifier(Self.otherDigest))), .invalidated(reason))
        }
    }

    func testLifecycleInvalidationPrecedenceIsDeterministic() {
        let expected = makeIdentity()
        let allIdentityFailures = makeIdentity(
            account: identifier(Self.otherDigest),
            homeserver: identifier(Self.otherDigest),
            originRoom: identifier(Self.otherDigest),
            device: identifier(Self.otherDigest),
            profile: identifier(Self.otherDigest),
            generation: Self.generation + 1
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: allIdentityFailures, session: .malformed, originRoomValidity: .malformed)),
            .invalidated(.accountMismatch)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(homeserver: identifier(Self.otherDigest), originRoom: identifier(Self.otherDigest), device: identifier(Self.otherDigest), profile: identifier(Self.otherDigest), generation: Self.generation + 1), session: .malformed, originRoomValidity: .malformed)),
            .invalidated(.homeserverMismatch)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(originRoom: identifier(Self.otherDigest), device: identifier(Self.otherDigest), profile: identifier(Self.otherDigest), generation: Self.generation + 1), session: .missing, originRoomValidity: .malformed)),
            .invalidated(.sessionMissing)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(originRoom: identifier(Self.otherDigest), device: identifier(Self.otherDigest), profile: identifier(Self.otherDigest), generation: Self.generation + 1), originRoomValidity: .malformed)),
            .invalidated(.originRoomMismatch)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(device: identifier(Self.otherDigest), profile: identifier(Self.otherDigest), generation: Self.generation + 1), originRoomValidity: .invalid)),
            .invalidated(.originRoomInvalid)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(device: identifier(Self.otherDigest), profile: identifier(Self.otherDigest), generation: Self.generation + 1))),
            .invalidated(.deviceMismatch)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(profile: identifier(Self.otherDigest), generation: Self.generation + 1))),
            .invalidated(.profileMismatch)
        )
        XCTAssertEqual(
            evaluate(expected: expected, context: makeContext(identity: makeIdentity(generation: Self.generation + 1))),
            .invalidated(.generationMismatch)
        )
    }

    func testUnsupportedReasonsExposeCompleteAccessiblePresentation() {
        XCTAssertEqual(MatrixRTCUnsupportedReason.allCases, [
            .qualificationUnavailable, .peerTrustUnavailable, .originInvalidated, .nativeSessionUnavailable,
        ])
        for reason in MatrixRTCUnsupportedReason.allCases {
            let presentation = MatrixRTCUnsupportedPresentation(reason: reason)
            XCTAssertEqual(presentation.reason, reason)
            XCTAssertEqual(presentation.title, reason.title)
            XCTAssertEqual(presentation.description, reason.description)
            XCTAssertEqual(presentation.recovery, reason.recovery)
            XCTAssertEqual(presentation.accessibilityLabel, reason.accessibilityLabel)
            XCTAssertEqual(presentation.accessibilityHint, reason.accessibilityHint)
            XCTAssertFalse(presentation.title.isEmpty)
            XCTAssertFalse(presentation.description.isEmpty)
            XCTAssertFalse(presentation.recovery.isEmpty)
            XCTAssertFalse(presentation.accessibilityLabel.isEmpty)
            XCTAssertFalse(presentation.accessibilityHint.isEmpty)
        }
    }

    func testFuturePresentationContractIsTrailingInspectorAndFutureOnly() {
        let contract = MatrixRTCFutureCallPresentationContract.selectedRoom
        XCTAssertEqual(contract.scope, .futureOnlyNonruntime)
        XCTAssertEqual(contract.affordance, .selectedRoomTopRight)
        XCTAssertEqual(contract.surface, .messagesLikeTrailingInspector)
        XCTAssertEqual(contract.states, [.unavailable, .incoming, .preJoin, .active])
        XCTAssertEqual(contract.unavailableAction, .exposeUnavailableReason)
        XCTAssertEqual(contract.incomingBehavior, .passive)
        XCTAssertEqual(contract.dismissal, .presentationOnly)
    }

    func testSecurityContractSourceUsesOnlySDKNeutralImports() throws {
        let source = try securityContractSource()
        let forbidden = [
            "import Foundation", "SwiftUI", "AppKit", "AVFoundation", "LiveKit", "MatrixRustSDK",
            "MatrixSDKFFI", "UniFFI", "FoundationNetworking", "URLSession", "Network", "Security",
            "Date(", "Clock", "ProcessInfo", "m.rtc_foci", "isLivekitRtcSupported",
        ]
        for term in forbidden {
            XCTAssertFalse(source.contains(term), "Security contract source contains forbidden term: \(term)")
        }
    }

    private func classify(
        authentication: MatrixRTCPeerEvidenceState = .proven,
        currentDeviceChain: MatrixRTCPeerEvidenceState = .proven,
        currentCrossSigningChain: MatrixRTCPeerEvidenceState = .proven,
        localSAS: MatrixRTCLocalSASEvidence = .verified,
        revocation: MatrixRTCRevocationEvidence = .notRevoked
    ) -> MatrixRTCPeerTrustClassification {
        MatrixRTCPeerTrustClassifier.classify(MatrixRTCPeerTrustEvidence(
            authentication: authentication,
            currentDeviceChain: currentDeviceChain,
            currentCrossSigningChain: currentCrossSigningChain,
            localSAS: localSAS,
            revocation: revocation
        ))
    }

    private func assertMetadata(
        _ kind: MatrixRTCSecretKind,
        owner: MatrixRTCSecretOwner,
        lifetime: MatrixRTCSecretLifetime,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(kind.ownershipMetadata.owner, owner, file: file, line: line)
        XCTAssertEqual(kind.ownershipMetadata.lifetime, lifetime, file: file, line: line)
        XCTAssertEqual(kind.ownershipMetadata.redaction, .omitFromQualificationEvidenceAndDescriptions, file: file, line: line)
    }

    private func identifier(_ digest: String) -> MatrixRTCDigestIdentifier {
        MatrixRTCDigestIdentifier(sha256: digest)!
    }

    private func makeIdentity(
        account: MatrixRTCDigestIdentifier? = nil,
        homeserver: MatrixRTCDigestIdentifier? = nil,
        originRoom: MatrixRTCDigestIdentifier? = nil,
        device: MatrixRTCDigestIdentifier? = nil,
        profile: MatrixRTCDigestIdentifier? = nil,
        generation: UInt64 = MatrixRTCSecurityContractTests.generation
    ) -> MatrixRTCOriginLifecycleIdentity {
        MatrixRTCOriginLifecycleIdentity(
            account: account ?? identifier(Self.accountDigest),
            homeserver: homeserver ?? identifier(Self.homeserverDigest),
            originRoom: originRoom ?? identifier(Self.originRoomDigest),
            device: device ?? identifier(Self.deviceDigest),
            profile: profile ?? identifier(Self.profileDigest),
            generation: generation
        )
    }

    private func makeContext(
        identity: MatrixRTCOriginLifecycleIdentity? = nil,
        session: MatrixRTCOriginEvidenceValidity = .valid,
        originRoomValidity: MatrixRTCOriginEvidenceValidity = .valid,
        presentedRoom: MatrixRTCDigestIdentifier? = nil
    ) -> MatrixRTCOriginLifecycleContext {
        MatrixRTCOriginLifecycleContext(
            identity: identity ?? makeIdentity(),
            session: session,
            originRoom: originRoomValidity,
            presentedRoom: presentedRoom ?? identifier(Self.originRoomDigest)
        )
    }

    private func evaluate(
        expected: MatrixRTCOriginLifecycleIdentity? = nil,
        context: MatrixRTCOriginLifecycleContext? = nil,
        request: MatrixRTCOriginLifecycleRequest = .present
    ) -> MatrixRTCOriginLifecycleDecision {
        MatrixRTCOriginLifecycleEvaluator.evaluate(
            expectedOrigin: expected ?? makeIdentity(),
            context: context ?? makeContext(),
            request: request
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func securityContractSource() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRTCSecurityContract.swift"),
            encoding: .utf8
        )
    }
}
