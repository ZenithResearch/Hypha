import XCTest
@testable import ZenithMacOSClientCore

final class HyphaSecurityPresentationPolicyTests: XCTestCase {
    func testUnknownAuthorityStaysUnknownWithoutActionsOrBanner() {
        let presentation = makePresentation(
            trust: .unknown,
            bootstrap: .notBootstrapped,
            recovery: .unknown
        )

        XCTAssertEqual(presentation.indicatorSeverity, .unknown)
        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertEqual(presentation.localOperation, .idle)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testUnsignedFirstDeviceOffersOnlyAuthoritativeSetupAction() {
        let presentation = makePresentation(
            trust: .unsigned,
            bootstrap: .notBootstrapped,
            peerEligibility: .noEligiblePeer
        )

        XCTAssertEqual(presentation.indicatorSeverity, .recommended)
        XCTAssertEqual(presentation.primaryDeviceAction, .setUpThisDevice)
        XCTAssertEqual(presentation.localOperation, .idle)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testUnsignedDeviceOffersPeerVerificationOnlyWhenEligibilityIsProven() {
        let presentation = makePresentation(
            trust: .unsigned,
            bootstrap: .notBootstrapped,
            peerEligibility: .eligiblePeer
        )

        XCTAssertEqual(presentation.primaryDeviceAction, .verifyWithAnotherHyphaDevice)
    }

    func testUnavailablePeerEligibilityDoesNotGuessFirstDeviceOrExposePeerVerification() {
        let presentation = makePresentation(
            trust: .unsigned,
            bootstrap: .notBootstrapped,
            peerEligibility: .unavailable
        )

        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertEqual(presentation.indicatorSeverity, .recommended)
    }

    func testPasswordRequirementOffersContinuationInsteadOfStartingAnotherAction() {
        let presentation = makePresentation(trust: .unsigned, bootstrap: .passwordRequired)

        XCTAssertEqual(presentation.primaryDeviceAction, .continueDeviceSetupWithPassword)
        XCTAssertEqual(presentation.localOperation, .idle)
    }

    func testBootstrappingSuppressesActionsAndReportsLocalOperation() {
        let presentation = makePresentation(trust: .unsigned, bootstrap: .bootstrapping)

        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertEqual(presentation.localOperation, .settingUpThisDevice)
    }

    func testFailedDeviceSetupIsVisibleAndOffersTheSameAuthoritativeRetryPath() {
        let presentation = makePresentation(
            trust: .unsigned,
            bootstrap: .failed(reason: "Device security setup failed. Try again."),
            peerEligibility: .noEligiblePeer
        )

        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertEqual(
            presentation.localOperation,
            .deviceSetupFailed(reason: "Device security setup failed. Try again.")
        )
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testVerifiedTrustIsTheOnlyHealthySuccessState() {
        let presentation = makePresentation(
            trust: .verifiedByCurrentSelfSigningKey,
            bootstrap: .verifiedByCurrentSelfSigningKey,
            recovery: .ready
        )

        XCTAssertEqual(presentation.indicatorSeverity, .secure)
        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testInvalidTrustSignatureRequiresPersistentCriticalPresentation() {
        let presentation = makePresentation(trust: .invalidSignature, bootstrap: .notBootstrapped)

        XCTAssertEqual(presentation.indicatorSeverity, .critical)
        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertTrue(presentation.requiresPersistentCriticalBanner)
    }

    func testUnavailableAuthorityDoesNotClaimSuccessOrExposeAnUnprovenAction() {
        let presentation = makePresentation(
            trust: .unavailable,
            bootstrap: .unavailable,
            recovery: .unknown
        )

        XCTAssertEqual(presentation.indicatorSeverity, .unknown)
        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertNil(presentation.recoveryAction)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testBootstrapAuthorityCannotPromoteUnknownTrustToSuccess() {
        let presentation = makePresentation(
            trust: .unknown,
            bootstrap: .verifiedByCurrentSelfSigningKey,
            recovery: .ready
        )

        XCTAssertEqual(presentation.indicatorSeverity, .unknown)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testActiveVerificationFlowMapsToLocalHyphaOperationWithoutDeviceSetupAction() {
        let challenge = MatrixVerificationChallenge.decimals([111, 222, 333])
        let cases: [(MatrixVerificationFlowState, HyphaSecurityLocalOperation)] = [
            (.requesting, .requestingVerificationFromAnotherHyphaDevice),
            (.challenge(challenge), .comparingWithAnotherHyphaDevice(challenge)),
            (.approving, .approvingAnotherHyphaDevice),
            (.failed(reason: "Timed out"), .verificationFailed(reason: "Timed out"))
        ]

        for (flow, expectedOperation) in cases {
            let presentation = makePresentation(
                trust: .unsigned,
                bootstrap: .notBootstrapped,
                verification: flow
            )

            XCTAssertNil(presentation.primaryDeviceAction, "Flow \(flow) must suppress device setup")
            XCTAssertEqual(presentation.localOperation, expectedOperation)
            XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
        }
    }

    func testDeviceSetupAndVerificationPresentationAreNeverSimultaneous() {
        let bootstrapStates: [MatrixFirstDeviceTrustBootstrapState] = [
            .notBootstrapped,
            .bootstrapping,
            .passwordRequired,
            .verifiedByCurrentSelfSigningKey,
            .invalidSignature,
            .unavailable,
            .failed(reason: "Unavailable")
        ]
        let activeVerificationStates: [MatrixVerificationFlowState] = [
            .requesting,
            .challenge(.emojis([.init(symbol: "🐙", description: "Octopus")])),
            .approving,
            .failed(reason: "Unavailable")
        ]

        for bootstrap in bootstrapStates {
            for verification in activeVerificationStates {
                let presentation = makePresentation(
                    trust: .unsigned,
                    bootstrap: bootstrap,
                    verification: verification
                )
                XCTAssertNil(
                    presentation.primaryDeviceAction,
                    "Setup action leaked for bootstrap=\(bootstrap), verification=\(verification)"
                )
            }
        }
    }

    func testOnlyProvenInvalidTrustOrBootstrapStateRequiresPersistentCriticalBanner() {
        let trustStates: [MatrixDeviceTrustState] = [
            .unknown,
            .unsigned,
            .invalidSignature,
            .verifiedByCurrentSelfSigningKey,
            .unavailable
        ]
        let bootstrapStates: [MatrixFirstDeviceTrustBootstrapState] = [
            .notBootstrapped,
            .bootstrapping,
            .passwordRequired,
            .verifiedByCurrentSelfSigningKey,
            .invalidSignature,
            .unavailable,
            .failed(reason: "Unavailable")
        ]

        for trust in trustStates {
            for bootstrap in bootstrapStates {
                let presentation = makePresentation(trust: trust, bootstrap: bootstrap)
                let expectedCritical = trust == .invalidSignature || bootstrap == .invalidSignature

                XCTAssertEqual(
                    presentation.requiresPersistentCriticalBanner,
                    expectedCritical,
                    "Unexpected critical decision for trust=\(trust), bootstrap=\(bootstrap)"
                )
                XCTAssertEqual(
                    presentation.indicatorSeverity == .critical,
                    expectedCritical,
                    "Critical severity diverged for trust=\(trust), bootstrap=\(bootstrap)"
                )
            }
        }
    }

    func testRecoveryUnavailableIsOptionalSetupAndNeverABanner() {
        let presentation = makePresentation(
            trust: .verifiedByCurrentSelfSigningKey,
            bootstrap: .verifiedByCurrentSelfSigningKey,
            recovery: .unavailable
        )

        XCTAssertEqual(presentation.recoveryAction, .setUpRecovery)
        XCTAssertEqual(presentation.indicatorSeverity, .secure)
        XCTAssertFalse(presentation.requiresPersistentCriticalBanner)
    }

    func testRecoveryStatesMapToOptionalActionsAndLocalOperationsWithoutChangingTrustSeverity() {
        let diagnostic = diagnosticReceipt()
        let cases: [(MatrixRecoveryState, HyphaSecurityRecoveryAction?, HyphaSecurityLocalOperation)] = [
            (.unknown, nil, .idle),
            (.unavailable, .setUpRecovery, .idle),
            (.available, .restoreEncryption, .idle),
            (.incomplete, .restoreEncryption, .idle),
            (.restoring, nil, .restoringEncryption),
            (.ready, nil, .idle),
            (.failed(reason: "Bad key"), .restoreEncryption, .recoveryFailed(reason: "Bad key")),
            (.diagnostic(diagnostic), .restoreEncryption, .recoveryDiagnostic(diagnostic))
        ]

        for (recovery, expectedAction, expectedOperation) in cases {
            let presentation = makePresentation(
                trust: .verifiedByCurrentSelfSigningKey,
                bootstrap: .verifiedByCurrentSelfSigningKey,
                recovery: recovery
            )

            XCTAssertEqual(presentation.recoveryAction, expectedAction, "Recovery state: \(recovery)")
            XCTAssertEqual(presentation.localOperation, expectedOperation, "Recovery state: \(recovery)")
            XCTAssertEqual(presentation.indicatorSeverity, .secure, "Recovery must not alter trust severity")
            XCTAssertFalse(presentation.requiresPersistentCriticalBanner, "Recovery must remain non-banner")
        }
    }

    func testActiveVerificationTakesPresentationPrecedenceOverRecoveryOperation() {
        let presentation = makePresentation(
            trust: .unsigned,
            bootstrap: .bootstrapping,
            verification: .challenge(.decimals([1, 2, 3])),
            recovery: .restoring
        )

        XCTAssertNil(presentation.primaryDeviceAction)
        XCTAssertEqual(
            presentation.localOperation,
            .comparingWithAnotherHyphaDevice(.decimals([1, 2, 3]))
        )
    }

    private func makePresentation(
        trust: MatrixDeviceTrustState = .unknown,
        bootstrap: MatrixFirstDeviceTrustBootstrapState = .notBootstrapped,
        verification: MatrixVerificationFlowState = .idle,
        recovery: MatrixRecoveryState = .unknown,
        peerEligibility: MatrixPeerVerificationEligibility = .unavailable
    ) -> HyphaSecurityPresentationState {
        HyphaSecurityPresentationPolicy.presentation(
            trustState: trust,
            firstDeviceTrustBootstrapState: bootstrap,
            verificationFlowState: verification,
            recoveryState: recovery,
            peerVerificationEligibility: peerEligibility
        )
    }

    private func diagnosticReceipt() -> MatrixCrossSigningDiagnosticReceipt {
        MatrixCrossSigningDiagnosticReceipt(
            publicIdentityRefreshed: true,
            privateSelfSigningKeyPresent: true,
            privateSelfSigningKeyMatchesCurrentPublicIdentity: false,
            localOwnDeviceKeyMatchesServerDeviceKey: true,
            signedObjectMatchesFreshServerDeviceObject: true,
            generatedSignatureValidLocally: false,
            uploadTransport: .accepted,
            uploadProcessing: .invalidSignature,
            postUploadServerSignaturePresent: false,
            backupRepair: .failed
        )
    }
}
