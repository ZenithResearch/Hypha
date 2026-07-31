import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class MatrixRTCQualificationTests: XCTestCase {
    private static let profileID = "ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2"
    private static let profileDigest = "630c781b782eb94965fb83767a39247f2d127ac31f0c89065f18711b375f8f6d"
    private static let originDigest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private static let otherOriginDigest = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
    private static let syntheticSDKSourceRevision = "0123456789abcdef0123456789abcdef01234567"
    private static let otherSDKSourceRevision = "2222222222222222222222222222222222222222"
    private static let syntheticSDKCapabilitySnapshotDigest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    private static let otherSDKCapabilitySnapshotDigest = "4444444444444444444444444444444444444444444444444444444444444444"
    private static let generation: UInt64 = 42

    func testCompleteAuthoritativeFixtureIsAvailable() throws {
        let fixture = try loadFixture(named: "complete-authoritative")
        let (selection, evidence) = try fixture.domainValues()

        XCTAssertEqual(MatrixRTCQualificationEvaluator.evaluate(selection: selection, evidence: evidence), .available)
    }

    func testMissingEvidenceIsUnavailable() throws {
        let selection = try makeSelection()
        XCTAssertEqual(try evaluate(selection: selection, evidence: .init(server: nil, sdk: nil)), .unavailable(.missingServerEvidence))
        XCTAssertEqual(try evaluate(selection: selection, evidence: makeEvidence(includeSDK: false)), .unavailable(.missingSDKEvidence))
    }

    func testMissingSnapshotIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .missing)), .unavailable(.snapshotMissing))
    }

    func testSnapshotDigestMismatchIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .digestMismatch)), .unavailable(.snapshotDigestMismatch))
    }

    func testMalformedSnapshotIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .malformed)), .unavailable(.snapshotMalformed))
    }

    func testMissingServerAdvertisementIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .missing)), .unavailable(.serverAdvertisementMissing))
    }

    func testDisabledServerAdvertisementIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .disabled)), .unavailable(.serverAdvertisementDisabled))
    }

    func testMalformedServerAdvertisementIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .malformed)), .unavailable(.serverAdvertisementMalformed))
    }

    func testMissingAuthenticatedTransportEvidenceIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .missing)), .unavailable(.authenticatedTransportMissing))
    }

    func testUnsupportedAuthenticatedTransportEndpointIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .authenticatedUnsupported)), .unavailable(.authenticatedTransportUnsupported))
    }

    func testMalformedAuthenticatedTransportEndpointIsUnavailable() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .authenticatedMalformed)), .unavailable(.authenticatedTransportMalformed))
    }

    func testFallbackOnlyDiscoveryCannotQualify() throws {
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .fallbackOnly)), .unavailable(.fallbackOnly))
    }

    func testLegacyConvenienceBooleanCannotQualify() throws {
        let diagnostics = MatrixRTCDiagnosticEvidence(
            legacyWellKnownFocusAdvertised: false,
            legacyConvenienceBooleanSupported: true
        )
        let evidence = makeEvidence(advertisement: .missing, transport: .missing, diagnostics: diagnostics)
        XCTAssertEqual(try evaluate(evidence: evidence), .unavailable(.serverAdvertisementMissing))
    }

    func testLegacyWellKnownFocusCannotQualify() throws {
        let diagnostics = MatrixRTCDiagnosticEvidence(
            legacyWellKnownFocusAdvertised: true,
            legacyConvenienceBooleanSupported: false
        )
        let evidence = makeEvidence(advertisement: .missing, transport: .fallbackOnly, diagnostics: diagnostics)
        XCTAssertEqual(try evaluate(evidence: evidence), .unavailable(.serverAdvertisementMissing))
    }

    func testLegacyDiagnosticsDoNotChangeAnAuthoritativeOutcome() throws {
        let negative = MatrixRTCDiagnosticEvidence(
            legacyWellKnownFocusAdvertised: false,
            legacyConvenienceBooleanSupported: false
        )
        let positive = MatrixRTCDiagnosticEvidence(
            legacyWellKnownFocusAdvertised: true,
            legacyConvenienceBooleanSupported: true
        )
        XCTAssertEqual(try evaluate(evidence: makeEvidence(diagnostics: negative)), .available)
        XCTAssertEqual(try evaluate(evidence: makeEvidence(diagnostics: positive)), .available)
    }

    func testOlderEvidenceGenerationIsStale() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverGeneration: Self.generation - 1, sdkGeneration: Self.generation - 1)),
            .unavailable(.staleEvidence)
        )
    }

    func testDifferentServerAndSDKEvidenceProfilesAreRejected() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverProfileID: "synthetic.other.profile")),
            .unavailable(.mixedProfile)
        )
    }

    func testDifferentServerAndSDKEvidenceGenerationsAreRejected() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverGeneration: Self.generation - 1)),
            .unavailable(.mixedGeneration)
        )
    }

    func testDifferentServerAndSDKEvidenceOriginsAreRejected() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverOriginDigest: Self.otherOriginDigest)),
            .unavailable(.mixedOrigin)
        )
    }

    func testUnexpectedSelectedProfileIsRejected() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverProfileID: "synthetic.other.profile", sdkProfileID: "synthetic.other.profile")),
            .unavailable(.profileMismatch)
        )
    }

    func testUnexpectedSelectedProfileDigestIsRejected() throws {
        let otherDigest = String(repeating: "a", count: 64)
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverProfileDigest: otherDigest, sdkProfileDigest: otherDigest)),
            .unavailable(.profileDigestMismatch)
        )
    }

    func testUnexpectedFutureGenerationIsRejected() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(serverGeneration: Self.generation + 1, sdkGeneration: Self.generation + 1)),
            .unavailable(.generationMismatch)
        )
    }

    func testMissingRequiredSDKCapabilitiesFailInCanonicalOrder() throws {
        for capability in MatrixRTCQualificationEvaluator.requiredSDKCapabilities {
            var capabilities = Set(MatrixRTCQualificationEvaluator.requiredSDKCapabilities)
            capabilities.remove(capability)
            XCTAssertEqual(
                try evaluate(evidence: makeEvidence(capabilities: capabilities)),
                .unavailable(.missingSDKCapability(capability)),
                "Removed capability should be reported: \(capability)"
            )
        }
    }

    func testCurrentPinnedSDKGapBlocksAvailability() throws {
        let evidence = try loadSDKCapabilityEvidence()
        let currentPinnedCapabilities = try evidence.pinnedEvaluatorCapabilities()
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(capabilities: currentPinnedCapabilities)),
            .unavailable(.missingSDKCapability(.authenticatedTransportRegistryWithoutFallback))
        )
    }

    func testCheckedInSDKComparisonExhaustivelyCoversSelectedEvaluatorCapabilities() throws {
        let mappedRows = try loadSDKCapabilityEvidence().evaluatorComparisonRows()
        XCTAssertEqual(Set(mappedRows.keys), Set(MatrixRTCQualificationEvaluator.requiredSDKCapabilities))
        XCTAssertEqual(mappedRows.count, 11)
    }

    func testNewlyClosedSDKMatrixRowsHavePinnedCurrentAndSelectedValues() throws {
        let rows = try loadSDKCapabilityEvidence().comparisonByName()
        for name in [
            "profile_aware_participant_device_snapshot",
            "notification_and_decline",
            "recipient_device_validation",
            "registered_transport_type_validation",
        ] {
            let row = try XCTUnwrap(rows[name])
            let expectedPinnedAndCurrent = name == "notification_and_decline"
            XCTAssertEqual(row.pinnedHypha, expectedPinnedAndCurrent, name)
            XCTAssertEqual(row.currentUpstream, expectedPinnedAndCurrent, name)
            XCTAssertTrue(row.selectedProfile, name)
        }
    }

    func testUnknownSDKComparisonRowFailsFixtureDecoding() throws {
        let data = try Data(contentsOf: sdkCapabilityEvidenceURL)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var comparison = try XCTUnwrap(object["comparison"] as? [[String: Any]])
        comparison.append([
            "capability": "unknown_evaluator_capability",
            "current_upstream": false,
            "pinned_hypha": false,
            "selected_profile": true,
        ])
        object["comparison"] = comparison

        let decoded = try JSONDecoder().decode(
            SDKCapabilityEvidenceDTO.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertThrowsError(try decoded.evaluatorComparisonRows())
    }

    func testCurrentProductionFixtureIsUnsupported() throws {
        let fixture = try loadFixture(named: "current-production-unsupported")
        let (selection, evidence) = try fixture.domainValues()
        XCTAssertEqual(
            MatrixRTCQualificationEvaluator.evaluate(selection: selection, evidence: evidence),
            .unavailable(.serverAdvertisementMissing)
        )
    }

    func testReasonPrecedenceIsIndependentOfInputCapabilityOrder() throws {
        let shuffled: [MatrixRTCSDKCapability] = [
            .completeNativeSessionSurface,
            .recipientDeviceValidation,
            .slotMemberLifecycle,
            .notificationAndDecline,
        ]
        let reversed = Array(shuffled.reversed())
        let expected = MatrixRTCQualificationResult.unavailable(
            .missingSDKCapability(.authenticatedTransportRegistryWithoutFallback)
        )
        XCTAssertEqual(try evaluate(evidence: makeEvidence(capabilities: Set(shuffled))), expected)
        XCTAssertEqual(try evaluate(evidence: makeEvidence(capabilities: Set(reversed))), expected)
    }

    func testSDKArtifactIdentityRequiresExactLowercaseEncodings() {
        XCTAssertNotNil(MatrixRTCSDKArtifactIdentity(
            sourceRevision: Self.syntheticSDKSourceRevision,
            capabilitySnapshotDigestSHA256: Self.syntheticSDKCapabilitySnapshotDigest
        ))
        for revision in [
            Self.syntheticSDKSourceRevision.uppercased(),
            String(Self.syntheticSDKSourceRevision.dropLast()),
            Self.syntheticSDKSourceRevision + "0",
            String(repeating: "g", count: 40),
        ] {
            XCTAssertNil(MatrixRTCSDKArtifactIdentity(
                sourceRevision: revision,
                capabilitySnapshotDigestSHA256: Self.syntheticSDKCapabilitySnapshotDigest
            ))
        }
        for digest in [
            Self.syntheticSDKCapabilitySnapshotDigest.uppercased(),
            String(Self.syntheticSDKCapabilitySnapshotDigest.dropLast()),
            Self.syntheticSDKCapabilitySnapshotDigest + "0",
            String(repeating: "g", count: 64),
        ] {
            XCTAssertNil(MatrixRTCSDKArtifactIdentity(
                sourceRevision: Self.syntheticSDKSourceRevision,
                capabilitySnapshotDigestSHA256: digest
            ))
        }
    }

    func testSDKSourceRevisionMismatchPrecedesSnapshotDigestAndCapabilityEvaluation() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(
                observedSDKSourceRevision: Self.otherSDKSourceRevision,
                observedSDKCapabilitySnapshotDigest: Self.otherSDKCapabilitySnapshotDigest,
                capabilities: []
            )),
            .unavailable(.sdkSourceRevisionMismatch)
        )
    }

    func testSDKCapabilitySnapshotDigestMismatchPrecedesCapabilityEvaluation() throws {
        XCTAssertEqual(
            try evaluate(evidence: makeEvidence(
                observedSDKCapabilitySnapshotDigest: Self.otherSDKCapabilitySnapshotDigest,
                capabilities: []
            )),
            .unavailable(.sdkCapabilitySnapshotDigestMismatch)
        )
    }

    func testQualificationReasonPrecedenceMatchesContract() throws {
        let selection = try makeSelection()
        XCTAssertEqual(try evaluate(selection: selection, evidence: .init(server: nil, sdk: nil)), .unavailable(.missingServerEvidence))
        XCTAssertEqual(try evaluate(selection: selection, evidence: makeEvidence(includeSDK: false, snapshot: .missing)), .unavailable(.missingSDKEvidence))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverProfileID: "other", serverProfileDigest: String(repeating: "a", count: 64))), .unavailable(.mixedProfile))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverProfileDigest: String(repeating: "a", count: 64), serverGeneration: Self.generation - 1)), .unavailable(.mixedProfileDigest))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverOriginDigest: Self.otherOriginDigest, serverGeneration: Self.generation - 1)), .unavailable(.mixedGeneration))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverOriginDigest: Self.otherOriginDigest, snapshot: .missing)), .unavailable(.mixedOrigin))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverProfileID: "other", sdkProfileID: "other", snapshot: .missing)), .unavailable(.profileMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverProfileDigest: String(repeating: "a", count: 64), sdkProfileDigest: String(repeating: "a", count: 64), snapshot: .missing)), .unavailable(.profileDigestMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverOriginDigest: Self.otherOriginDigest, sdkOriginDigest: Self.otherOriginDigest, snapshot: .missing)), .unavailable(.originMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverGeneration: Self.generation - 1, sdkGeneration: Self.generation - 1, snapshot: .missing)), .unavailable(.staleEvidence))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(serverGeneration: Self.generation + 1, sdkGeneration: Self.generation + 1, snapshot: .missing)), .unavailable(.generationMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .missing, advertisement: .missing)), .unavailable(.snapshotMissing))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .digestMismatch, advertisement: .missing)), .unavailable(.snapshotDigestMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(snapshot: .malformed, advertisement: .missing)), .unavailable(.snapshotMalformed))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .missing, transport: .missing)), .unavailable(.serverAdvertisementMissing))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .disabled, transport: .missing)), .unavailable(.serverAdvertisementDisabled))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(advertisement: .malformed, transport: .missing)), .unavailable(.serverAdvertisementMalformed))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .missing, capabilities: [])), .unavailable(.authenticatedTransportMissing))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .fallbackOnly, capabilities: [])), .unavailable(.fallbackOnly))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .authenticatedUnsupported, capabilities: [])), .unavailable(.authenticatedTransportUnsupported))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(transport: .authenticatedMalformed, capabilities: [])), .unavailable(.authenticatedTransportMalformed))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(observedSDKSourceRevision: Self.otherSDKSourceRevision, observedSDKCapabilitySnapshotDigest: Self.otherSDKCapabilitySnapshotDigest, capabilities: [])), .unavailable(.sdkSourceRevisionMismatch))
        XCTAssertEqual(try evaluate(evidence: makeEvidence(observedSDKCapabilitySnapshotDigest: Self.otherSDKCapabilitySnapshotDigest, capabilities: [])), .unavailable(.sdkCapabilitySnapshotDigestMismatch))
    }

    func testReasonDescriptionsContainNoEvidenceValues() {
        let reasons: [MatrixRTCQualificationReason] = [
            .missingServerEvidence, .missingSDKEvidence, .mixedProfile, .mixedProfileDigest,
            .mixedGeneration, .mixedOrigin, .profileMismatch, .profileDigestMismatch,
            .originMismatch, .staleEvidence, .generationMismatch, .snapshotMissing,
            .snapshotDigestMismatch, .snapshotMalformed, .serverAdvertisementMissing,
            .serverAdvertisementDisabled, .serverAdvertisementMalformed,
            .authenticatedTransportMissing, .fallbackOnly, .authenticatedTransportUnsupported,
            .authenticatedTransportMalformed, .sdkSourceRevisionMismatch,
            .sdkCapabilitySnapshotDigestMismatch,
        ] + MatrixRTCQualificationEvaluator.requiredSDKCapabilities.map { .missingSDKCapability($0) }
        let forbiddenValues = [Self.profileID, Self.profileDigest, Self.originDigest, String(Self.generation)]
        let forbiddenVocabulary = ["token", "header", "payload", "account", "room", "device", "host", "response", "error"]

        for reason in reasons {
            let text = [reason.title, reason.description, reason.recovery].joined(separator: " ").lowercased()
            for value in forbiddenValues {
                XCTAssertFalse(text.contains(value.lowercased()), "Description leaked evidence: \(reason)")
            }
            for word in forbiddenVocabulary {
                XCTAssertFalse(text.contains(word), "Description used unsafe vocabulary '\(word)': \(reason)")
            }
        }
    }

    func testFixturesContainNoSecretOrRawPayloadFields() throws {
        let forbiddenKeyFragments = [
            "access_token", "authorization", "header", "openid", "token_value", "sender_key",
            "transport_grant", "raw", "body", "payload", "credential", "password", "secret",
            "account_id", "room_id", "device_id", "user_id",
        ]
        for name in ["complete-authoritative", "current-production-unsupported"] {
            let data = try Data(contentsOf: fixtureURL(named: name))
            let object = try JSONSerialization.jsonObject(with: data)
            try inspectJSON(object, forbiddenKeyFragments: forbiddenKeyFragments)
            let text = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("Bearer "))
            XCTAssertNil(text.range(of: #"syt_[A-Za-z0-9._~-]{20,}"#, options: .regularExpression))
            XCTAssertNil(text.range(of: #"[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}"#, options: .regularExpression))
            XCTAssertFalse(text.contains("matrix.org"))
        }
    }

    func testQualificationSourceUsesOnlySDKNeutralImports() throws {
        let source = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/ZenithMacOSClientCore/MatrixRTCQualification.swift"), encoding: .utf8)
        let forbidden = [
            "SwiftUI", "AppKit", "AVFoundation", "LiveKit", "MatrixRustSDK", "MatrixSDKFFI",
            "UniFFI", "FoundationNetworking", "URLSession", "Network", "Security", "Date(", "Clock",
            "ProcessInfo", "m.rtc_foci", "isLivekitRtcSupported",
        ]
        for term in forbidden {
            XCTAssertFalse(source.contains(term), "Qualification source contains forbidden term: \(term)")
        }
    }

    func testOriginBindingRequiresExactlyLowercaseSHA256() {
        XCTAssertNotNil(MatrixRTCOriginBinding(sha256: Self.originDigest))
        XCTAssertNil(MatrixRTCOriginBinding(sha256: Self.originDigest.uppercased()))
        XCTAssertNil(MatrixRTCOriginBinding(sha256: String(Self.originDigest.dropLast())))
        XCTAssertNil(MatrixRTCOriginBinding(sha256: Self.originDigest + "0"))
        XCTAssertNil(MatrixRTCOriginBinding(sha256: String(repeating: "g", count: 64)))
    }

    private func evaluate(
        selection: MatrixRTCQualificationSelection? = nil,
        evidence: MatrixRTCQualificationEvidence
    ) throws -> MatrixRTCQualificationResult {
        MatrixRTCQualificationEvaluator.evaluate(selection: try selection ?? makeSelection(), evidence: evidence)
    }

    private func makeSelection(
        originDigest: String = MatrixRTCQualificationTests.originDigest,
        generation: UInt64 = MatrixRTCQualificationTests.generation,
        expectedSDKSourceRevision: String = MatrixRTCQualificationTests.syntheticSDKSourceRevision,
        expectedSDKCapabilitySnapshotDigest: String = MatrixRTCQualificationTests.syntheticSDKCapabilitySnapshotDigest
    ) throws -> MatrixRTCQualificationSelection {
        MatrixRTCQualificationSelection(
            origin: try XCTUnwrap(MatrixRTCOriginBinding(sha256: originDigest)),
            generation: generation,
            expectedSDKArtifactIdentity: try XCTUnwrap(MatrixRTCSDKArtifactIdentity(
                sourceRevision: expectedSDKSourceRevision,
                capabilitySnapshotDigestSHA256: expectedSDKCapabilitySnapshotDigest
            ))
        )
    }

    private func makeEvidence(
        includeServer: Bool = true,
        includeSDK: Bool = true,
        serverProfileID: String = MatrixRTCQualificationTests.profileID,
        sdkProfileID: String = MatrixRTCQualificationTests.profileID,
        serverProfileDigest: String = MatrixRTCQualificationTests.profileDigest,
        sdkProfileDigest: String = MatrixRTCQualificationTests.profileDigest,
        serverOriginDigest: String = MatrixRTCQualificationTests.originDigest,
        sdkOriginDigest: String = MatrixRTCQualificationTests.originDigest,
        serverGeneration: UInt64 = MatrixRTCQualificationTests.generation,
        sdkGeneration: UInt64 = MatrixRTCQualificationTests.generation,
        snapshot: MatrixRTCSnapshotIntegrity = .matched,
        advertisement: MatrixRTCServerAdvertisement = .supported,
        transport: MatrixRTCTransportEvidence = .authenticatedSupported,
        diagnostics: MatrixRTCDiagnosticEvidence = .init(
            legacyWellKnownFocusAdvertised: false,
            legacyConvenienceBooleanSupported: false
        ),
        observedSDKSourceRevision: String = MatrixRTCQualificationTests.syntheticSDKSourceRevision,
        observedSDKCapabilitySnapshotDigest: String = MatrixRTCQualificationTests.syntheticSDKCapabilitySnapshotDigest,
        capabilities: Set<MatrixRTCSDKCapability> = Set(MatrixRTCQualificationEvaluator.requiredSDKCapabilities)
    ) -> MatrixRTCQualificationEvidence {
        let serverOrigin = MatrixRTCOriginBinding(sha256: serverOriginDigest)!
        let sdkOrigin = MatrixRTCOriginBinding(sha256: sdkOriginDigest)!
        let serverBinding = MatrixRTCEvidenceBinding(
            profileID: serverProfileID,
            profileDigestSHA256: serverProfileDigest,
            origin: serverOrigin,
            generation: serverGeneration
        )
        let sdkBinding = MatrixRTCEvidenceBinding(
            profileID: sdkProfileID,
            profileDigestSHA256: sdkProfileDigest,
            origin: sdkOrigin,
            generation: sdkGeneration
        )
        return MatrixRTCQualificationEvidence(
            server: includeServer ? MatrixRTCServerQualificationEvidence(
                binding: serverBinding,
                snapshotIntegrity: snapshot,
                serverAdvertisement: advertisement,
                transportEvidence: transport,
                diagnostics: diagnostics
            ) : nil,
            sdk: includeSDK ? MatrixRTCSDKQualificationEvidence(
                binding: sdkBinding,
                artifactIdentity: MatrixRTCSDKArtifactIdentity(
                    sourceRevision: observedSDKSourceRevision,
                    capabilitySnapshotDigestSHA256: observedSDKCapabilitySnapshotDigest
                )!,
                capabilities: capabilities
            ) : nil
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func fixtureURL(named name: String) -> URL {
        repositoryRoot.appendingPathComponent("docs/matrixrtc/fixtures/\(name).json")
    }

    private var sdkCapabilityEvidenceURL: URL {
        repositoryRoot.appendingPathComponent("docs/matrixrtc/sdk-capability-evidence.json")
    }

    private func loadSDKCapabilityEvidence() throws -> SDKCapabilityEvidenceDTO {
        try JSONDecoder().decode(SDKCapabilityEvidenceDTO.self, from: Data(contentsOf: sdkCapabilityEvidenceURL))
    }

    private func loadFixture(named name: String) throws -> FixtureDTO {
        try JSONDecoder().decode(FixtureDTO.self, from: Data(contentsOf: fixtureURL(named: name)))
    }

    private func inspectJSON(_ value: Any, forbiddenKeyFragments: [String]) throws {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let lowerKey = key.lowercased()
                for fragment in forbiddenKeyFragments {
                    XCTAssertFalse(lowerKey.contains(fragment), "Fixture key contains forbidden fragment: \(key)")
                }
                try inspectJSON(child, forbiddenKeyFragments: forbiddenKeyFragments)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try inspectJSON(child, forbiddenKeyFragments: forbiddenKeyFragments)
            }
        } else if let string = value as? String {
            XCTAssertFalse(string.localizedCaseInsensitiveContains("Bearer "))
        }
    }
}

private struct FixtureDTO: Decodable {
    let profileID: String
    let profileDigestSHA256: String
    let originDigestSHA256: String
    let generation: UInt64
    let sdkSourceRevision: String
    let sdkCapabilitySnapshotDigestSHA256: String
    let snapshotIntegrity: String
    let serverAdvertisement: String
    let transportEvidence: String
    let sdkCapabilities: [String]
    let legacyWellKnownFocusAdvertised: Bool
    let legacyConvenienceBooleanSupported: Bool

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case profileDigestSHA256 = "profile_digest_sha256"
        case originDigestSHA256 = "origin_digest_sha256"
        case generation
        case sdkSourceRevision = "sdk_source_revision"
        case sdkCapabilitySnapshotDigestSHA256 = "sdk_capability_snapshot_digest_sha256"
        case snapshotIntegrity = "snapshot_integrity"
        case serverAdvertisement = "server_advertisement"
        case transportEvidence = "transport_evidence"
        case sdkCapabilities = "sdk_capabilities"
        case legacyWellKnownFocusAdvertised = "legacy_well_known_focus_advertised"
        case legacyConvenienceBooleanSupported = "legacy_convenience_boolean_supported"
    }

    func domainValues() throws -> (MatrixRTCQualificationSelection, MatrixRTCQualificationEvidence) {
        let origin = try XCTUnwrap(MatrixRTCOriginBinding(sha256: originDigestSHA256))
        let binding = MatrixRTCEvidenceBinding(
            profileID: profileID,
            profileDigestSHA256: profileDigestSHA256,
            origin: origin,
            generation: generation
        )
        let diagnostics = MatrixRTCDiagnosticEvidence(
            legacyWellKnownFocusAdvertised: legacyWellKnownFocusAdvertised,
            legacyConvenienceBooleanSupported: legacyConvenienceBooleanSupported
        )
        let server = MatrixRTCServerQualificationEvidence(
            binding: binding,
            snapshotIntegrity: try snapshotIntegrityValue,
            serverAdvertisement: try serverAdvertisementValue,
            transportEvidence: try transportEvidenceValue,
            diagnostics: diagnostics
        )
        let sdk = MatrixRTCSDKQualificationEvidence(
            binding: binding,
            artifactIdentity: try XCTUnwrap(MatrixRTCSDKArtifactIdentity(
                sourceRevision: sdkSourceRevision,
                capabilitySnapshotDigestSHA256: sdkCapabilitySnapshotDigestSHA256
            )),
            capabilities: try Set(sdkCapabilities.map(capabilityValue))
        )
        return (
            MatrixRTCQualificationSelection(
                origin: origin,
                generation: generation,
                expectedSDKArtifactIdentity: sdk.artifactIdentity
            ),
            MatrixRTCQualificationEvidence(server: server, sdk: sdk)
        )
    }

    private var snapshotIntegrityValue: MatrixRTCSnapshotIntegrity {
        get throws {
            switch snapshotIntegrity {
            case "missing": return .missing
            case "matched": return .matched
            case "digest_mismatch": return .digestMismatch
            case "malformed": return .malformed
            default: throw FixtureError.unknownValue(snapshotIntegrity)
            }
        }
    }

    private var serverAdvertisementValue: MatrixRTCServerAdvertisement {
        get throws {
            switch serverAdvertisement {
            case "missing": return .missing
            case "disabled": return .disabled
            case "malformed": return .malformed
            case "supported": return .supported
            default: throw FixtureError.unknownValue(serverAdvertisement)
            }
        }
    }

    private var transportEvidenceValue: MatrixRTCTransportEvidence {
        get throws {
            switch transportEvidence {
            case "missing": return .missing
            case "fallback_only": return .fallbackOnly
            case "authenticated_unsupported": return .authenticatedUnsupported
            case "authenticated_malformed": return .authenticatedMalformed
            case "authenticated_supported": return .authenticatedSupported
            default: throw FixtureError.unknownValue(transportEvidence)
            }
        }
    }

    private func capabilityValue(_ value: String) throws -> MatrixRTCSDKCapability {
        switch value {
        case "authenticated_transport_registry_without_fallback": return .authenticatedTransportRegistryWithoutFallback
        case "sticky_event_ephemeral_map": return .stickyEventEphemeralMap
        case "slot_member_lifecycle": return .slotMemberLifecycle
        case "delayed_leave_lifecycle": return .delayedLeaveLifecycle
        case "profile_aware_participant_device_snapshot": return .profileAwareParticipantDeviceSnapshot
        case "notification_and_decline": return .notificationAndDecline
        case "per_member_sender_key_lifecycle": return .perMemberSenderKeyLifecycle
        case "recipient_device_validation": return .recipientDeviceValidation
        case "bounded_transport_grant": return .boundedTransportGrant
        case "registered_transport_type_validation": return .registeredTransportTypeValidation
        case "complete_native_session_surface": return .completeNativeSessionSurface
        default: throw FixtureError.unknownValue(value)
        }
    }
}

private struct SDKCapabilityEvidenceDTO: Decodable {
    let comparison: [SDKCapabilityComparisonRow]

    func comparisonByName() throws -> [String: SDKCapabilityComparisonRow] {
        try Dictionary(uniqueKeysWithValues: comparison.map { row in
            _ = try row.canonicalEvaluatorCapability
            return (row.capability, row)
        })
    }

    func evaluatorComparisonRows() throws -> [MatrixRTCSDKCapability: SDKCapabilityComparisonRow] {
        var result: [MatrixRTCSDKCapability: SDKCapabilityComparisonRow] = [:]
        for row in comparison {
            guard let capability = try row.canonicalEvaluatorCapability else { continue }
            guard result.updateValue(row, forKey: capability) == nil else {
                throw FixtureError.duplicateValue(row.capability)
            }
        }
        return result
    }

    func pinnedEvaluatorCapabilities() throws -> Set<MatrixRTCSDKCapability> {
        Set(try evaluatorComparisonRows().compactMap { capability, row in
            row.pinnedHypha ? capability : nil
        })
    }
}

private struct SDKCapabilityComparisonRow: Decodable {
    let capability: String
    let currentUpstream: Bool
    let pinnedHypha: Bool
    let selectedProfile: Bool

    private enum CodingKeys: String, CodingKey {
        case capability
        case currentUpstream = "current_upstream"
        case pinnedHypha = "pinned_hypha"
        case selectedProfile = "selected_profile"
    }

    var canonicalEvaluatorCapability: MatrixRTCSDKCapability? {
        get throws {
            switch capability {
            case "legacy_well_known_livekit_boolean", "core_authenticated_transport_registry": return nil
            case "ffi_direct_authenticated_transport_registry_without_fallback": return .authenticatedTransportRegistryWithoutFallback
            case "sticky_event_ephemeral_map_surface": return .stickyEventEphemeralMap
            case "slot_member_lifecycle": return .slotMemberLifecycle
            case "delayed_leave_lifecycle": return .delayedLeaveLifecycle
            case "profile_aware_participant_device_snapshot": return .profileAwareParticipantDeviceSnapshot
            case "notification_and_decline": return .notificationAndDecline
            case "sender_key_lifecycle": return .perMemberSenderKeyLifecycle
            case "recipient_device_validation": return .recipientDeviceValidation
            case "bounded_transport_grant": return .boundedTransportGrant
            case "registered_transport_type_validation": return .registeredTransportTypeValidation
            case "complete_native_session_surface": return .completeNativeSessionSurface
            default: throw FixtureError.unknownValue(capability)
            }
        }
    }
}

private enum FixtureError: Error {
    case unknownValue(String)
    case duplicateValue(String)
}
