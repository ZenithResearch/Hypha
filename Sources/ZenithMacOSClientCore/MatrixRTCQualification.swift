public struct MatrixRTCOriginBinding: Equatable, Sendable {
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

public struct MatrixRTCEvidenceBinding: Equatable, Sendable {
    public let profileID: String
    public let profileDigestSHA256: String
    public let origin: MatrixRTCOriginBinding
    public let generation: UInt64

    public init(
        profileID: String,
        profileDigestSHA256: String,
        origin: MatrixRTCOriginBinding,
        generation: UInt64
    ) {
        self.profileID = profileID
        self.profileDigestSHA256 = profileDigestSHA256
        self.origin = origin
        self.generation = generation
    }
}

/// Caller-supplied identity attesting which SDK artifact produced a capability snapshot.
/// This pure SDK-neutral value does not verify signatures or read files or the network.
public struct MatrixRTCSDKArtifactIdentity: Equatable, Sendable {
    public let sourceRevision: String
    public let capabilitySnapshotDigestSHA256: String

    public init?(sourceRevision: String, capabilitySnapshotDigestSHA256: String) {
        guard Self.isLowercaseHex(sourceRevision, count: 40),
              Self.isLowercaseHex(capabilitySnapshotDigestSHA256, count: 64) else {
            return nil
        }
        self.sourceRevision = sourceRevision
        self.capabilitySnapshotDigestSHA256 = capabilitySnapshotDigestSHA256
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }
}

public struct MatrixRTCQualificationSelection: Equatable, Sendable {
    public let origin: MatrixRTCOriginBinding
    public let generation: UInt64
    public let expectedSDKArtifactIdentity: MatrixRTCSDKArtifactIdentity

    public init(
        origin: MatrixRTCOriginBinding,
        generation: UInt64,
        expectedSDKArtifactIdentity: MatrixRTCSDKArtifactIdentity
    ) {
        self.origin = origin
        self.generation = generation
        self.expectedSDKArtifactIdentity = expectedSDKArtifactIdentity
    }
}

public enum MatrixRTCSnapshotIntegrity: Equatable, Sendable {
    case missing
    case matched
    case digestMismatch
    case malformed
}

public enum MatrixRTCServerAdvertisement: Equatable, Sendable {
    case missing
    case disabled
    case malformed
    case supported
}

public enum MatrixRTCTransportEvidence: Equatable, Sendable {
    case missing
    case fallbackOnly
    case authenticatedUnsupported
    case authenticatedMalformed
    case authenticatedSupported
}

public enum MatrixRTCSDKCapability: CaseIterable, Equatable, Hashable, Sendable {
    case authenticatedTransportRegistryWithoutFallback
    case stickyEventEphemeralMap
    case slotMemberLifecycle
    case delayedLeaveLifecycle
    case profileAwareParticipantDeviceSnapshot
    case notificationAndDecline
    case perMemberSenderKeyLifecycle
    case recipientDeviceValidation
    case boundedTransportGrant
    case registeredTransportTypeValidation
    case completeNativeSessionSurface
}

public struct MatrixRTCDiagnosticEvidence: Equatable, Sendable {
    public let legacyWellKnownFocusAdvertised: Bool
    public let legacyConvenienceBooleanSupported: Bool

    public init(
        legacyWellKnownFocusAdvertised: Bool,
        legacyConvenienceBooleanSupported: Bool
    ) {
        self.legacyWellKnownFocusAdvertised = legacyWellKnownFocusAdvertised
        self.legacyConvenienceBooleanSupported = legacyConvenienceBooleanSupported
    }
}

public struct MatrixRTCServerQualificationEvidence: Equatable, Sendable {
    public let binding: MatrixRTCEvidenceBinding
    public let snapshotIntegrity: MatrixRTCSnapshotIntegrity
    public let serverAdvertisement: MatrixRTCServerAdvertisement
    public let transportEvidence: MatrixRTCTransportEvidence
    public let diagnostics: MatrixRTCDiagnosticEvidence

    public init(
        binding: MatrixRTCEvidenceBinding,
        snapshotIntegrity: MatrixRTCSnapshotIntegrity,
        serverAdvertisement: MatrixRTCServerAdvertisement,
        transportEvidence: MatrixRTCTransportEvidence,
        diagnostics: MatrixRTCDiagnosticEvidence
    ) {
        self.binding = binding
        self.snapshotIntegrity = snapshotIntegrity
        self.serverAdvertisement = serverAdvertisement
        self.transportEvidence = transportEvidence
        self.diagnostics = diagnostics
    }
}

public struct MatrixRTCSDKQualificationEvidence: Equatable, Sendable {
    public let binding: MatrixRTCEvidenceBinding
    public let artifactIdentity: MatrixRTCSDKArtifactIdentity
    public let capabilities: Set<MatrixRTCSDKCapability>

    public init(
        binding: MatrixRTCEvidenceBinding,
        artifactIdentity: MatrixRTCSDKArtifactIdentity,
        capabilities: Set<MatrixRTCSDKCapability>
    ) {
        self.binding = binding
        self.artifactIdentity = artifactIdentity
        self.capabilities = capabilities
    }
}

public struct MatrixRTCQualificationEvidence: Equatable, Sendable {
    public let server: MatrixRTCServerQualificationEvidence?
    public let sdk: MatrixRTCSDKQualificationEvidence?

    public init(
        server: MatrixRTCServerQualificationEvidence?,
        sdk: MatrixRTCSDKQualificationEvidence?
    ) {
        self.server = server
        self.sdk = sdk
    }
}

public enum MatrixRTCQualificationReason: Equatable, Sendable {
    case missingServerEvidence
    case missingSDKEvidence
    case mixedProfile
    case mixedProfileDigest
    case mixedGeneration
    case mixedOrigin
    case profileMismatch
    case profileDigestMismatch
    case originMismatch
    case staleEvidence
    case generationMismatch
    case snapshotMissing
    case snapshotDigestMismatch
    case snapshotMalformed
    case serverAdvertisementMissing
    case serverAdvertisementDisabled
    case serverAdvertisementMalformed
    case authenticatedTransportMissing
    case fallbackOnly
    case authenticatedTransportUnsupported
    case authenticatedTransportMalformed
    case sdkSourceRevisionMismatch
    case sdkCapabilitySnapshotDigestMismatch
    case missingSDKCapability(MatrixRTCSDKCapability)

    public var title: String {
        switch self {
        case .missingServerEvidence:
            return "Server evidence unavailable"
        case .missingSDKEvidence:
            return "SDK evidence unavailable"
        case .mixedProfile:
            return "Evidence profiles differ"
        case .mixedProfileDigest:
            return "Evidence profile digests differ"
        case .mixedGeneration:
            return "Evidence generations differ"
        case .mixedOrigin:
            return "Evidence origins differ"
        case .profileMismatch:
            return "Selected profile mismatch"
        case .profileDigestMismatch:
            return "Selected profile digest mismatch"
        case .originMismatch:
            return "Selected origin mismatch"
        case .staleEvidence:
            return "Evidence is stale"
        case .generationMismatch:
            return "Evidence generation mismatch"
        case .snapshotMissing:
            return "Profile snapshot unavailable"
        case .snapshotDigestMismatch:
            return "Profile snapshot digest mismatch"
        case .snapshotMalformed:
            return "Profile snapshot malformed"
        case .serverAdvertisementMissing:
            return "Feature advertisement unavailable"
        case .serverAdvertisementDisabled:
            return "Feature advertisement disabled"
        case .serverAdvertisementMalformed:
            return "Feature advertisement malformed"
        case .authenticatedTransportMissing:
            return "Authenticated transport registry unavailable"
        case .fallbackOnly:
            return "Only fallback discovery is available"
        case .authenticatedTransportUnsupported:
            return "Authenticated transport registry unsupported"
        case .authenticatedTransportMalformed:
            return "Authenticated transport registry malformed"
        case .sdkSourceRevisionMismatch:
            return "SDK source revision mismatch"
        case .sdkCapabilitySnapshotDigestMismatch:
            return "SDK capability snapshot digest mismatch"
        case .missingSDKCapability:
            return "Required SDK capability unavailable"
        }
    }

    public var description: String {
        switch self {
        case .missingServerEvidence:
            return "Authoritative server evidence is missing."
        case .missingSDKEvidence:
            return "Authoritative SDK evidence is missing."
        case .mixedProfile:
            return "Server and SDK evidence use different profiles."
        case .mixedProfileDigest:
            return "Server and SDK evidence use different profile digests."
        case .mixedGeneration:
            return "Server and SDK evidence use different generations."
        case .mixedOrigin:
            return "Server and SDK evidence use different origins."
        case .profileMismatch:
            return "Evidence does not use the selected profile."
        case .profileDigestMismatch:
            return "Evidence does not match the selected profile digest."
        case .originMismatch:
            return "Evidence does not match the selected origin."
        case .staleEvidence:
            return "MatrixRTC evidence is stale."
        case .generationMismatch:
            return "MatrixRTC evidence is from an unexpected generation."
        case .snapshotMissing:
            return "The authoritative profile snapshot is missing."
        case .snapshotDigestMismatch:
            return "The authoritative profile snapshot digest does not match."
        case .snapshotMalformed:
            return "The authoritative profile snapshot is malformed."
        case .serverAdvertisementMissing:
            return "The selected feature advertisement is missing."
        case .serverAdvertisementDisabled:
            return "The selected feature advertisement is disabled."
        case .serverAdvertisementMalformed:
            return "The selected feature advertisement is malformed."
        case .authenticatedTransportMissing:
            return "Authenticated transport registry evidence is missing."
        case .fallbackOnly:
            return "Fallback discovery is not authoritative."
        case .authenticatedTransportUnsupported:
            return "The authenticated transport registry is unsupported."
        case .authenticatedTransportMalformed:
            return "The authenticated transport registry evidence is malformed."
        case .sdkSourceRevisionMismatch:
            return "The SDK artifact does not match the selected source revision."
        case .sdkCapabilitySnapshotDigestMismatch:
            return "The SDK capability snapshot does not match the selected digest."
        case .missingSDKCapability:
            return "A required SDK capability is missing."
        }
    }

    public var recovery: String {
        switch self {
        case .missingSDKCapability, .sdkSourceRevisionMismatch,
             .sdkCapabilitySnapshotDigestMismatch:
            return "Update the SDK and repeat the authoritative capability check."
        case .fallbackOnly:
            return "Repeat the authoritative capability check without fallback discovery."
        case .staleEvidence, .generationMismatch, .mixedGeneration:
            return "Request fresh authoritative evidence for the selected generation."
        case .missingServerEvidence, .missingSDKEvidence,
             .mixedProfile, .mixedProfileDigest, .mixedOrigin,
             .profileMismatch, .profileDigestMismatch, .originMismatch,
             .snapshotMissing, .snapshotDigestMismatch, .snapshotMalformed,
             .serverAdvertisementMissing, .serverAdvertisementDisabled,
             .serverAdvertisementMalformed, .authenticatedTransportMissing,
             .authenticatedTransportUnsupported, .authenticatedTransportMalformed:
            return "Repeat the authoritative capability check."
        }
    }
}

public enum MatrixRTCQualificationResult: Equatable, Sendable {
    case available
    case unavailable(MatrixRTCQualificationReason)
}

public enum MatrixRTCQualificationEvaluator {
    static let requiredSDKCapabilities: [MatrixRTCSDKCapability] = [
        .authenticatedTransportRegistryWithoutFallback,
        .stickyEventEphemeralMap,
        .slotMemberLifecycle,
        .delayedLeaveLifecycle,
        .profileAwareParticipantDeviceSnapshot,
        .notificationAndDecline,
        .perMemberSenderKeyLifecycle,
        .recipientDeviceValidation,
        .boundedTransportGrant,
        .registeredTransportTypeValidation,
        .completeNativeSessionSurface,
    ]

    private static let selectedProfileID = "ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2"
    private static let selectedProfileDigestSHA256 = "630c781b782eb94965fb83767a39247f2d127ac31f0c89065f18711b375f8f6d"

    public static func evaluate(
        selection: MatrixRTCQualificationSelection,
        evidence: MatrixRTCQualificationEvidence
    ) -> MatrixRTCQualificationResult {
        guard let server = evidence.server else {
            return .unavailable(.missingServerEvidence)
        }
        guard let sdk = evidence.sdk else {
            return .unavailable(.missingSDKEvidence)
        }

        if server.binding.profileID != sdk.binding.profileID {
            return .unavailable(.mixedProfile)
        }
        if server.binding.profileDigestSHA256 != sdk.binding.profileDigestSHA256 {
            return .unavailable(.mixedProfileDigest)
        }
        if server.binding.generation != sdk.binding.generation {
            return .unavailable(.mixedGeneration)
        }
        if server.binding.origin != sdk.binding.origin {
            return .unavailable(.mixedOrigin)
        }
        if server.binding.profileID != selectedProfileID {
            return .unavailable(.profileMismatch)
        }
        if server.binding.profileDigestSHA256 != selectedProfileDigestSHA256 {
            return .unavailable(.profileDigestMismatch)
        }
        if server.binding.origin != selection.origin {
            return .unavailable(.originMismatch)
        }
        if server.binding.generation < selection.generation {
            return .unavailable(.staleEvidence)
        }
        if server.binding.generation > selection.generation {
            return .unavailable(.generationMismatch)
        }
        if sdk.artifactIdentity.sourceRevision != selection.expectedSDKArtifactIdentity.sourceRevision {
            return .unavailable(.sdkSourceRevisionMismatch)
        }
        if sdk.artifactIdentity.capabilitySnapshotDigestSHA256 != selection.expectedSDKArtifactIdentity.capabilitySnapshotDigestSHA256 {
            return .unavailable(.sdkCapabilitySnapshotDigestMismatch)
        }

        switch server.snapshotIntegrity {
        case .missing:
            return .unavailable(.snapshotMissing)
        case .digestMismatch:
            return .unavailable(.snapshotDigestMismatch)
        case .malformed:
            return .unavailable(.snapshotMalformed)
        case .matched:
            break
        }

        switch server.serverAdvertisement {
        case .missing:
            return .unavailable(.serverAdvertisementMissing)
        case .disabled:
            return .unavailable(.serverAdvertisementDisabled)
        case .malformed:
            return .unavailable(.serverAdvertisementMalformed)
        case .supported:
            break
        }

        switch server.transportEvidence {
        case .missing:
            return .unavailable(.authenticatedTransportMissing)
        case .fallbackOnly:
            return .unavailable(.fallbackOnly)
        case .authenticatedUnsupported:
            return .unavailable(.authenticatedTransportUnsupported)
        case .authenticatedMalformed:
            return .unavailable(.authenticatedTransportMalformed)
        case .authenticatedSupported:
            break
        }

        for capability in requiredSDKCapabilities where !sdk.capabilities.contains(capability) {
            return .unavailable(.missingSDKCapability(capability))
        }
        return .available
    }
}
