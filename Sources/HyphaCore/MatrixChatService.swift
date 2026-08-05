import Foundation

public enum MatrixSessionStartupDecision: Equatable, Sendable {
    case signedOut
    case restoreActive
    case chooseAccount
}

public enum MatrixSessionStartupPolicy {
    public static func decision(
        savedSessionCount: Int,
        hasActiveSession: Bool
    ) -> MatrixSessionStartupDecision {
        if savedSessionCount > 1 { return .chooseAccount }
        if savedSessionCount == 1, hasActiveSession { return .restoreActive }
        return .signedOut
    }
}

public struct MatrixRoomSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let isEncrypted: Bool
    public let hasInvite: Bool
    public let isCreatedByCurrentUser: Bool
    public let isSpace: Bool
    public let isDirect: Bool
    public let topic: String?
    public let canInviteMembers: Bool

    public init(
        id: String,
        name: String,
        isEncrypted: Bool,
        hasInvite: Bool,
        isCreatedByCurrentUser: Bool = false,
        isSpace: Bool = false,
        isDirect: Bool = false,
        topic: String? = nil,
        canInviteMembers: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isEncrypted = isEncrypted
        self.hasInvite = hasInvite
        self.isCreatedByCurrentUser = isCreatedByCurrentUser
        self.isSpace = isSpace
        self.isDirect = isDirect
        self.topic = topic
        self.canInviteMembers = canInviteMembers
    }
}

public struct MatrixSidebarRoomGroups: Equatable, Sendable {
    public let directMessages: [MatrixRoomSummary]
    public let invitations: [MatrixRoomSummary]
    public let spaces: [MatrixRoomSummary]
    public let rooms: [MatrixRoomSummary]

    public init(rooms: [MatrixRoomSummary]) {
        invitations = rooms.filter(\.hasInvite)
        let joined = rooms.filter { !$0.hasInvite }
        directMessages = joined.filter { $0.isDirect && !$0.isSpace }
        spaces = joined.filter(\.isSpace)
        self.rooms = joined.filter { !$0.isSpace && !$0.isDirect }
    }
}

public enum MatrixUserLookupResult: Equatable, Sendable {
    case exists(userID: String, displayName: String?)
    case notFound(userID: String, inviteLink: String)
    case unavailable
}

public struct MatrixTimelineEvent: Identifiable, Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        case undecryptable(reason: String)
        case unsupported(type: String)
    }

    public let id: String
    public let senderDisplayName: String
    public let senderID: String
    public let content: Content
    public let isOwn: Bool
    public let authenticity: MatrixEventAuthenticity
    public let timestamp: UInt64

    public init(
        id: String,
        senderDisplayName: String,
        senderID: String? = nil,
        content: Content,
        isOwn: Bool = false,
        authenticity: MatrixEventAuthenticity = .noWarning,
        timestamp: UInt64 = 0
    ) {
        self.id = id
        self.senderDisplayName = senderDisplayName
        self.senderID = senderID ?? senderDisplayName
        self.content = content
        self.isOwn = isOwn
        self.authenticity = authenticity
        self.timestamp = timestamp
    }
}

public enum MatrixEventAuthenticity: Equatable, Hashable, Sendable {
    case noWarning
    case authenticityNotGuaranteed
    case unknownDevice
    case unsignedDevice
    case unverifiedIdentity
    case verificationViolation
    case mismatchedSender
    case sentInClear
}

public struct MatrixVerificationEmoji: Identifiable, Equatable, Sendable {
    public let symbol: String
    public let description: String
    public var id: String { "\(symbol)|\(description)" }

    public init(symbol: String, description: String) {
        self.symbol = symbol
        self.description = description
    }
}

public enum MatrixVerificationChallenge: Equatable, Sendable {
    case emojis([MatrixVerificationEmoji])
    case decimals([UInt16])
}

public enum MatrixRecoveryState: Equatable, Sendable {
    case unknown
    case unavailable
    case available
    case incomplete
    case restoring
    case ready
    case failed(reason: String)
    case diagnostic(MatrixCrossSigningDiagnosticReceipt)
}

public enum MatrixDiagnosticUploadTransport: Equatable, Sendable { case accepted, failed }
public enum MatrixDiagnosticUploadProcessing: Equatable, Sendable {
    case accepted, keyMismatch, invalidSignature, otherFailure
}
public enum MatrixDiagnosticBackupRepair: Equatable, Sendable {
    case notAttempted, completed, failed
}

public struct MatrixCrossSigningDiagnosticReceipt: Equatable, Sendable {
    public let publicIdentityRefreshed: Bool
    public let privateSelfSigningKeyPresent: Bool
    public let privateSelfSigningKeyMatchesCurrentPublicIdentity: Bool
    public let localOwnDeviceKeyMatchesServerDeviceKey: Bool
    public let signedObjectMatchesFreshServerDeviceObject: Bool
    public let generatedSignatureValidLocally: Bool
    public let uploadTransport: MatrixDiagnosticUploadTransport
    public let uploadProcessing: MatrixDiagnosticUploadProcessing
    public let postUploadServerSignaturePresent: Bool
    public let backupRepair: MatrixDiagnosticBackupRepair

    public var stableCode: String {
        if uploadTransport == .failed { return "SIG-T0" }
        if !privateSelfSigningKeyMatchesCurrentPublicIdentity { return "SIG-I1" }
        if !localOwnDeviceKeyMatchesServerDeviceKey { return "SIG-D2" }
        if uploadProcessing == .keyMismatch { return "SIG-O3" }
        if !signedObjectMatchesFreshServerDeviceObject { return "SIG-O3" }
        if !generatedSignatureValidLocally { return "SIG-S4" }
        if uploadProcessing == .invalidSignature { return "SIG-H5" }
        if !postUploadServerSignaturePresent { return "SIG-P6" }
        if backupRepair == .failed { return "SIG-B7" }
        return "SIG-OK"
    }
}

public enum MatrixPasswordLoginPolicy {
    public static func normalizeUsername(
        _ rawValue: String,
        activeServerName: String
    ) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverName = activeServerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !serverName.isEmpty else { return nil }

        let withoutSigil = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
        let components = withoutSigil.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let localpart = components.first.map(String.init), isValidLocalpart(localpart) else { return nil }
        if components.count == 2 {
            guard components[1].lowercased() == serverName else { return nil }
        }
        return "@\(localpart.lowercased()):\(serverName)"
    }

    private static func isValidLocalpart(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._=-")
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public enum MatrixInitialPasswordResetPolicy {
    public enum AuthenticationMethod: Equatable, Sendable {
        case manualPassword
        case inviteTokenRegistration
        case savedCredential
    }

    public static func requiresReset(
        authenticationMethod: AuthenticationMethod,
        hadExistingSession: Bool
    ) -> Bool {
        authenticationMethod == .manualPassword && !hadExistingSession
    }
}

public enum MatrixRoomKind: String, CaseIterable, Equatable, Sendable {
    case room
    case space
}

public enum MatrixRoomVisibility: String, CaseIterable, Equatable, Sendable {
    case inviteOnly
    case `public`
}

public struct MatrixRoomCreationRequest: Equatable, Sendable {
    public let name: String
    public let topic: String?
    public let invitees: [String]
    public let kind: MatrixRoomKind
    public let visibility: MatrixRoomVisibility

    public init(
        name: String,
        topic: String? = nil,
        invitees: [String] = [],
        kind: MatrixRoomKind = .room,
        visibility: MatrixRoomVisibility = .inviteOnly
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTopic = topic?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.topic = trimmedTopic?.isEmpty == true ? nil : trimmedTopic
        var seen = Set<String>()
        self.invitees = invitees.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        self.kind = kind
        self.visibility = visibility
    }
}

public struct MatrixRoomInviteRequest: Equatable, Sendable {
    public let roomID: String
    public let userIDs: [String]

    public init(roomID: String, userIDs: [String]) {
        self.roomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        self.userIDs = userIDs.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

public enum MatrixRoomInvitationPolicy {
    public static func eligibleRooms(from rooms: [MatrixRoomSummary]) -> [MatrixRoomSummary] {
        rooms
            .filter { !$0.hasInvite && !$0.isSpace && $0.canInviteMembers }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func resolveUserIDs(
        _ values: [String],
        defaultServerName: String?
    ) -> [String]? {
        let serverName = defaultServerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var resolved: [String] = []
        for value in values {
            let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            guard candidate.count <= 1_024 else { return nil }
            let userID: String
            if candidate.hasPrefix("@") {
                let body = candidate.dropFirst()
                if let separator = body.firstIndex(of: ":") {
                    let localpart = body[..<separator]
                    let server = body[body.index(after: separator)...]
                    guard !localpart.isEmpty,
                          !server.isEmpty,
                          !candidate.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
                        return nil
                    }
                    userID = candidate
                } else {
                    let localpart = String(body)
                    guard validLocalpart(localpart),
                          let serverName,
                          !serverName.isEmpty,
                          !serverName.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
                        return nil
                    }
                    userID = "@\(localpart):\(serverName)"
                }
            } else {
                guard validLocalpart(candidate),
                      let serverName,
                      !serverName.isEmpty,
                      !serverName.unicodeScalars.contains(where: CharacterSet.whitespacesAndNewlines.contains) else {
                    return nil
                }
                userID = "@\(candidate):\(serverName)"
            }
            if seen.insert(userID).inserted {
                guard resolved.count < 10 else { return nil }
                resolved.append(userID)
            }
        }
        return resolved.isEmpty ? nil : resolved
    }

    public static func localAccountLookupResult(
        userID: String,
        roomID: String,
        users: [MatrixAdminUserSummary]
    ) -> MatrixUserLookupResult {
        if users.contains(where: { $0.userID == userID && !$0.isDeactivated && !$0.isGuest }) {
            return .exists(userID: userID, displayName: nil)
        }
        return .notFound(
            userID: userID,
            inviteLink: "https://matrix.to/#/\(roomID)"
        )
    }

    private static func validLocalpart(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._=-/")
        return !value.isEmpty
            && value.count <= 255
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

public enum MatrixDeviceTrustState: Equatable, Sendable {
    case unknown
    case unsigned
    case invalidSignature
    case verifiedByCurrentSelfSigningKey
    case unavailable
}

public enum MatrixPeerVerificationEligibility: Equatable, Sendable {
    case eligiblePeer
    case noEligiblePeer
    case unavailable
}

public enum MatrixFirstDeviceTrustBootstrapState: Equatable, Hashable, Sendable {
    case notBootstrapped
    case bootstrapping
    case passwordRequired
    case verifiedByCurrentSelfSigningKey
    case invalidSignature
    case unavailable
    case failed(reason: String)
}

public enum MatrixVerificationFlowState: Equatable, Sendable {
    case idle
    case requesting
    case challenge(MatrixVerificationChallenge)
    case approving
    case failed(reason: String)
}

public struct MatrixSecurityGuidance: Equatable, Sendable {
    public let trustState: MatrixDeviceTrustState
    public let verificationFlowState: MatrixVerificationFlowState
    public let recoveryState: MatrixRecoveryState
    public let peerVerificationEligibility: MatrixPeerVerificationEligibility

    public init(
        trustState: MatrixDeviceTrustState,
        verificationFlowState: MatrixVerificationFlowState,
        recoveryState: MatrixRecoveryState,
        peerVerificationEligibility: MatrixPeerVerificationEligibility = .unavailable
    ) {
        self.trustState = trustState
        self.verificationFlowState = verificationFlowState
        self.recoveryState = recoveryState
        self.peerVerificationEligibility = peerVerificationEligibility
    }
}

public enum MatrixChatAuthority: Equatable, Sendable {
    case available
    case blockedByProvenIdentityViolation
}


public enum MatrixRecoveryFailureStage: Equatable, Sendable {
    case identityRefresh
    case secretStorageUnlock
    case selfSigningKeyImport
    case deviceSignatureUpload
    case serverConfirmation
    case backupRepair
}

public enum MatrixChatServiceError: Error, Equatable, Sendable {
    case invalidCredentials
    case sessionExpired
    case offline
    case trustViolation
    case recoveryRequired
    case recoveryFailed(stage: MatrixRecoveryFailureStage)
    case recoveryDiagnostic(receipt: MatrixCrossSigningDiagnosticReceipt)
    case noSavedSession
    case unavailable(reason: String)
}

public enum MatrixPasswordChangeResult: Equatable, Sendable {
    case success
    case invalidCurrentPassword
    case failed(message: String)
}

public protocol MatrixChatService: Sendable {
    func restore() async throws -> [MatrixRoomSummary]
    func signIn(username: String, password: String) async throws -> [MatrixRoomSummary]
    func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws
    func requestHomeserverPasswordReset() async throws -> MatrixPasswordResetRequest
    func hasPendingHomeserverPasswordResetRequest() async throws -> Bool
    func completeHomeserverPasswordResetRequest() async throws
    func isHomeserverAdministrator() async throws -> Bool
    func administratorSnapshot() async throws -> MatrixAdminSnapshot
    func administratorPasswordResetRequests(users: [MatrixAdminUserSummary]) async throws -> [MatrixPasswordResetRequest]
    func resetAdministratorManagedPassword(for request: MatrixPasswordResetRequest, temporaryPassword: String) async throws
    func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary
    func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary
    func logoutAdministratorManagedAccount(userID: String) async throws
    func deactivateAdministratorManagedAccount(userID: String) async throws
    func purgeAdministratorManagedRoom(roomID: String) async throws
    func refreshRooms() async throws -> [MatrixRoomSummary]
    func timeline(for roomID: String) async throws -> [MatrixTimelineEvent]
    func sendText(_ body: String, to roomID: String) async throws
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws
    func acceptInvitation(roomID: String) async throws
    func declineInvitation(roomID: String) async throws
    func removeRoom(roomID: String) async throws -> [MatrixRoomSummary]
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState
    func setupEncryptionRecovery() async throws -> String
    func restoreEncryption(recoveryKey: String) async throws
    func deviceTrustState() async throws -> MatrixDeviceTrustState
    func peerVerificationEligibility() async -> MatrixPeerVerificationEligibility
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge
    func approveDeviceVerification() async throws
    func declineDeviceVerification() async
    func suspend() async
    func logout() async throws
}

public extension MatrixChatService {
    func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary {
        throw MatrixAdminClientError.serverRejected
    }

    func logoutAdministratorManagedAccount(userID: String) async throws {
        throw MatrixAdminClientError.serverRejected
    }

    func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Password change is unavailable")
    }

    func requestHomeserverPasswordReset() async throws -> MatrixPasswordResetRequest {
        throw MatrixChatServiceError.unavailable(reason: "Homeserver password reset requests are unavailable")
    }

    func hasPendingHomeserverPasswordResetRequest() async throws -> Bool { false }

    func completeHomeserverPasswordResetRequest() async throws {}

    func administratorPasswordResetRequests(users: [MatrixAdminUserSummary]) async throws -> [MatrixPasswordResetRequest] {
        throw MatrixAdminClientError.serverRejected
    }

    func resetAdministratorManagedPassword(for request: MatrixPasswordResetRequest, temporaryPassword: String) async throws {
        throw MatrixAdminClientError.serverRejected
    }

    func isHomeserverAdministrator() async throws -> Bool { false }

    func administratorSnapshot() async throws -> MatrixAdminSnapshot {
        throw MatrixChatServiceError.unavailable(reason: "Homeserver administration is unavailable")
    }

    func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        throw MatrixChatServiceError.unavailable(reason: "Account administration is unavailable")
    }

    func deactivateAdministratorManagedAccount(userID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Account administration is unavailable")
    }

    func purgeAdministratorManagedRoom(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room administration is unavailable")
    }

    func refreshRooms() async throws -> [MatrixRoomSummary] {
        throw MatrixChatServiceError.unavailable(reason: "Room sync is unavailable")
    }
    func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async throws -> MatrixRoomSummary {
        throw MatrixChatServiceError.unavailable(reason: "Room creation is unavailable")
    }
    func lookupInviteUser(userID: String, roomID: String) async throws -> MatrixUserLookupResult {
        .unavailable
    }
    func inviteUsers(_ request: MatrixRoomInviteRequest) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Room invitations are unavailable")
    }
    func acceptInvitation(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Invitation acceptance is unavailable")
    }
    func declineInvitation(roomID: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Invitation decline is unavailable")
    }
    func removeRoom(roomID: String) async throws -> [MatrixRoomSummary] {
        throw MatrixChatServiceError.unavailable(reason: "Room removal is unavailable")
    }
    func encryptionRecoveryState(trustState: MatrixDeviceTrustState) async throws -> MatrixRecoveryState { .unknown }
    func setupEncryptionRecovery() async throws -> String {
        throw MatrixChatServiceError.unavailable(reason: "Encryption recovery setup is unavailable")
    }
    func restoreEncryption(recoveryKey: String) async throws {
        throw MatrixChatServiceError.unavailable(reason: "Encryption recovery is unavailable")
    }
    func deviceTrustState() async throws -> MatrixDeviceTrustState { .unknown }
    func peerVerificationEligibility() async -> MatrixPeerVerificationEligibility { .unavailable }
    func bootstrapFirstDeviceTrust() async throws -> MatrixFirstDeviceTrustBootstrapState {
        throw MatrixChatServiceError.unavailable(reason: "First-device security setup is unavailable")
    }
    func continueFirstDeviceTrust(password: String) async throws -> MatrixFirstDeviceTrustBootstrapState {
        throw MatrixChatServiceError.unavailable(reason: "First-device security setup is unavailable")
    }
    func requestDeviceVerification() async throws -> MatrixVerificationChallenge {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func approveDeviceVerification() async throws {
        throw MatrixChatServiceError.unavailable(reason: "Device verification is unavailable")
    }
    func declineDeviceVerification() async {}
    func suspend() async {}
}

public enum MatrixSignOutMessage: Equatable, Sendable {
    case invalidCredentials
    case savedCredentialUnavailable
    case signedOut
}

public enum MatrixComposerState: Equatable, Sendable {
    case ready
    case sending
    case disabled(reason: String)
}

public enum MatrixChatState: Equatable, Sendable {
    case signedOut(message: MatrixSignOutMessage?)
    case restoring
    case rooms([MatrixRoomSummary])
    case thread(room: MatrixRoomSummary, events: [MatrixTimelineEvent], composer: MatrixComposerState)
    case sessionExpired
    case offline(canRetry: Bool)
    case trustBlocked(room: MatrixRoomSummary)
    case recoveryRequired
    case unavailable(reason: String)
}

@MainActor
public final class MatrixChatCoordinator {
    public private(set) var state: MatrixChatState = .signedOut(message: nil)
    public private(set) var trustState: MatrixDeviceTrustState = .unknown
    public private(set) var verificationFlowState: MatrixVerificationFlowState = .idle
    public private(set) var recoveryState: MatrixRecoveryState = .unknown
    public private(set) var firstDeviceTrustBootstrapState: MatrixFirstDeviceTrustBootstrapState = .notBootstrapped
    public private(set) var peerVerificationEligibility: MatrixPeerVerificationEligibility = .unavailable

    public var securityGuidance: MatrixSecurityGuidance {
        MatrixSecurityGuidance(
            trustState: trustState,
            verificationFlowState: verificationFlowState,
            recoveryState: recoveryState,
            peerVerificationEligibility: peerVerificationEligibility
        )
    }

    public var chatAuthority: MatrixChatAuthority {
        trustState == .invalidSignature ? .blockedByProvenIdentityViolation : .available
    }

    private let service: any MatrixChatService
    private var roomOperationGeneration: UInt64 = 0
    private var timelineOperationGeneration: UInt64 = 0

    public init(service: any MatrixChatService) {
        self.service = service
    }

    public func restore() async {
        state = .restoring
        do {
            state = .rooms(try await service.restore())
            await refreshTrustState()
            await refreshRecoveryState()
        } catch {
            state = map(error, room: nil)
        }
    }

    public func signIn(username: String, password: String) async {
        state = .restoring
        do {
            state = .rooms(try await service.signIn(username: username, password: password))
            await refreshTrustState()
            await refreshRecoveryState()
        } catch {
            state = map(error, room: nil)
        }
    }

    public func restoreAndRefreshForAccountSwitch() async -> [MatrixRoomSummary]? {
        state = .restoring
        do {
            _ = try await service.restore()
            let rooms = try await service.refreshRooms()
            state = .rooms(rooms)
            await refreshTrustState()
            await refreshRecoveryState()
            return rooms
        } catch {
            state = map(error, room: nil)
            return nil
        }
    }

    public func signInAndRefreshForAccountSwitch(
        username: String,
        password: String
    ) async -> [MatrixRoomSummary]? {
        state = .restoring
        do {
            _ = try await service.signIn(username: username, password: password)
            let rooms = try await service.refreshRooms()
            state = .rooms(rooms)
            await refreshTrustState()
            await refreshRecoveryState()
            return rooms
        } catch {
            state = map(error, room: nil)
            return nil
        }
    }

    public func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool
    ) async -> MatrixPasswordChangeResult {
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            return .failed(message: "Current and new passwords are required.")
        }
        do {
            try await service.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                logoutOtherDevices: logoutOtherDevices
            )
            return .success
        } catch MatrixChatServiceError.invalidCredentials {
            return .invalidCurrentPassword
        } catch MatrixChatServiceError.sessionExpired {
            return .failed(message: "Your session expired. Sign in again before changing the password.")
        } catch MatrixChatServiceError.offline {
            return .failed(message: "Hypha is offline. Reconnect and try again.")
        } catch {
            return .failed(message: "The password could not be changed. Try again.")
        }
    }

    public func requestHomeserverPasswordReset() async -> Bool {
        do {
            _ = try await service.requestHomeserverPasswordReset()
            return true
        } catch {
            return false
        }
    }

    public func hasPendingHomeserverPasswordResetRequest() async throws -> Bool {
        try await service.hasPendingHomeserverPasswordResetRequest()
    }

    public func completeHomeserverPasswordResetRequest() async -> Bool {
        do {
            try await service.completeHomeserverPasswordResetRequest()
            return true
        } catch {
            return false
        }
    }

    public func isHomeserverAdministrator() async -> Bool {
        do {
            return try await service.isHomeserverAdministrator()
        } catch {
            return false
        }
    }

    public func administratorSnapshot() async throws -> MatrixAdminSnapshot {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        return try await service.administratorSnapshot()
    }

    public func administratorPasswordResetRequests(
        users: [MatrixAdminUserSummary]
    ) async throws -> [MatrixPasswordResetRequest] {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        return try await service.administratorPasswordResetRequests(users: users)
    }

    public func resetAdministratorManagedPassword(
        for request: MatrixPasswordResetRequest,
        temporaryPassword: String
    ) async throws {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        try await service.resetAdministratorManagedPassword(
            for: request,
            temporaryPassword: temporaryPassword
        )
    }

    public func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async throws -> MatrixAdminUserSummary {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        return try await service.createAdministratorManagedAccount(
            localpart: localpart,
            temporaryPassword: temporaryPassword,
            administrator: administrator
        )
    }

    public func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async throws -> MatrixAdminRoomSummary {
        guard try await service.isHomeserverAdministrator() else { throw MatrixAdminClientError.notAdministrator }
        return try await service.createAdministratorManagedRoom(name: name, topic: topic, asSpace: asSpace, visibility: visibility)
    }

    public func logoutAdministratorManagedAccount(userID: String) async throws {
        guard try await service.isHomeserverAdministrator() else { throw MatrixAdminClientError.notAdministrator }
        try await service.logoutAdministratorManagedAccount(userID: userID)
    }

    public func deactivateAdministratorManagedAccount(userID: String) async throws {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        try await service.deactivateAdministratorManagedAccount(userID: userID)
    }

    public func purgeAdministratorManagedRoom(roomID: String) async throws {
        guard try await service.isHomeserverAdministrator() else {
            throw MatrixAdminClientError.notAdministrator
        }
        try await service.purgeAdministratorManagedRoom(roomID: roomID)
    }

    public func refreshRooms() async throws -> [MatrixRoomSummary] {
        let rooms = try await service.refreshRooms()
        if case .rooms = state {
            state = .rooms(rooms)
        }
        return rooms
    }

    public func lookupInviteUser(
        _ userID: String,
        for room: MatrixRoomSummary
    ) async -> MatrixUserLookupResult {
        guard room.canInviteMembers, !room.hasInvite, !room.isSpace else { return .unavailable }
        do {
            return try await service.lookupInviteUser(userID: userID, roomID: room.id)
        } catch {
            return .unavailable
        }
    }

    public func inviteUsers(_ userIDs: [String], to room: MatrixRoomSummary) async -> Bool {
        let request = MatrixRoomInviteRequest(roomID: room.id, userIDs: userIDs)
        guard room.canInviteMembers,
              !room.hasInvite,
              !room.isSpace,
              !request.roomID.isEmpty,
              !request.userIDs.isEmpty,
              chatAuthority == .available else { return false }
        do {
            try await service.inviteUsers(request)
            return true
        } catch {
            return false
        }
    }

    public func acceptInvitation(to room: MatrixRoomSummary) async -> [MatrixRoomSummary]? {
        guard room.hasInvite, chatAuthority == .available else { return nil }
        do {
            try await service.acceptInvitation(roomID: room.id)
            let rooms = try await service.refreshRooms()
            if case .rooms = state {
                state = .rooms(rooms)
            }
            return rooms
        } catch {
            return nil
        }
    }

    public func declineInvitation(to room: MatrixRoomSummary) async -> [MatrixRoomSummary]? {
        guard room.hasInvite, chatAuthority == .available else { return nil }
        do {
            try await service.declineInvitation(roomID: room.id)
            let rooms = try await service.refreshRooms()
            if case .rooms = state {
                state = .rooms(rooms)
            }
            return rooms
        } catch {
            return nil
        }
    }

    public func open(room: MatrixRoomSummary) async {
        roomOperationGeneration &+= 1
        timelineOperationGeneration &+= 1
        let operationGeneration = roomOperationGeneration
        do {
            let events = try await service.timeline(for: room.id)
            guard operationGeneration == roomOperationGeneration else { return }
            state = .thread(room: room, events: events, composer: room.isEncrypted ? .ready : .disabled(reason: "Encrypted rooms only"))
        } catch {
            guard operationGeneration == roomOperationGeneration else { return }
            state = map(error, room: room)
        }
    }

    public func refreshOpenRoom() async {
        guard case let .thread(room, _, _) = state else { return }
        let operationGeneration = roomOperationGeneration
        timelineOperationGeneration &+= 1
        let timelineGeneration = timelineOperationGeneration
        do {
            let events = try await service.timeline(for: room.id)
            guard operationGeneration == roomOperationGeneration,
                  timelineGeneration == timelineOperationGeneration,
                  case let .thread(currentRoom, _, currentComposer) = state,
                  currentRoom.id == room.id else { return }
            state = .thread(room: room, events: events, composer: currentComposer)
        } catch {
            guard operationGeneration == roomOperationGeneration,
                  timelineGeneration == timelineOperationGeneration,
                  case let .thread(currentRoom, _, _) = state,
                  currentRoom.id == room.id else { return }
            let failureState = map(error, room: room)
            switch failureState {
            case .offline, .unavailable:
                return
            default:
                state = failureState
            }
        }
    }

    @discardableResult
    public func send(_ body: String) async -> Bool {
        guard case let .thread(room, events, composer) = state,
              composer == .ready,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard chatAuthority == .available else {
            state = .trustBlocked(room: room)
            return false
        }

        let operationGeneration = roomOperationGeneration
        timelineOperationGeneration &+= 1
        state = .thread(room: room, events: events, composer: .sending)
        do {
            try await service.sendText(body, to: room.id)
        } catch {
            if operationGeneration == roomOperationGeneration {
                timelineOperationGeneration &+= 1
                applySendFailure(error, room: room, events: events)
            }
            return false
        }

        guard operationGeneration == roomOperationGeneration else { return true }
        state = .thread(room: room, events: events, composer: .ready)
        timelineOperationGeneration &+= 1
        let timelineGeneration = timelineOperationGeneration

        do {
            let refreshedEvents = try await service.timeline(for: room.id)
            guard operationGeneration == roomOperationGeneration,
                  timelineGeneration == timelineOperationGeneration,
                  case let .thread(currentRoom, _, _) = state,
                  currentRoom.id == room.id else { return true }
            state = .thread(room: room, events: refreshedEvents, composer: .ready)
        } catch {
            if operationGeneration == roomOperationGeneration,
               timelineGeneration == timelineOperationGeneration {
                applySendFailure(error, room: room, events: events)
            }
        }
        return true
    }

    private func applySendFailure(
        _ error: Error,
        room: MatrixRoomSummary,
        events: [MatrixTimelineEvent]
    ) {
        let failureState = map(error, room: room)
        switch failureState {
        case .offline, .unavailable:
            state = .thread(room: room, events: events, composer: .ready)
        default:
            state = failureState
        }
    }

    public func createEncryptedRoom(_ request: MatrixRoomCreationRequest) async {
        guard !request.name.isEmpty else {
            state = .unavailable(reason: "Room name is required")
            return
        }
        guard chatAuthority == .available else {
            state = .unavailable(reason: "Device trust requires review")
            return
        }
        do {
            let room = try await service.createEncryptedRoom(request)
            guard room.isSpace || room.isEncrypted else {
                state = .trustBlocked(room: room)
                return
            }
            await open(room: room)
        } catch {
            state = map(error, room: nil)
        }
    }

    @discardableResult
    public func removeRoom(_ room: MatrixRoomSummary) async -> Bool {
        guard room.isCreatedByCurrentUser else { return false }
        do {
            let remainingRooms = try await service.removeRoom(roomID: room.id)
            roomOperationGeneration &+= 1
            timelineOperationGeneration &+= 1
            state = .rooms(remainingRooms)
            return true
        } catch {
            return false
        }
    }

    public func restoreEncryption(recoveryKey: String) async {
        let normalizedRecoveryKey = recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRecoveryKey.isEmpty else {
            recoveryState = .failed(reason: "Recovery key is required")
            return
        }
        recoveryState = .restoring
        do {
            try await service.restoreEncryption(recoveryKey: normalizedRecoveryKey)
            await refreshTrustState()
            await refreshRecoveryState()
        } catch let MatrixChatServiceError.recoveryFailed(stage) {
            recoveryState = .failed(reason: Self.recoveryFailureMessage(for: stage))
        } catch let MatrixChatServiceError.recoveryDiagnostic(receipt) {
            recoveryState = .diagnostic(receipt)
        } catch {
            recoveryState = .failed(reason: "Encryption recovery failed")
        }
    }

    static func recoveryFailureMessage(for stage: MatrixRecoveryFailureStage) -> String {
        switch stage {
        case .identityRefresh:
            "Current cross-signing identity could not be refreshed"
        case .secretStorageUnlock:
            "Secret Storage recovery did not complete"
        case .selfSigningKeyImport:
            "Secret Storage opened, but the self-signing key is unavailable"
        case .deviceSignatureUpload:
            "Self-signing key imported, but device signature upload failed"
        case .serverConfirmation:
            "Device signature was not confirmed by the homeserver"
        case .backupRepair:
            "Device verified, but room-key backup repair did not complete"
        }
    }

    public func setupEncryptionRecovery() async -> String? {
        recoveryState = .restoring
        do {
            let recoveryKey = try await service.setupEncryptionRecovery()
            await refreshTrustState()
            await refreshRecoveryState()
            return recoveryKey
        } catch {
            recoveryState = .failed(reason: "Encryption recovery setup failed")
            return nil
        }
    }

    public func refreshRecoveryState() async {
        do {
            recoveryState = try await service.encryptionRecoveryState(trustState: trustState)
        } catch {
            recoveryState = .failed(reason: "Recovery status unavailable")
        }
    }

    public func bootstrapFirstDeviceTrust() async {
        guard firstDeviceTrustBootstrapState != .bootstrapping else { return }
        firstDeviceTrustBootstrapState = .bootstrapping
        do {
            applyFirstDeviceTrustBootstrapState(try await service.bootstrapFirstDeviceTrust())
        } catch {
            firstDeviceTrustBootstrapState = .failed(
                reason: "Device security setup failed. Try again."
            )
        }
        await refreshRecoveryState()
    }

    public func continueFirstDeviceTrust(password: String) async {
        guard firstDeviceTrustBootstrapState != .bootstrapping else { return }
        guard !password.isEmpty else {
            firstDeviceTrustBootstrapState = .passwordRequired
            return
        }
        firstDeviceTrustBootstrapState = .bootstrapping
        do {
            applyFirstDeviceTrustBootstrapState(
                try await service.continueFirstDeviceTrust(password: password)
            )
        } catch {
            firstDeviceTrustBootstrapState = .passwordRequired
        }
        await refreshRecoveryState()
    }

    private func applyFirstDeviceTrustBootstrapState(_ state: MatrixFirstDeviceTrustBootstrapState) {
        firstDeviceTrustBootstrapState = state
        switch state {
        case .verifiedByCurrentSelfSigningKey:
            trustState = .verifiedByCurrentSelfSigningKey
        case .invalidSignature:
            trustState = .invalidSignature
        case .unavailable:
            trustState = .unavailable
        case .notBootstrapped:
            trustState = .unsigned
        case .bootstrapping, .passwordRequired, .failed:
            break
        }
    }

    public func requestDeviceVerification() async {
        verificationFlowState = .requesting
        do {
            verificationFlowState = .challenge(try await service.requestDeviceVerification())
        } catch {
            verificationFlowState = .failed(reason: "Device verification failed")
        }
    }

    public func approveDeviceVerification() async {
        verificationFlowState = .approving
        do {
            try await service.approveDeviceVerification()
            verificationFlowState = .idle
            await refreshTrustState()
        } catch {
            verificationFlowState = .failed(reason: "Device verification approval failed")
        }
    }

    public func declineDeviceVerification() async {
        await service.declineDeviceVerification()
        verificationFlowState = .idle
    }

    public func refreshTrustState() async {
        do {
            let refreshedTrustState = try await service.deviceTrustState()
            let remainsUnresolved = refreshedTrustState == .unknown || refreshedTrustState == .unavailable
            if trustState != .invalidSignature || !remainsUnresolved {
                trustState = refreshedTrustState
            }
        } catch {
            if trustState != .invalidSignature {
                trustState = .unavailable
            }
        }
        await refreshPeerVerificationEligibility()
        await refreshRecoveryState()
    }

    public func refreshPeerVerificationEligibility() async {
        peerVerificationEligibility = await service.peerVerificationEligibility()
    }

    public func suspend() async {
        await service.suspend()
    }

    public func logout() async {
        do {
            try await service.logout()
            peerVerificationEligibility = .unavailable
            state = .signedOut(message: .signedOut)
        } catch {
            state = map(error, room: nil)
        }
    }

    private func map(_ error: Error, room: MatrixRoomSummary?) -> MatrixChatState {
        guard let serviceError = error as? MatrixChatServiceError else {
            return .unavailable(reason: "Matrix service unavailable")
        }
        switch serviceError {
        case .invalidCredentials:
            return .signedOut(message: .invalidCredentials)
        case .sessionExpired:
            return .sessionExpired
        case .offline:
            return .offline(canRetry: true)
        case .trustViolation:
            if let room { return .trustBlocked(room: room) }
            return .unavailable(reason: "Device trust requires review")
        case .recoveryRequired:
            return .recoveryRequired
        case let .recoveryFailed(stage):
            return .unavailable(reason: Self.recoveryFailureMessage(for: stage))
        case let .recoveryDiagnostic(receipt):
            return .unavailable(reason: receipt.stableCode)
        case .noSavedSession:
            return .signedOut(message: nil)
        case let .unavailable(reason):
            return .unavailable(reason: reason)
        }
    }
}
