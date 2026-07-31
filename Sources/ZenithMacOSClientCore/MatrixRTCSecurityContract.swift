public enum MatrixRTCPeerEvidenceState: Equatable, Sendable {
    case proven
    case missing
    case invalid
    case malformed
}

public enum MatrixRTCLocalSASEvidence: Equatable, Sendable {
    case verified
    case notVerified
    case malformed
}

public enum MatrixRTCRevocationEvidence: Equatable, Sendable {
    case notRevoked
    case revoked
    case missing
    case malformed
}

public struct MatrixRTCPeerTrustEvidence: Equatable, Sendable {
    public let authentication: MatrixRTCPeerEvidenceState
    public let currentDeviceChain: MatrixRTCPeerEvidenceState
    public let currentCrossSigningChain: MatrixRTCPeerEvidenceState
    public let localSAS: MatrixRTCLocalSASEvidence
    public let revocation: MatrixRTCRevocationEvidence
}

public enum MatrixRTCPeerTrustClassification: Equatable, Sendable {
    case authenticated
    case crossSigned
    case locallySASVerified
    case invalid
    case revoked
    case unknown
    case malformed
}

public enum MatrixRTCPeerTrustClassifier: Equatable, Sendable {
    public static func classify(
        _ evidence: MatrixRTCPeerTrustEvidence
    ) -> MatrixRTCPeerTrustClassification {
        if evidence.revocation == .revoked {
            return .revoked
        }
        if evidence.authentication == .invalid
            || evidence.currentDeviceChain == .invalid
            || evidence.currentCrossSigningChain == .invalid {
            return .invalid
        }
        if evidence.authentication == .malformed
            || evidence.currentDeviceChain == .malformed
            || evidence.currentCrossSigningChain == .malformed
            || evidence.localSAS == .malformed
            || evidence.revocation == .malformed {
            return .malformed
        }
        if evidence.revocation == .missing || evidence.authentication != .proven {
            return .unknown
        }
        if evidence.currentDeviceChain != .proven
            || evidence.currentCrossSigningChain != .proven {
            return .authenticated
        }
        if evidence.localSAS == .verified {
            return .locallySASVerified
        }
        return .crossSigned
    }
}

public enum MatrixRTCSecretKind: CaseIterable, Equatable, Sendable {
    case matrixAccessToken
    case openIDToken
    case senderKey
    case transportGrant
    case authorizationHeader

    public var ownershipMetadata: MatrixRTCSecretOwnershipMetadata {
        switch self {
        case .matrixAccessToken:
            return MatrixRTCSecretOwnershipMetadata(
                owner: .matrixSession,
                lifetime: .sessionBound,
                redaction: .omitFromQualificationEvidenceAndDescriptions
            )
        case .openIDToken:
            return MatrixRTCSecretOwnershipMetadata(
                owner: .homeserverTokenExchange,
                lifetime: .singleExchange,
                redaction: .omitFromQualificationEvidenceAndDescriptions
            )
        case .senderKey:
            return MatrixRTCSecretOwnershipMetadata(
                owner: .matrixRTCCrypto,
                lifetime: .membershipGenerationBound,
                redaction: .omitFromQualificationEvidenceAndDescriptions
            )
        case .transportGrant:
            return MatrixRTCSecretOwnershipMetadata(
                owner: .transportAuthorization,
                lifetime: .callLifecycleBound,
                redaction: .omitFromQualificationEvidenceAndDescriptions
            )
        case .authorizationHeader:
            return MatrixRTCSecretOwnershipMetadata(
                owner: .requestBoundary,
                lifetime: .singleRequest,
                redaction: .omitFromQualificationEvidenceAndDescriptions
            )
        }
    }
}

public enum MatrixRTCSecretOwner: Equatable, Sendable {
    case matrixSession
    case homeserverTokenExchange
    case matrixRTCCrypto
    case transportAuthorization
    case requestBoundary
}

public enum MatrixRTCSecretLifetime: Equatable, Sendable {
    case sessionBound
    case singleExchange
    case membershipGenerationBound
    case callLifecycleBound
    case singleRequest
}

public enum MatrixRTCSecretRedaction: Equatable, Sendable {
    case omitFromQualificationEvidenceAndDescriptions
}

public struct MatrixRTCSecretOwnershipMetadata: Equatable, Sendable {
    public let owner: MatrixRTCSecretOwner
    public let lifetime: MatrixRTCSecretLifetime
    public let redaction: MatrixRTCSecretRedaction
}

public struct MatrixRTCDigestIdentifier: Equatable, Sendable {
    public let sha256: String

    public init?(sha256: String) {
        guard sha256.utf8.count == 64,
              sha256.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
              }) else {
            return nil
        }
        self.sha256 = sha256
    }
}

public struct MatrixRTCOriginLifecycleIdentity: Equatable, Sendable {
    public let account: MatrixRTCDigestIdentifier
    public let homeserver: MatrixRTCDigestIdentifier
    public let originRoom: MatrixRTCDigestIdentifier
    public let device: MatrixRTCDigestIdentifier
    public let profile: MatrixRTCDigestIdentifier
    public let generation: UInt64
}

public enum MatrixRTCOriginEvidenceValidity: Equatable, Sendable {
    case valid
    case missing
    case invalid
    case malformed
}

public struct MatrixRTCOriginLifecycleContext: Equatable, Sendable {
    public let identity: MatrixRTCOriginLifecycleIdentity
    public let session: MatrixRTCOriginEvidenceValidity
    public let originRoom: MatrixRTCOriginEvidenceValidity
    public let presentedRoom: MatrixRTCDigestIdentifier
}

public enum MatrixRTCOriginLifecycleAction: Equatable, Sendable {
    case returnToOrigin
    case leaveAndSwitch
    case cancel
}

public enum MatrixRTCOriginLifecycleRequest: Equatable, Sendable {
    case present
    case returnToOrigin
    case requestAccountSwitch(to: MatrixRTCDigestIdentifier)
    case leaveAndSwitch(to: MatrixRTCDigestIdentifier)
    case cancelAccountSwitch
    case beginSecondCall
}

public enum MatrixRTCOriginInvalidationReason: Equatable, Sendable {
    case accountMismatch
    case homeserverMismatch
    case sessionMissing
    case sessionInvalid
    case sessionMalformed
    case originRoomMismatch
    case originRoomMissing
    case originRoomInvalid
    case originRoomMalformed
    case deviceMismatch
    case profileMismatch
    case generationMismatch
}

public enum MatrixRTCOriginLifecycleDecision: Equatable, Sendable {
    case presentAtOrigin
    case preservePresentation(returnAction: MatrixRTCOriginLifecycleAction)
    case requireAccountSwitchChoice(
        confirm: MatrixRTCOriginLifecycleAction,
        cancel: MatrixRTCOriginLifecycleAction
    )
    case leaveAndSwitch
    case cancelPreservingOrigin
    case blockSecondCall
    case invalidated(MatrixRTCOriginInvalidationReason)
}

public enum MatrixRTCOriginLifecycleEvaluator: Equatable, Sendable {
    public static func evaluate(
        expectedOrigin: MatrixRTCOriginLifecycleIdentity,
        context: MatrixRTCOriginLifecycleContext,
        request: MatrixRTCOriginLifecycleRequest
    ) -> MatrixRTCOriginLifecycleDecision {
        if context.identity.account != expectedOrigin.account {
            return .invalidated(.accountMismatch)
        }
        if context.identity.homeserver != expectedOrigin.homeserver {
            return .invalidated(.homeserverMismatch)
        }
        switch context.session {
        case .missing:
            return .invalidated(.sessionMissing)
        case .invalid:
            return .invalidated(.sessionInvalid)
        case .malformed:
            return .invalidated(.sessionMalformed)
        case .valid:
            break
        }
        if context.identity.originRoom != expectedOrigin.originRoom {
            return .invalidated(.originRoomMismatch)
        }
        switch context.originRoom {
        case .missing:
            return .invalidated(.originRoomMissing)
        case .invalid:
            return .invalidated(.originRoomInvalid)
        case .malformed:
            return .invalidated(.originRoomMalformed)
        case .valid:
            break
        }
        if context.identity.device != expectedOrigin.device {
            return .invalidated(.deviceMismatch)
        }
        if context.identity.profile != expectedOrigin.profile {
            return .invalidated(.profileMismatch)
        }
        if context.identity.generation != expectedOrigin.generation {
            return .invalidated(.generationMismatch)
        }

        switch request {
        case .present:
            if context.presentedRoom == expectedOrigin.originRoom {
                return .presentAtOrigin
            }
            return .preservePresentation(returnAction: .returnToOrigin)
        case .returnToOrigin:
            return .presentAtOrigin
        case let .requestAccountSwitch(account):
            if account == expectedOrigin.account {
                return .presentAtOrigin
            }
            return .requireAccountSwitchChoice(confirm: .leaveAndSwitch, cancel: .cancel)
        case let .leaveAndSwitch(account):
            if account == expectedOrigin.account {
                return .presentAtOrigin
            }
            return .leaveAndSwitch
        case .cancelAccountSwitch:
            return .cancelPreservingOrigin
        case .beginSecondCall:
            return .blockSecondCall
        }
    }
}

public enum MatrixRTCUnsupportedReason: CaseIterable, Equatable, Sendable {
    case qualificationUnavailable
    case peerTrustUnavailable
    case originInvalidated
    case nativeSessionUnavailable

    public var title: String {
        switch self {
        case .qualificationUnavailable:
            return "Calling unavailable"
        case .peerTrustUnavailable:
            return "Peer verification unavailable"
        case .originInvalidated:
            return "Call context changed"
        case .nativeSessionUnavailable:
            return "Calling support unavailable"
        }
    }

    public var description: String {
        switch self {
        case .qualificationUnavailable:
            return "Required capability evidence is not available."
        case .peerTrustUnavailable:
            return "Required peer evidence is not available."
        case .originInvalidated:
            return "The original call context is no longer valid."
        case .nativeSessionUnavailable:
            return "Native calling support is not available."
        }
    }

    public var recovery: String {
        switch self {
        case .qualificationUnavailable:
            return "Repeat the capability check before trying again."
        case .peerTrustUnavailable:
            return "Repeat peer verification before trying again."
        case .originInvalidated:
            return "Return to the original context and try again."
        case .nativeSessionUnavailable:
            return "Update support and try again later."
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .qualificationUnavailable:
            return "Calling unavailable due to missing capability evidence"
        case .peerTrustUnavailable:
            return "Calling unavailable due to missing peer verification"
        case .originInvalidated:
            return "Calling unavailable because the call context changed"
        case .nativeSessionUnavailable:
            return "Calling unavailable because native support is missing"
        }
    }

    public var accessibilityHint: String {
        switch self {
        case .qualificationUnavailable:
            return "Repeat the capability check before retrying."
        case .peerTrustUnavailable:
            return "Repeat peer verification before retrying."
        case .originInvalidated:
            return "Return to the original context before retrying."
        case .nativeSessionUnavailable:
            return "Update support before retrying."
        }
    }
}

public struct MatrixRTCUnsupportedPresentation: Equatable, Sendable {
    public let reason: MatrixRTCUnsupportedReason
    public let title: String
    public let description: String
    public let recovery: String
    public let accessibilityLabel: String
    public let accessibilityHint: String

    public init(reason: MatrixRTCUnsupportedReason) {
        self.reason = reason
        title = reason.title
        description = reason.description
        recovery = reason.recovery
        accessibilityLabel = reason.accessibilityLabel
        accessibilityHint = reason.accessibilityHint
    }
}

public enum MatrixRTCFuturePresentationScope: Equatable, Sendable {
    case futureOnlyNonruntime
}

public enum MatrixRTCFutureCallAffordance: Equatable, Sendable {
    case selectedRoomTopRight
}

public enum MatrixRTCFutureCallSurface: Equatable, Sendable {
    case messagesLikeTrailingInspector
}

public enum MatrixRTCFutureCallPresentationState: CaseIterable, Equatable, Sendable {
    case unavailable
    case incoming
    case preJoin
    case active
}

public enum MatrixRTCFutureUnavailableAction: Equatable, Sendable {
    case exposeUnavailableReason
}

public enum MatrixRTCFutureIncomingBehavior: Equatable, Sendable {
    case passive
}

public enum MatrixRTCFutureInspectorDismissal: Equatable, Sendable {
    case presentationOnly
}

public struct MatrixRTCFutureCallPresentationContract: Equatable, Sendable {
    public let scope: MatrixRTCFuturePresentationScope
    public let affordance: MatrixRTCFutureCallAffordance
    public let surface: MatrixRTCFutureCallSurface
    public let states: [MatrixRTCFutureCallPresentationState]
    public let unavailableAction: MatrixRTCFutureUnavailableAction
    public let incomingBehavior: MatrixRTCFutureIncomingBehavior
    public let dismissal: MatrixRTCFutureInspectorDismissal

    public static let selectedRoom = MatrixRTCFutureCallPresentationContract(
        scope: .futureOnlyNonruntime,
        affordance: .selectedRoomTopRight,
        surface: .messagesLikeTrailingInspector,
        states: [.unavailable, .incoming, .preJoin, .active],
        unavailableAction: .exposeUnavailableReason,
        incomingBehavior: .passive,
        dismissal: .presentationOnly
    )
}
