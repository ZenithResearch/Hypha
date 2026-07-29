public enum HyphaSecurityIndicatorSeverity: Equatable, Sendable {
    case unknown
    case recommended
    case secure
    case critical
}

public enum HyphaSecurityPrimaryDeviceAction: Equatable, Sendable {
    case setUpThisDevice
    case verifyWithAnotherHyphaDevice
    case continueDeviceSetupWithPassword
}

public enum HyphaSecurityRecoveryAction: Equatable, Sendable {
    case setUpRecovery
    case restoreEncryption
}

public enum HyphaSecurityLocalOperation: Equatable, Sendable {
    case idle
    case settingUpThisDevice
    case requestingVerificationFromAnotherHyphaDevice
    case comparingWithAnotherHyphaDevice(MatrixVerificationChallenge)
    case approvingAnotherHyphaDevice
    case verificationFailed(reason: String)
    case restoringEncryption
    case recoveryFailed(reason: String)
    case recoveryDiagnostic(MatrixCrossSigningDiagnosticReceipt)
}

public struct HyphaSecurityPresentationState: Equatable, Sendable {
    public let indicatorSeverity: HyphaSecurityIndicatorSeverity
    public let primaryDeviceAction: HyphaSecurityPrimaryDeviceAction?
    public let recoveryAction: HyphaSecurityRecoveryAction?
    public let localOperation: HyphaSecurityLocalOperation
    public let requiresPersistentCriticalBanner: Bool

    public init(
        indicatorSeverity: HyphaSecurityIndicatorSeverity,
        primaryDeviceAction: HyphaSecurityPrimaryDeviceAction?,
        recoveryAction: HyphaSecurityRecoveryAction?,
        localOperation: HyphaSecurityLocalOperation,
        requiresPersistentCriticalBanner: Bool
    ) {
        self.indicatorSeverity = indicatorSeverity
        self.primaryDeviceAction = primaryDeviceAction
        self.recoveryAction = recoveryAction
        self.localOperation = localOperation
        self.requiresPersistentCriticalBanner = requiresPersistentCriticalBanner
    }
}

public enum HyphaSecurityPresentationPolicy {
    public static func presentation(
        trustState: MatrixDeviceTrustState,
        firstDeviceTrustBootstrapState: MatrixFirstDeviceTrustBootstrapState,
        verificationFlowState: MatrixVerificationFlowState,
        recoveryState: MatrixRecoveryState,
        peerVerificationEligibility: MatrixPeerVerificationEligibility = .unavailable
    ) -> HyphaSecurityPresentationState {
        let requiresPersistentCriticalBanner =
            trustState == .invalidSignature ||
            firstDeviceTrustBootstrapState == .invalidSignature

        return HyphaSecurityPresentationState(
            indicatorSeverity: indicatorSeverity(
                trustState: trustState,
                requiresPersistentCriticalBanner: requiresPersistentCriticalBanner
            ),
            primaryDeviceAction: primaryDeviceAction(
                trustState: trustState,
                firstDeviceTrustBootstrapState: firstDeviceTrustBootstrapState,
                verificationFlowState: verificationFlowState,
                peerVerificationEligibility: peerVerificationEligibility,
                requiresPersistentCriticalBanner: requiresPersistentCriticalBanner
            ),
            recoveryAction: recoveryAction(for: recoveryState),
            localOperation: localOperation(
                firstDeviceTrustBootstrapState: firstDeviceTrustBootstrapState,
                verificationFlowState: verificationFlowState,
                recoveryState: recoveryState
            ),
            requiresPersistentCriticalBanner: requiresPersistentCriticalBanner
        )
    }

    private static func indicatorSeverity(
        trustState: MatrixDeviceTrustState,
        requiresPersistentCriticalBanner: Bool
    ) -> HyphaSecurityIndicatorSeverity {
        if requiresPersistentCriticalBanner {
            return .critical
        }

        switch trustState {
        case .unknown, .unavailable:
            return .unknown
        case .unsigned:
            return .recommended
        case .verifiedByCurrentSelfSigningKey:
            return .secure
        case .invalidSignature:
            return .critical
        }
    }

    private static func primaryDeviceAction(
        trustState: MatrixDeviceTrustState,
        firstDeviceTrustBootstrapState: MatrixFirstDeviceTrustBootstrapState,
        verificationFlowState: MatrixVerificationFlowState,
        peerVerificationEligibility: MatrixPeerVerificationEligibility,
        requiresPersistentCriticalBanner: Bool
    ) -> HyphaSecurityPrimaryDeviceAction? {
        guard verificationFlowState == .idle,
              trustState == .unsigned,
              !requiresPersistentCriticalBanner else {
            return nil
        }

        switch firstDeviceTrustBootstrapState {
        case .notBootstrapped:
            switch peerVerificationEligibility {
            case .eligiblePeer:
                return .verifyWithAnotherHyphaDevice
            case .noEligiblePeer:
                return .setUpThisDevice
            case .unavailable:
                return nil
            }
        case .passwordRequired:
            return .continueDeviceSetupWithPassword
        case .bootstrapping,
             .verifiedByCurrentSelfSigningKey,
             .invalidSignature,
             .unavailable:
            return nil
        }
    }

    private static func recoveryAction(
        for recoveryState: MatrixRecoveryState
    ) -> HyphaSecurityRecoveryAction? {
        switch recoveryState {
        case .unavailable:
            return .setUpRecovery
        case .available, .incomplete, .failed, .diagnostic:
            return .restoreEncryption
        case .unknown, .restoring, .ready:
            return nil
        }
    }

    private static func localOperation(
        firstDeviceTrustBootstrapState: MatrixFirstDeviceTrustBootstrapState,
        verificationFlowState: MatrixVerificationFlowState,
        recoveryState: MatrixRecoveryState
    ) -> HyphaSecurityLocalOperation {
        switch verificationFlowState {
        case .requesting:
            return .requestingVerificationFromAnotherHyphaDevice
        case let .challenge(challenge):
            return .comparingWithAnotherHyphaDevice(challenge)
        case .approving:
            return .approvingAnotherHyphaDevice
        case let .failed(reason):
            return .verificationFailed(reason: reason)
        case .idle:
            break
        }

        if firstDeviceTrustBootstrapState == .bootstrapping {
            return .settingUpThisDevice
        }

        switch recoveryState {
        case .restoring:
            return .restoringEncryption
        case let .failed(reason):
            return .recoveryFailed(reason: reason)
        case let .diagnostic(receipt):
            return .recoveryDiagnostic(receipt)
        case .unknown, .unavailable, .available, .incomplete, .ready:
            return .idle
        }
    }
}
