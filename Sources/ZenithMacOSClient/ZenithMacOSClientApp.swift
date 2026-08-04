import Accessibility
import AppKit
import SwiftUI
import ZenithMacOSClientCore

@main
struct ZenithMacOSClientApp: App {
    @StateObject private var model: MatrixAppModel

    init() {
        let healthChecker = MatrixHomeserverHealthChecker()
        let sessionVault = MatrixEncryptedSessionVault()
        let credentialStore = HyphaMigratingCredentialStore(
            primary: sessionVault,
            legacy: HyphaMatrixKeychainCredentialStore()
        )
        _model = StateObject(wrappedValue: MatrixAppModel(
            healthChecker: healthChecker,
            sessionVault: sessionVault,
            credentialStore: credentialStore,
            sharedPasswordStore: AppleSharedWebCredentialStore()
        ) { configuration in
            MatrixRustSDKChatService(
                configuration: configuration,
                vault: sessionVault,
                clientFactory: MatrixRustLiveClientFactory(configuration: configuration)
            )
        })
    }

    var body: some Scene {
        WindowGroup("Hypha") {
            MatrixCompanionShell(model: model)
                .frame(minWidth: 760, minHeight: 520)
                .zenithAppSurface()
                .task { await model.restoreSavedHomeserverIfAvailable() }
        }
        .defaultSize(width: 980, height: 680)
    }
}

enum HomeserverOnboardingState: Equatable {
    case awaitingInput
    case checking
    case connected(URL)
    case failed(String)
}

fileprivate enum MatrixAppPasswordChangeOutcome: Equatable {
    case success
    case successWithCredentialUpdate
    case successWithApplePasswordsUpdate
    case successWithCredentialUpdates
    case successWithCredentialWarning
    case invalidCurrentPassword
    case failed(String)
}

enum MatrixAppAdminAccessState: Equatable {
    case unknown
    case checking
    case authorized
    case denied
}

enum MatrixAppMessageTone: Equatable {
    case success
    case warning
    case error
}

@MainActor
final class MatrixAppModel: ObservableObject {
    typealias ServiceFactory = (MatrixProductConfiguration) -> any MatrixChatService

    @Published var state: MatrixChatState = .signedOut(message: nil)
    @Published var homeserverInput = ""
    @Published var homeserverState: HomeserverOnboardingState = .awaitingInput
    @Published var username = ""
    @Published var password = ""
    @Published var savePasswordToApplePasswords = false
    @Published var messageDraftStore = HyphaMessageDraftStore()
    @Published var rooms: [MatrixRoomSummary] = []
    @Published var trustState: MatrixDeviceTrustState = .unknown
    @Published var verificationFlowState: MatrixVerificationFlowState = .idle
    @Published var recoveryState: MatrixRecoveryState = .unknown
    @Published var firstDeviceTrustBootstrapState: MatrixFirstDeviceTrustBootstrapState = .notBootstrapped
    @Published var peerVerificationEligibility: MatrixPeerVerificationEligibility = .unavailable
    @Published var registrationAvailability: MatrixRegistrationAvailability = .unavailable
    @Published var registrationError: String?
    @Published var showsFirstRunGuidance = false
    @Published var isSyncingRooms = false
    @Published var roomSyncMessage: String?
    @Published var roomSyncMessageTone: MatrixAppMessageTone = .error
    @Published var savedSessions: [MatrixSDKSessionRecord] = []
    @Published var savedCredentials: [HyphaMatrixCredentialDescriptor] = []
    @Published var activeSessionAccountKey: String?
    @Published private(set) var requiresInitialPasswordReset = false
    @Published private(set) var hasPendingHomeserverPasswordResetRequest = false
    @Published private(set) var isAuthenticationOperationInFlight = false
    @Published private(set) var adminAccessState: MatrixAppAdminAccessState = .unknown
    @Published private(set) var adminSnapshot: MatrixAdminSnapshot?
    @Published private(set) var adminPasswordResetRequests: [MatrixPasswordResetRequest] = []
    @Published private(set) var issuedPasswordResetRequestIDs: Set<String> = []
    @Published private(set) var isAdminOperationInFlight = false
    @Published var adminMessage: String?
    @Published private(set) var isPasswordResetRequestInFlight = false
    @Published private(set) var passwordResetRequestMessage: String?

    private static let homeserverDefaultsKey = "ca.zenithresearch.macos.client.matrix.homeserver"
    private static let legacyHomeserverDefaultsKey = [
        "ca", "zenith-research", "mobile-macos", "matrix", "homeserver",
    ].joined(separator: ".")
    private static let legacyDefaultsSuite = ["ca", "zenithresearch", "mobile", "macos"].joined(separator: ".")
    private static let pendingInitialPasswordResetAccountKeys = "ca.zenithresearch.hypha.pending-initial-password-reset-account-keys"
    private let defaults = UserDefaults.standard
    private let legacyDefaults = UserDefaults(suiteName: MatrixAppModel.legacyDefaultsSuite)
    private let healthChecker: MatrixHomeserverHealthChecker
    private let sessionVault: MatrixEncryptedSessionVault
    private let credentialStore: any HyphaMatrixCredentialStore
    private let sharedPasswordStore: any HyphaSharedWebCredentialStore
    private let serviceFactory: ServiceFactory
    private var activeConfiguration: MatrixProductConfiguration?
    private var coordinator: MatrixChatCoordinator?
    private var registrationClient: MatrixInviteRegistrationClient?
    private var timelineRefreshTask: Task<Void, Never>?
    private var authenticationOperationGate = HyphaAuthenticationOperationGate()

    init(
        healthChecker: MatrixHomeserverHealthChecker,
        sessionVault: MatrixEncryptedSessionVault,
        credentialStore: any HyphaMatrixCredentialStore,
        sharedPasswordStore: any HyphaSharedWebCredentialStore = AppleSharedWebCredentialStore(),
        serviceFactory: @escaping ServiceFactory
    ) {
        self.healthChecker = healthChecker
        self.sessionVault = sessionVault
        self.credentialStore = credentialStore
        self.sharedPasswordStore = sharedPasswordStore
        self.serviceFactory = serviceFactory
    }

    var connectedHomeserver: URL? {
        guard case let .connected(url) = homeserverState else { return nil }
        return url
    }

    var isCheckingHomeserver: Bool { homeserverState == .checking }

    var applePasswordsAvailable: Bool {
        guard let domain = activeConfiguration?.homeserver.host else { return false }
        return AppleSharedWebCredentialStore.isAvailable(for: domain)
    }

    var composer: String {
        get { messageDraftStore.activeDraft.text }
        set { messageDraftStore.edit(newValue) }
    }

    var messageDraft: HyphaMessageDraft { messageDraftStore.activeDraft }

    func connectHomeserver() async {
        timelineRefreshTask?.cancel()
        homeserverState = .checking
        password = ""
        do {
            let configuration = try await healthChecker.connect(to: homeserverInput)
            let coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
            activeConfiguration = configuration
            self.coordinator = coordinator
            homeserverInput = configuration.homeserver.absoluteString
            defaults.set(homeserverInput, forKey: Self.homeserverDefaultsKey)
            homeserverState = .connected(configuration.homeserver)
            refreshSavedCredentials(configuration: configuration)
            let sessionsLoaded = refreshSavedSessions(configuration: configuration)
            let startupDecision = MatrixSessionStartupPolicy.decision(
                savedSessionCount: savedSessions.count,
                hasActiveSession: activeSessionAccountKey != nil
            )
            if !sessionsLoaded || startupDecision == .restoreActive {
                await coordinator.restore()
            }
            applyState(from: coordinator)
            applySecurityState(from: coordinator)
            await refreshAdministratorAccess()
            let registrationClient = MatrixInviteRegistrationClient(homeserver: configuration.homeserver)
            self.registrationClient = registrationClient
            registrationAvailability = await registrationClient.availability()
        } catch {
            activeConfiguration = nil
            coordinator = nil
            registrationClient = nil
            registrationAvailability = .unavailable
            savedSessions = []
            savedCredentials = []
            activeSessionAccountKey = nil
            rooms = []
            resetSecurityState()
            resetAdministratorState()
            let message = (error as? LocalizedError)?.errorDescription ?? "The homeserver could not be checked."
            homeserverState = .failed(message)
        }
    }

    func restoreSavedHomeserverIfAvailable() async {
        guard homeserverState == .awaitingInput else { return }
        let currentValue = defaults.string(forKey: Self.homeserverDefaultsKey)
        let legacyValue = legacyDefaults?.string(forKey: Self.legacyHomeserverDefaultsKey)
        guard let savedHomeserver = currentValue ?? legacyValue,
              !savedHomeserver.isEmpty else { return }
        if currentValue == nil {
            defaults.set(savedHomeserver, forKey: Self.homeserverDefaultsKey)
            legacyDefaults?.removeObject(forKey: Self.legacyHomeserverDefaultsKey)
        }
        homeserverInput = savedHomeserver
        await connectHomeserver()
    }

    func changeHomeserver() {
        guard !isAuthenticationOperationInFlight else { return }
        timelineRefreshTask?.cancel()
        timelineRefreshTask = nil
        defaults.removeObject(forKey: Self.homeserverDefaultsKey)
        legacyDefaults?.removeObject(forKey: Self.legacyHomeserverDefaultsKey)
        activeConfiguration = nil
        coordinator = nil
        registrationClient = nil
        registrationAvailability = .unavailable
        registrationError = nil
        showsFirstRunGuidance = false
        savedSessions = []
        savedCredentials = []
        activeSessionAccountKey = nil
        requiresInitialPasswordReset = false
        hasPendingHomeserverPasswordResetRequest = false
        username = ""
        password = ""
        savePasswordToApplePasswords = false
        state = .signedOut(message: nil)
        resetSecurityState()
        resetAdministratorState()
        homeserverState = .awaitingInput
    }

    func createAccount(
        username: String,
        password: String,
        registrationToken: String,
        saveInApplePasswords shouldSaveInApplePasswords: Bool
    ) async -> Bool {
        guard registrationAvailability == .inviteToken,
              let registrationClient,
              let coordinator else { return false }
        guard beginAuthenticationOperation() else { return false }
        defer { finishAuthenticationOperation() }
        registrationError = nil
        do {
            _ = try await registrationClient.register(.init(
                username: username,
                password: password,
                registrationToken: registrationToken
            ))
            self.username = username
            await coordinator.signIn(username: username, password: password)
            applyState(from: coordinator)
            applySecurityState(from: coordinator)
            await refreshAdministratorAccess()
            if let configuration = activeConfiguration {
                refreshSavedSessions(configuration: configuration)
                if case .rooms = state, shouldSaveInApplePasswords {
                    await saveInApplePasswords(
                        password: password,
                        username: username,
                        configuration: configuration,
                        successContext: "Account created"
                    )
                }
            }
            if case .rooms = state {
                showsFirstRunGuidance = true
                return true
            }
            registrationError = "Account created, but sign-in did not complete. Sign in with the new credentials."
            return false
        } catch let error as MatrixAccountRegistrationError {
            switch error {
            case .invalidToken:
                registrationError = "The invite token is invalid, expired, or already exhausted."
            case .invalidInput:
                registrationError = "Choose a username and password, then check the invite token."
            case .unsupportedAuthentication:
                registrationError = "This homeserver requires a registration step Hypha does not support."
            case .unsupportedSingleSignOn:
                registrationError = "This homeserver requires single sign-on registration, which Hypha does not support here."
            case .unsupportedOAuth:
                registrationError = "This homeserver requires OAuth registration, which Hypha does not support here."
            case .captchaRequired:
                registrationError = "This homeserver requires CAPTCHA registration, which Hypha does not support here."
            case .unavailable:
                registrationError = "Invite-token registration is unavailable."
            case .redirectRejected, .originMismatch:
                registrationError = "The homeserver changed the secure registration destination."
            case .invalidResponse:
                registrationError = "The homeserver returned an invalid registration response."
            case .unexpectedServerSession:
                registrationError = "The homeserver unexpectedly created a session Hypha cannot safely adopt."
            case .identityMismatch:
                registrationError = "The homeserver returned a different account identity."
            case .transportFailure:
                registrationError = "The homeserver could not be reached securely."
            case .serverRejected:
                registrationError = "The homeserver rejected account creation."
            }
            return false
        } catch {
            registrationError = "Account creation failed."
            return false
        }
    }

    func dismissFirstRunGuidance() {
        showsFirstRunGuidance = false
    }

    func signIn() async {
        guard let coordinator else { return }
        guard beginAuthenticationOperation() else { return }
        defer { finishAuthenticationOperation() }
        let enteredUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameForRequest = activeConfiguration.flatMap {
            MatrixPasswordLoginPolicy.normalizeUsername(
                enteredUsername,
                activeServerName: $0.homeserver.host ?? ""
            )
        } ?? enteredUsername
        let passwordForRequest = password
        let shouldSaveInApplePasswords = savePasswordToApplePasswords
        let candidateAccountKey = activeConfiguration.map {
            MatrixRustSDKChatService.accountKey(username: usernameForRequest, homeserver: $0.homeserver)
        }
        let hadExistingSession = candidateAccountKey.map { accountKey in
            savedSessions.contains { $0.accountKey == accountKey }
        } ?? false
        password = ""
        savePasswordToApplePasswords = false
        await coordinator.signIn(username: usernameForRequest, password: passwordForRequest)
        applyState(from: coordinator)
        applySecurityState(from: coordinator)
        await refreshAdministratorAccess()
        if let configuration = activeConfiguration {
            refreshSavedSessions(configuration: configuration)
            if case .rooms = state, let candidateAccountKey {
                let serverRequestPending: Bool
                do {
                    serverRequestPending = try await coordinator.hasPendingHomeserverPasswordResetRequest()
                } catch {
                    serverRequestPending = true
                }
                hasPendingHomeserverPasswordResetRequest = serverRequestPending
                if serverRequestPending || MatrixInitialPasswordResetPolicy.requiresReset(
                    authenticationMethod: .manualPassword,
                    hadExistingSession: hadExistingSession
                ) {
                    markInitialPasswordResetRequired(accountKey: candidateAccountKey)
                }
            }
            if case .rooms = state, shouldSaveInApplePasswords {
                await saveInApplePasswords(
                    password: passwordForRequest,
                    username: usernameForRequest,
                    configuration: configuration,
                    successContext: "Signed in"
                )
            }
        }
    }

    func signIn(with credential: HyphaMatrixCredentialDescriptor) async {
        guard let configuration = activeConfiguration,
              MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                  credential.homeserverURL,
                  configured: configuration.homeserver
              ) else { return }
        guard beginAuthenticationOperation() else { return }
        defer { finishAuthenticationOperation() }
        await coordinator?.suspend()
        timelineRefreshTask?.cancel()
        timelineRefreshTask = nil
        do {
            guard let savedPassword = try credentialStore.password(for: credential) else {
                retrySignIn(username: credential.username, message: .savedCredentialUnavailable)
                return
            }
            let coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
            self.coordinator = coordinator
            username = credential.username
            password = ""
            await coordinator.signIn(username: credential.username, password: savedPassword)
            applyState(from: coordinator)
            applySecurityState(from: coordinator)
            await refreshAdministratorAccess()
            refreshSavedSessions(configuration: configuration)
            if case .rooms = state {
                do {
                    try credentialStore.finalizeAuthenticatedMigration(credential)
                } catch {
                    roomSyncMessage = "Signed in, but Hypha could not finish credential migration."
                    roomSyncMessageTone = .warning
                }
            }
            refreshSavedCredentials(configuration: configuration)
        } catch {
            retrySignIn(username: credential.username, message: .savedCredentialUnavailable)
        }
    }

    func switchSession(_ session: MatrixSDKSessionRecord) async {
        guard let configuration = activeConfiguration,
              MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                  session.homeserverURL,
                  configured: configuration.homeserver
              ) else { return }
        guard beginAuthenticationOperation() else { return }
        defer { finishAuthenticationOperation() }
        await coordinator?.suspend()
        timelineRefreshTask?.cancel()
        timelineRefreshTask = nil
        do {
            try sessionVault.activateSession(accountKey: session.accountKey)
            let coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
            self.coordinator = coordinator
            await coordinator.restore()
            applyState(from: coordinator)
            applySecurityState(from: coordinator)
            await refreshAdministratorAccess()
            refreshSavedSessions(configuration: configuration)
        } catch {
            state = .unavailable(reason: "Saved Matrix session could not be opened")
        }
    }

    func deleteLocalSession(_ session: MatrixSDKSessionRecord) async {
        guard let configuration = activeConfiguration, beginAuthenticationOperation() else { return }
        defer { finishAuthenticationOperation() }
        if activeSessionAccountKey == session.accountKey {
            await coordinator?.suspend()
            timelineRefreshTask?.cancel()
            timelineRefreshTask = nil
            rooms = []
            state = .signedOut(message: nil)
            resetSecurityState()
            resetAdministratorState()
        }
        do {
            try sessionVault.deleteSession(accountKey: session.accountKey)
            refreshSavedSessions(configuration: configuration)
        } catch {
            roomSyncMessage = "Hypha could not delete the selected local session."
            roomSyncMessageTone = .error
        }
    }

    func deleteSavedPassword(_ credential: HyphaMatrixCredentialDescriptor) async {
        guard let configuration = activeConfiguration, beginAuthenticationOperation() else { return }
        defer { finishAuthenticationOperation() }
        do {
            try credentialStore.delete(credential)
            refreshSavedCredentials(configuration: configuration)
        } catch {
            roomSyncMessage = "Hypha could not delete the selected saved password."
            roomSyncMessageTone = .error
        }
    }

    func beginAddingAccount() async {
        guard let configuration = activeConfiguration,
              !isAuthenticationOperationInFlight else { return }
        await coordinator?.suspend()
        timelineRefreshTask?.cancel()
        timelineRefreshTask = nil
        coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
        username = ""
        password = ""
        savePasswordToApplePasswords = false
        rooms = []
        requiresInitialPasswordReset = false
        hasPendingHomeserverPasswordResetRequest = false
        resetSecurityState()
        resetAdministratorState()
        state = .signedOut(message: nil)
    }

    private func markInitialPasswordResetRequired(accountKey: String) {
        var pending = Set(defaults.stringArray(forKey: Self.pendingInitialPasswordResetAccountKeys) ?? [])
        pending.insert(accountKey)
        defaults.set(Array(pending).sorted(), forKey: Self.pendingInitialPasswordResetAccountKeys)
        requiresInitialPasswordReset = activeSessionAccountKey == accountKey
    }

    func completeInitialPasswordReset() {
        guard let accountKey = activeSessionAccountKey else { return }
        var pending = Set(defaults.stringArray(forKey: Self.pendingInitialPasswordResetAccountKeys) ?? [])
        pending.remove(accountKey)
        defaults.set(Array(pending).sorted(), forKey: Self.pendingInitialPasswordResetAccountKeys)
        requiresInitialPasswordReset = false
    }

    private func refreshInitialPasswordResetRequirement() {
        guard let accountKey = activeSessionAccountKey else {
            requiresInitialPasswordReset = false
            return
        }
        let pending = Set(defaults.stringArray(forKey: Self.pendingInitialPasswordResetAccountKeys) ?? [])
        requiresInitialPasswordReset = pending.contains(accountKey)
    }

    @discardableResult
    private func refreshSavedSessions(configuration: MatrixProductConfiguration) -> Bool {
        do {
            savedSessions = try sessionVault.storedSessions().filter { session in
                MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                    session.homeserverURL,
                    configured: configuration.homeserver
                )
            }
            activeSessionAccountKey = try sessionVault.loadSession()?.accountKey
            refreshInitialPasswordResetRequirement()
            return true
        } catch {
            savedSessions = []
            activeSessionAccountKey = nil
            requiresInitialPasswordReset = false
            return false
        }
    }

    private func refreshSavedCredentials(configuration: MatrixProductConfiguration) {
        do {
            savedCredentials = try credentialStore.credentials().filter { credential in
                MatrixRustLiveClientFactory.matchesConfiguredHomeserver(
                    credential.homeserverURL,
                    configured: configuration.homeserver
                )
            }
        } catch {
            savedCredentials = []
        }
    }

    @discardableResult
    private func saveInApplePasswords(
        password: String,
        username: String,
        configuration: MatrixProductConfiguration,
        successContext: String,
        announce: Bool = true
    ) async -> Bool {
        guard let domain = configuration.homeserver.host else {
            if announce {
                roomSyncMessage = "\(successContext), but Apple Passwords could not identify this homeserver."
                roomSyncMessageTone = .warning
            }
            return false
        }
        do {
            try await sharedPasswordStore.save(
                password: password,
                username: username,
                domain: domain
            )
            if announce {
                roomSyncMessage = "\(successContext). Password saved in Apple Passwords."
                roomSyncMessageTone = .success
            }
            return true
        } catch {
            if announce {
                roomSyncMessage = "\(successContext), but Apple Passwords did not save the password."
                roomSyncMessageTone = .warning
            }
            return false
        }
    }

    private func beginAuthenticationOperation() -> Bool {
        guard authenticationOperationGate.begin() else { return false }
        isAuthenticationOperationInFlight = authenticationOperationGate.isInFlight
        return true
    }

    private func finishAuthenticationOperation() {
        authenticationOperationGate.finish()
        isAuthenticationOperationInFlight = authenticationOperationGate.isInFlight
    }

    func refreshRooms() async {
        guard let coordinator, !isSyncingRooms else { return }
        isSyncingRooms = true
        roomSyncMessage = nil
        defer { isSyncingRooms = false }
        do {
            rooms = try await coordinator.refreshRooms()
            applyState(from: coordinator)
        } catch {
            roomSyncMessage = "Room sync failed. Check your connection and try again."
            roomSyncMessageTone = .error
        }
    }

    func retrySignIn(
        username: String? = nil,
        message: MatrixSignOutMessage? = nil
    ) {
        password = ""
        savePasswordToApplePasswords = false
        if let username { self.username = username }
        if let configuration = activeConfiguration {
            coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
        }
        state = .signedOut(message: message)
        resetSecurityState()
        resetAdministratorState()
    }

    func bootstrapFirstDeviceTrust() async {
        guard let coordinator else { return }
        guard firstDeviceTrustBootstrapState != .bootstrapping else { return }
        firstDeviceTrustBootstrapState = .bootstrapping
        await coordinator.bootstrapFirstDeviceTrust()
        applySecurityState(from: coordinator)
    }

    func continueFirstDeviceTrust(password: String) async {
        guard let coordinator else { return }
        guard firstDeviceTrustBootstrapState != .bootstrapping else { return }
        firstDeviceTrustBootstrapState = .bootstrapping
        await coordinator.continueFirstDeviceTrust(password: password)
        applySecurityState(from: coordinator)
    }

    func requestDeviceVerification() async {
        guard let coordinator else { return }
        verificationFlowState = .requesting
        await coordinator.requestDeviceVerification()
        applySecurityState(from: coordinator)
    }

    func approveDeviceVerification() async {
        guard let coordinator else { return }
        await coordinator.approveDeviceVerification()
        applySecurityState(from: coordinator)
    }

    func declineDeviceVerification() async {
        guard let coordinator else { return }
        await coordinator.declineDeviceVerification()
        applySecurityState(from: coordinator)
    }

    func refreshDeviceVerification() async {
        guard let coordinator else { return }
        await coordinator.refreshTrustState()
        applySecurityState(from: coordinator)
    }

    func restoreEncryption(recoveryKey: String) async {
        guard let coordinator else { return }
        await coordinator.restoreEncryption(recoveryKey: recoveryKey)
        applySecurityState(from: coordinator)
        if case .ready = recoveryState {
            await coordinator.refreshOpenRoom()
            applyState(from: coordinator)
        }
    }

    func setupEncryptionRecovery() async -> String? {
        guard let coordinator else { return nil }
        let recoveryKey = await coordinator.setupEncryptionRecovery()
        applySecurityState(from: coordinator)
        return recoveryKey
    }

    fileprivate func changePassword(
        currentPassword: String,
        newPassword: String,
        logoutOtherDevices: Bool,
        saveInApplePasswords: Bool
    ) async -> MatrixAppPasswordChangeOutcome {
        guard let coordinator else {
            return .failed("No active Matrix session is available.")
        }
        let result = await coordinator.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
            logoutOtherDevices: logoutOtherDevices
        )
        switch result {
        case .success:
            if hasPendingHomeserverPasswordResetRequest {
                guard await coordinator.completeHomeserverPasswordResetRequest() else {
                    return .failed("The password changed, but Hypha could not close the homeserver reset request. The new password is now your current password. Reconnect and replace it once more to finish safely.")
                }
                hasPendingHomeserverPasswordResetRequest = false
            }
            if requiresInitialPasswordReset {
                completeInitialPasswordReset()
            }
            var updatedApplePasswords = false
            if saveInApplePasswords {
                guard let configuration = activeConfiguration,
                      let accountKey = activeSessionAccountKey,
                      let username = savedSessions.first(where: { $0.accountKey == accountKey })?.userId else {
                    return .successWithCredentialWarning
                }
                updatedApplePasswords = await self.saveInApplePasswords(
                    password: newPassword,
                    username: username,
                    configuration: configuration,
                    successContext: "Password changed",
                    announce: false
                )
                guard updatedApplePasswords else { return .successWithCredentialWarning }
            }
            guard let accountKey = activeSessionAccountKey,
                  let existingCredential = savedCredentials.first(where: { $0.id == accountKey }),
                  let configuration = activeConfiguration else {
                return updatedApplePasswords ? .successWithApplePasswordsUpdate : .success
            }
            do {
                let saved = try credentialStore.savePassword(
                    newPassword,
                    username: existingCredential.username,
                    homeserver: configuration.homeserver
                )
                guard saved.id == existingCredential.id else {
                    return .successWithCredentialWarning
                }
                refreshSavedCredentials(configuration: configuration)
                return updatedApplePasswords ? .successWithCredentialUpdates : .successWithCredentialUpdate
            } catch {
                return .successWithCredentialWarning
            }
        case .invalidCurrentPassword:
            return .invalidCurrentPassword
        case let .failed(message):
            return .failed(message)
        }
    }

    func requestHomeserverPasswordReset() async {
        guard let coordinator, !isPasswordResetRequestInFlight else { return }
        isPasswordResetRequestInFlight = true
        passwordResetRequestMessage = nil
        defer { isPasswordResetRequestInFlight = false }
        let accepted = await coordinator.requestHomeserverPasswordReset()
        guard coordinator === self.coordinator else { return }
        if accepted { hasPendingHomeserverPasswordResetRequest = true }
        passwordResetRequestMessage = accepted
            ? "Password reset requested from the homeserver. An administrator can now issue a temporary password."
            : "The homeserver did not accept the reset request. Check your connection and try again."
    }

    func refreshAdministratorAccess() async {
        guard let coordinator else {
            resetAdministratorState()
            return
        }
        adminAccessState = .checking
        let authorized = await coordinator.isHomeserverAdministrator()
        guard coordinator === self.coordinator else { return }
        adminAccessState = authorized ? .authorized : .denied
        if !authorized { adminSnapshot = nil }
    }

    func refreshAdministratorSnapshot() async {
        guard adminAccessState == .authorized,
              let coordinator,
              !isAdminOperationInFlight else { return }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            let snapshot = try await coordinator.administratorSnapshot()
            guard coordinator === self.coordinator else { return }
            adminSnapshot = snapshot
            do {
                adminPasswordResetRequests = try await coordinator.administratorPasswordResetRequests(users: snapshot.users)
            } catch {
                adminPasswordResetRequests = []
                adminMessage = "Accounts loaded, but password reset requests could not be refreshed."
            }
        } catch {
            applyAdministratorError(error)
        }
    }

    func createAdministratorManagedAccount(
        localpart: String,
        temporaryPassword: String,
        administrator: Bool
    ) async -> Bool {
        guard adminAccessState == .authorized,
              let coordinator,
              !isAdminOperationInFlight else { return false }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            let user = try await coordinator.createAdministratorManagedAccount(
                localpart: localpart,
                temporaryPassword: temporaryPassword,
                administrator: administrator
            )
            guard coordinator === self.coordinator else { return false }
            await publishAdministratorMutationSuccess(
                "Created \(user.userID) as \(user.isAdministrator ? "an administrator" : "a user"). Hypha did not retain the temporary password.",
                coordinator: coordinator
            )
            return true
        } catch {
            applyAdministratorError(error)
            return false
        }
    }

    func resetAdministratorManagedPassword(
        for request: MatrixPasswordResetRequest,
        temporaryPassword: String
    ) async -> Bool {
        guard adminAccessState == .authorized,
              let coordinator,
              !isAdminOperationInFlight else { return false }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            try await coordinator.resetAdministratorManagedPassword(
                for: request,
                temporaryPassword: temporaryPassword
            )
            guard coordinator === self.coordinator else { return false }
            issuedPasswordResetRequestIDs.insert(request.id)
            clearLocalSessions(for: request.userID)
            adminMessage = "Issued a temporary password for \(request.userID), logged out existing devices, and preserved the account role. The authenticated request remains visible but cannot be reset again in this administrator session while the user completes replacement."
            return true
        } catch {
            applyAdministratorError(error)
            return false
        }
    }

    func createAdministratorManagedRoom(name: String, topic: String, asSpace: Bool, visibility: MatrixRoomVisibility) async -> Bool {
        guard adminAccessState == .authorized, let coordinator, !isAdminOperationInFlight else { return false }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            let room = try await coordinator.createAdministratorManagedRoom(name: name, topic: topic, asSpace: asSpace, visibility: visibility)
            guard coordinator === self.coordinator else { return false }
            await publishAdministratorMutationSuccess("Created \(asSpace ? "space" : "encrypted room") \(room.name).", coordinator: coordinator)
            return true
        } catch {
            applyAdministratorError(error)
            return false
        }
    }

    func logoutAdministratorManagedAccount(_ user: MatrixAdminUserSummary) async {
        guard adminAccessState == .authorized, let coordinator, !isAdminOperationInFlight else { return }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            try await coordinator.logoutAdministratorManagedAccount(userID: user.userID)
            clearLocalSessions(for: user.userID)
            if user.userID == adminSnapshot?.currentUserID {
                await coordinator.suspend()
                state = .sessionExpired
                resetAdministratorState()
            } else {
                await publishAdministratorMutationSuccess("Logged out every device for \(user.userID).", coordinator: coordinator)
            }
        } catch { applyAdministratorError(error) }
    }

    private func clearLocalSessions(for userID: String) {
        for session in savedSessions where session.userId == userID {
            try? sessionVault.deleteSession(accountKey: session.accountKey)
        }
        if let configuration = activeConfiguration { refreshSavedSessions(configuration: configuration) }
    }

    func deactivateAdministratorManagedAccount(_ user: MatrixAdminUserSummary) async {
        guard adminAccessState == .authorized,
              let currentUserID = adminSnapshot?.currentUserID,
              !currentUserID.isEmpty,
              user.userID != currentUserID,
              let coordinator,
              !isAdminOperationInFlight else { return }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            try await coordinator.deactivateAdministratorManagedAccount(userID: user.userID)
            guard coordinator === self.coordinator else { return }
            clearLocalSessions(for: user.userID)
            await publishAdministratorMutationSuccess(
                "Deleted \(user.userID)'s active account and profile data. Synapse retained the MXID tombstone and event references.",
                coordinator: coordinator
            )
        } catch {
            applyAdministratorError(error)
        }
    }

    func purgeAdministratorManagedRoom(_ room: MatrixAdminRoomSummary) async {
        guard adminAccessState == .authorized,
              let coordinator,
              !isAdminOperationInFlight else { return }
        isAdminOperationInFlight = true
        adminMessage = nil
        defer { isAdminOperationInFlight = false }
        do {
            try await coordinator.purgeAdministratorManagedRoom(roomID: room.roomID)
            guard coordinator === self.coordinator else { return }
            timelineRefreshTask?.cancel()
            timelineRefreshTask = nil
            rooms.removeAll { $0.id == room.roomID }
            switch state {
            case let .thread(openRoom, _, _) where openRoom.id == room.roomID,
                 let .trustBlocked(openRoom) where openRoom.id == room.roomID:
                state = .rooms(rooms)
            default:
                break
            }
            await publishAdministratorMutationSuccess(
                "Blocked and purged \(room.name) from this homeserver. Federated copies may remain.",
                coordinator: coordinator
            )
        } catch {
            applyAdministratorError(error)
        }
    }

    private func publishAdministratorMutationSuccess(
        _ message: String,
        coordinator: MatrixChatCoordinator
    ) async {
        adminMessage = message
        do {
            let snapshot = try await coordinator.administratorSnapshot()
            guard coordinator === self.coordinator else { return }
            adminSnapshot = snapshot
        } catch {
            adminMessage = message + " The administrator list could not be refreshed."
        }
    }

    private func applyAdministratorError(_ error: Error) {
        switch error as? MatrixAdminClientError {
        case .notAdministrator:
            adminAccessState = .denied
            adminSnapshot = nil
            adminMessage = "Administrator access is no longer available for this account."
        case .sessionExpired:
            adminMessage = "The Matrix session expired. Sign in again before using administration."
        case .offline:
            adminMessage = "Hypha could not reach the homeserver. No administrative change was made."
        case .invalidInput:
            adminMessage = "Check the account or room details and try again."
        case .protectedAccount:
            adminMessage = "Hypha will not deactivate the active administrator account."
        case .credentialNotEstablished:
            adminMessage = "The account record exists, but the homeserver did not confirm a usable local password. Reset or delete the account before handing it off."
        case .invalidResponse, .serverRejected, nil:
            adminMessage = "The homeserver rejected the administrative operation. No success was assumed."
        }
    }

    private func resetAdministratorState() {
        adminAccessState = .unknown
        adminSnapshot = nil
        adminPasswordResetRequests = []
        issuedPasswordResetRequestIDs = []
        isAdminOperationInFlight = false
        adminMessage = nil
    }

    private func applySecurityState(from coordinator: MatrixChatCoordinator) {
        trustState = coordinator.trustState
        verificationFlowState = coordinator.verificationFlowState
        recoveryState = coordinator.recoveryState
        firstDeviceTrustBootstrapState = coordinator.firstDeviceTrustBootstrapState
        peerVerificationEligibility = coordinator.peerVerificationEligibility
    }

    private func resetSecurityState() {
        trustState = .unknown
        verificationFlowState = .idle
        recoveryState = .unknown
        firstDeviceTrustBootstrapState = .notBootstrapped
        peerVerificationEligibility = .unavailable
    }

    private var activeMatrixServerName: String? {
        activeSessionAccountKey
            .flatMap { accountKey in savedSessions.first { $0.accountKey == accountKey } }
            .flatMap { session -> String? in
                let parts = session.userId.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].hasPrefix("@"), !parts[1].isEmpty else { return nil }
                return String(parts[1])
            }
    }

    func resolvedInviteUserIDs(_ invitees: String) -> [String]? {
        let parsedInvitees = invitees
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
        return MatrixRoomInvitationPolicy.resolveUserIDs(
            parsedInvitees,
            defaultServerName: activeMatrixServerName
        )
    }

    func inviteUsers(_ userIDs: [String], to room: MatrixRoomSummary) async -> Bool {
        guard let coordinator else { return false }
        let invited = await coordinator.inviteUsers(userIDs, to: room)
        roomSyncMessage = invited
            ? "Invitations sent to \(room.name)."
            : "Not all invitations could be confirmed. Your room permission may have changed."
        roomSyncMessageTone = invited ? .success : .error
        return invited
    }

    func acceptInvitation(to room: MatrixRoomSummary) async -> Bool {
        guard let coordinator, room.hasInvite else { return false }
        guard let refreshedRooms = await coordinator.acceptInvitation(to: room) else {
            roomSyncMessage = "Could not accept the invitation. It may no longer be pending."
            roomSyncMessageTone = .error
            return false
        }
        rooms = refreshedRooms
        applyState(from: coordinator)
        roomSyncMessage = "Invitation accepted."
        roomSyncMessageTone = .success
        return true
    }

    func declineInvitation(to room: MatrixRoomSummary) async -> Bool {
        guard let coordinator, room.hasInvite else { return false }
        guard let refreshedRooms = await coordinator.declineInvitation(to: room) else {
            roomSyncMessage = "Could not decline the invitation. It may no longer be pending."
            roomSyncMessageTone = .error
            return false
        }
        rooms = refreshedRooms
        applyState(from: coordinator)
        roomSyncMessage = "Invitation declined."
        roomSyncMessageTone = .success
        return true
    }

    func lookupInviteUsers(
        _ userIDs: [String],
        for room: MatrixRoomSummary
    ) async -> [MatrixUserLookupResult] {
        guard let coordinator else { return userIDs.map { _ in .unavailable } }
        if adminAccessState == .authorized {
            await refreshAdministratorSnapshot()
        }
        let authoritativeLocalUsers = adminAccessState == .authorized ? adminSnapshot?.users : nil
        var results: [MatrixUserLookupResult] = []
        for userID in userIDs {
            let parts = userID.split(separator: ":", maxSplits: 1)
            let targetServerName = parts.count == 2 ? String(parts[1]) : nil
            if let authoritativeLocalUsers,
               targetServerName == activeMatrixServerName {
                results.append(MatrixRoomInvitationPolicy.localAccountLookupResult(
                    userID: userID,
                    roomID: room.id,
                    users: authoritativeLocalUsers
                ))
            } else {
                results.append(await coordinator.lookupInviteUser(userID, for: room))
            }
        }
        return results
    }

    func createRoomOrSpace(
        name: String,
        topic: String,
        invitees: String,
        kind: MatrixRoomKind,
        visibility: MatrixRoomVisibility
    ) async {
        guard let coordinator else { return }
        let parsedInvitees = invitees
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let request = MatrixRoomCreationRequest(
            name: name,
            topic: topic,
            invitees: parsedInvitees,
            kind: kind,
            visibility: visibility
        )
        await coordinator.createEncryptedRoom(request)
        applyState(from: coordinator)
        if case let .thread(room, _, _) = state {
            if !rooms.contains(where: { $0.id == room.id }) { rooms.append(room) }
            rooms.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            messageDraftStore.activate(draftContext(for: room))
            startTimelineRefresh(coordinator: coordinator, room: room)
        }
    }

    func removeRoom(_ room: MatrixRoomSummary) async {
        guard let coordinator, room.isCreatedByCurrentUser else {
            roomSyncMessage = "Only the account that created this room can remove it."
            roomSyncMessageTone = .warning
            return
        }
        let removed = await coordinator.removeRoom(room)
        applyState(from: coordinator)
        if removed {
            timelineRefreshTask?.cancel()
            rooms.removeAll { $0.id == room.id }
            roomSyncMessage = "Room left and forgotten for this account."
            roomSyncMessageTone = .success
        } else {
            roomSyncMessage = "Room could not be removed. It remains available to this account."
            roomSyncMessageTone = .error
        }
    }

    func open(_ room: MatrixRoomSummary) async {
        guard let coordinator else { return }
        timelineRefreshTask?.cancel()
        let draftContext = draftContext(for: room)
        await coordinator.open(room: room)
        guard coordinator === self.coordinator else { return }
        applyState(from: coordinator)
        guard case let .thread(openRoom, _, _) = state, openRoom.id == room.id else { return }
        messageDraftStore.activate(draftContext)
        startTimelineRefresh(coordinator: coordinator, room: room)
    }

    private func startTimelineRefresh(coordinator: MatrixChatCoordinator, room: MatrixRoomSummary) {
        timelineRefreshTask?.cancel()
        timelineRefreshTask = Task { [weak self, weak coordinator] in
            while !Task.isCancelled {
                do {
                    try await Task<Never, Never>.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard let self, let coordinator else { return }
                await coordinator.refreshOpenRoom()
                guard coordinator === self.coordinator else { return }
                guard case let .thread(openRoom, _, _) = coordinator.state,
                      openRoom.id == room.id else { return }
                self.applyState(from: coordinator)
            }
        }
    }

    func send() async {
        guard let coordinator,
              case let .thread(room, _, _) = state,
              let activeContext = messageDraftStore.activeContext,
              room.id == activeContext.roomID,
              let submission = messageDraftStore.beginSend() else { return }
        let sent = await coordinator.send(submission.body)
        if sent {
            messageDraftStore.succeedSend(in: submission.context)
        } else {
            messageDraftStore.failSend(
                in: submission.context,
                reason: sendFailureGuidance(for: coordinator.state)
            )
        }
        guard coordinator === self.coordinator else { return }
        applyState(from: coordinator)
    }

    private func draftContext(for room: MatrixRoomSummary) -> HyphaMessageDraftStore.Context {
        let fallbackAccountID = [
            activeConfiguration?.homeserver.absoluteString ?? "unconfigured",
            username,
        ].joined(separator: "|")
        return HyphaMessageDraftStore.Context(
            accountID: activeSessionAccountKey ?? fallbackAccountID,
            roomID: room.id
        )
    }

    private func sendFailureGuidance(for state: MatrixChatState) -> String {
        switch state {
        case .offline:
            "The homeserver is offline. Your draft is still here; reconnect, then retry."
        case .sessionExpired:
            "The Matrix session expired. Your draft is still here; sign in again, then retry."
        case .trustBlocked:
            "Sending is blocked because device trust changed. Your draft was preserved."
        case .recoveryRequired:
            "Encryption recovery is required. Your draft was preserved."
        case let .unavailable(reason):
            "Message not sent: \(reason). Your draft was preserved."
        default:
            "Message not sent. Your draft is still here; review it and retry."
        }
    }

    private func applyState(from coordinator: MatrixChatCoordinator) {
        state = coordinator.state
        if case let .rooms(joinedRooms) = state { rooms = joinedRooms }
        if case .sessionExpired = state, let accountKey = activeSessionAccountKey {
            try? sessionVault.deleteSession(accountKey: accountKey)
            if let configuration = activeConfiguration { refreshSavedSessions(configuration: configuration) }
            resetAdministratorState()
        }
    }
}

private enum HyphaAuthRoute {
    case landing
    case savedAccounts
    case passwordSignIn
    case registration
}

private struct MatrixCompanionShell: View {
    @ObservedObject var model: MatrixAppModel
    @StateObject private var updater = HyphaUpdateController()
    @State private var showsRecovery = false
    @State private var showsRecoverySetup = false
    @State private var showsNewRoom = false
    @State private var showsRoomInvite = false
    @State private var newRoomKind: MatrixRoomKind = .room
    @State private var showsFirstDevicePassword = false
    @State private var showsSecurityCenter = false
    @State private var showsPasswordChange = false
    @State private var showsAdministration = false
    @State private var showsSettings = false
    @State private var showsPasswordResetRequestConfirmation = false
    @State private var roomPendingRemoval: MatrixRoomSummary?
    @State private var roomPendingAcceptance: MatrixRoomSummary?
    @State private var roomPendingDecline: MatrixRoomSummary?
    @State private var invitationAcceptanceInFlightID: String?
    @State private var credentialPendingDeletion: HyphaMatrixCredentialDescriptor?
    @State private var authRoute: HyphaAuthRoute = .landing

    var body: some View {
        Group {
            if isAuthenticated {
                NavigationSplitView {
                    sidebar
                        .navigationTitle("Hypha")
                        .navigationSplitViewColumnWidth(min: 230, ideal: 268, max: 340)
                        .scrollContentBackground(.hidden)
                        .background(ZenithDesign.Palette.baseSubtle)
                } detail: {
                    contentSurface
                        .navigationTitle(detailTitle)
                }
            } else {
                contentSurface
            }
        }
        .sheet(isPresented: $showsRecovery) {
            MatrixRecoverySheet(model: model, isPresented: $showsRecovery)
        }
        .sheet(isPresented: $showsRecoverySetup) {
            MatrixRecoverySetupSheet(model: model, isPresented: $showsRecoverySetup)
        }
        .sheet(isPresented: $showsNewRoom) {
            MatrixNewRoomSheet(
                model: model,
                isPresented: $showsNewRoom,
                kind: $newRoomKind
            )
        }
        .sheet(isPresented: $showsRoomInvite) {
            MatrixRoomInviteSheet(model: model, isPresented: $showsRoomInvite)
        }
        .sheet(isPresented: $showsFirstDevicePassword) {
            MatrixFirstDevicePasswordSheet(model: model, isPresented: $showsFirstDevicePassword)
        }
        .sheet(isPresented: $showsPasswordChange) {
            MatrixChangePasswordSheet(
                model: model,
                isPresented: $showsPasswordChange,
                requiresCompletion: false
            )
        }
        .sheet(isPresented: Binding(
            get: { model.requiresInitialPasswordReset },
            set: { _ in }
        )) {
            MatrixMandatoryPasswordResetSheet(model: model)
        }
        .sheet(isPresented: $showsAdministration) {
            MatrixAdminSheet(model: model, isPresented: $showsAdministration)
        }
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                settingsView
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSettings = false }
                        }
                    }
            }
            .frame(minWidth: 480, idealWidth: 520, minHeight: 360)
        }
        .sheet(isPresented: $showsSecurityCenter) {
            NavigationStack {
                securityCenter
                    .navigationTitle("Security")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSecurityCenter = false }
                        }
                    }
            }
            .frame(minWidth: 580, idealWidth: 640, minHeight: 320)
        }
        .confirmationDialog(
            "Delete this saved password?",
            isPresented: Binding(
                get: { credentialPendingDeletion != nil },
                set: { if !$0 { credentialPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: credentialPendingDeletion
        ) { credential in
            Button("Delete saved password", role: .destructive) {
                credentialPendingDeletion = nil
                Task { await model.deleteSavedPassword(credential) }
            }
            Button("Cancel", role: .cancel) { credentialPendingDeletion = nil }
        } message: { credential in
            Text("This removes the saved password for \(credential.username) from Hypha on this Mac. Any active encrypted session remains signed in.")
        }
    }

    private var contentSurface: some View {
        VStack(spacing: 0) {
            if let homeserver = model.connectedHomeserver {
                HStack {
                    Label(
                        "Connected to \(homeserver.host ?? homeserver.absoluteString)",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(ZenithDesign.Typography.technical(size: 13, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    Spacer()
                    Button("Change homeserver") {
                        authRoute = .landing
                        model.changeHomeserver()
                    }
                    .buttonStyle(.link)
                    .disabled(model.isAuthenticationOperationInFlight)
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ZenithDesign.Space.x4)
                .padding(.vertical, ZenithDesign.Space.x2)
                .background(ZenithDesign.Palette.baseSubtle)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ZenithDesign.Palette.border)
                        .frame(height: 1)
                }
            }
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ZenithDesign.Palette.base)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showsSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("hypha.settings")
                securityToolbarMenu
            }
        }
    }

    private var detailTitle: String {
        switch model.state {
        case let .thread(room, _, _), let .trustBlocked(room):
            return room.name
        default:
            return "Chat"
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        switch model.state {
        case .rooms, .thread, .trustBlocked:
            roomList(model.rooms)
        default:
            List {
                Label("Matrix", systemImage: "message.fill")
                    .font(.headline)
                Text(model.connectedHomeserver == nil ? "Connect a Matrix homeserver" : "Sign in to load encrypted rooms")
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
        }
    }

    private var roomSyncMessageColor: Color {
        switch model.roomSyncMessageTone {
        case .success: ZenithDesign.Palette.success
        case .warning: ZenithDesign.Palette.warning
        case .error: ZenithDesign.Palette.error
        }
    }

    private func roomList(_ rooms: [MatrixRoomSummary]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                HStack(spacing: ZenithDesign.Space.x2) {
                    if !model.savedSessions.isEmpty || !model.savedCredentials.isEmpty {
                        accountSwitcher
                    }
                    Spacer(minLength: 0)
                    Button {
                        Task { await model.refreshRooms() }
                    } label: {
                        if model.isSyncingRooms {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Syncing rooms")
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .accessibilityLabel("Sync rooms")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isSyncingRooms)
                    .accessibilityIdentifier("matrix.rooms.sync")
                }
                .padding(.bottom, ZenithDesign.Space.x2)

                if let roomSyncMessage = model.roomSyncMessage {
                    Text(roomSyncMessage)
                        .font(.caption)
                        .foregroundStyle(roomSyncMessageColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let groups = MatrixSidebarRoomGroups(rooms: rooms)

                sidebarSectionTitle("DMs")
                if groups.directMessages.isEmpty {
                    Text("No DMs yet.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                } else {
                    ForEach(groups.directMessages) { room in
                        roomRow(room)
                    }
                }

                sidebarSectionTitle("Invites")
                    .padding(.top, ZenithDesign.Space.x2)
                if groups.invitations.isEmpty {
                    Text("No pending invites.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                } else {
                    ForEach(groups.invitations) { room in
                        HStack(spacing: ZenithDesign.Space.x2) {
                            Image(systemName: "envelope.badge.fill")
                                .foregroundStyle(ZenithDesign.Palette.brand)
                            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                                Text(room.name)
                                    .lineLimit(2)
                                Text("Invitation")
                                    .font(.caption)
                                    .foregroundStyle(ZenithDesign.Palette.muted)
                            }
                            Spacer()
                            HStack(spacing: ZenithDesign.Space.x2) {
                                Button {
                                    roomPendingAcceptance = room
                                } label: {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(ZenithDesign.Palette.success)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .disabled(invitationAcceptanceInFlightID != nil)
                                .accessibilityLabel("Accept invite")
                                .accessibilityIdentifier("matrix.room.invite.accept")

                                Button {
                                    roomPendingDecline = room
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(ZenithDesign.Palette.muted)
                                        .frame(width: 22, height: 22)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Circle())
                                .disabled(invitationAcceptanceInFlightID != nil)
                                .accessibilityLabel("Decline invite")
                                .accessibilityIdentifier("matrix.room.invite.decline")
                            }
                        }
                        .padding(.horizontal, ZenithDesign.Space.x3)
                        .padding(.vertical, ZenithDesign.Space.x2)
                        .background(ZenithDesign.Palette.baseRaised.opacity(0.55))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: ZenithDesign.Radius.control,
                                style: .continuous
                            )
                        )
                        .accessibilityIdentifier("matrix.room.invite")
                        .id("matrix.invitation.\(room.id)")
                    }
                }

                sidebarCreationHeader("Spaces", kind: .space)
                    .padding(.top, ZenithDesign.Space.x2)
                if groups.spaces.isEmpty {
                    Text("No Spaces yet.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                } else {
                    ForEach(groups.spaces) { space in
                        roomRow(space)
                    }
                }

                sidebarCreationHeader("Rooms", kind: .room)
                    .padding(.top, ZenithDesign.Space.x2)

                if groups.rooms.isEmpty {
                    Text("No joined rooms yet.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                } else {
                    ForEach(groups.rooms) { room in
                        roomRow(room)
                            .id("matrix.joined-room.\(room.id)")
                    }
                }
            }
            .padding(ZenithDesign.Space.x3)
            .foregroundStyle(ZenithDesign.Palette.content)
        }
        .background(ZenithDesign.Palette.baseSubtle)
        .accessibilityIdentifier("matrix.rooms.sidebar")
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            "Delete \(roomPendingRemoval?.isSpace == true ? "space" : "room") from this account?",
            isPresented: Binding(
                get: { roomPendingRemoval != nil },
                set: { if !$0 { roomPendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: roomPendingRemoval
        ) { room in
            Button("Leave and forget", role: .destructive) {
                roomPendingRemoval = nil
                Task { await model.removeRoom(room) }
            }
            .accessibilityIdentifier("matrix.room.remove.confirm")
            Button("Cancel", role: .cancel) { roomPendingRemoval = nil }
        } message: { room in
            Text("This removes \(room.name) from the active account by leaving and forgetting it. Matrix does not erase copies held by other members or servers.")
        }
        .confirmationDialog(
            "Accept this invitation?",
            isPresented: Binding(
                get: { roomPendingAcceptance != nil },
                set: { if !$0 { roomPendingAcceptance = nil } }
            ),
            titleVisibility: .visible,
            presenting: roomPendingAcceptance
        ) { room in
            Button("Accept invite") {
                roomPendingAcceptance = nil
                invitationAcceptanceInFlightID = room.id
                Task {
                    _ = await model.acceptInvitation(to: room)
                    invitationAcceptanceInFlightID = nil
                }
            }
            .accessibilityIdentifier("matrix.room.invite.accept.confirm")
            Button("Cancel", role: .cancel) { roomPendingAcceptance = nil }
        } message: { room in
            Text("Join \(room.name) with the active Matrix account?")
        }
        .confirmationDialog(
            "Decline this invitation?",
            isPresented: Binding(
                get: { roomPendingDecline != nil },
                set: { if !$0 { roomPendingDecline = nil } }
            ),
            titleVisibility: .visible,
            presenting: roomPendingDecline
        ) { room in
            Button("Decline invite", role: .destructive) {
                roomPendingDecline = nil
                invitationAcceptanceInFlightID = room.id
                Task {
                    _ = await model.declineInvitation(to: room)
                    invitationAcceptanceInFlightID = nil
                }
            }
            .accessibilityIdentifier("matrix.room.invite.decline.confirm")
            Button("Cancel", role: .cancel) { roomPendingDecline = nil }
        } message: { room in
            Text("Decline the invitation to \(room.name) for the active Matrix account?")
        }
    }

    private var settingsView: some View {
        Form {
            Section("Account & Password") {
                Button {
                    showsSettings = false
                    Task {
                        await Task.yield()
                        showsPasswordChange = true
                    }
                } label: {
                    Label("Change password", systemImage: "key")
                }
                .accessibilityIdentifier("matrix.password.change.settings")

                Button {
                    showsPasswordResetRequestConfirmation = true
                } label: {
                    Label("Request homeserver password reset", systemImage: "person.badge.key")
                }
                .disabled(model.isPasswordResetRequestInFlight)
                .accessibilityIdentifier("matrix.password.reset.request")

                Text("Request a reset only when an administrator needs to issue a temporary password. The request contains no password or credential material.")
                    .font(.caption)
                    .foregroundStyle(ZenithDesign.Palette.muted)

                if let message = model.passwordResetRequestMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .accessibilityIdentifier("matrix.password.reset.request.status")
                }
            }

            Section("Application Updates") {
                Text("Pull the latest main branch from the canonical Hypha GitHub remote, rebuild the app locally, verify it, and install it in place.")
                    .font(.callout)
                    .foregroundStyle(ZenithDesign.Palette.muted)

                Button {
                    updater.updateFromGitHubMain()
                } label: {
                    Label(
                        updater.state == .updating ? "Updating from GitHub main…" : "Update from GitHub main",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .buttonStyle(HyphaButtonStyle(.primary))
                .disabled(updater.state == .updating)
                .accessibilityIdentifier("hypha.update.main")

                if let statusText = updater.statusText {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(updater.state == .failed ? ZenithDesign.Palette.error : ZenithDesign.Palette.muted)
                }

                if updater.state == .installed {
                    Button("Restart Hypha") {
                        updater.restart()
                    }
                    .buttonStyle(HyphaButtonStyle(.secondary))
                    .accessibilityIdentifier("hypha.update.restart")
                }
            }
        }
        .formStyle(.grouped)
        .padding(ZenithDesign.Space.x3)
        .confirmationDialog(
            "Request a homeserver password reset?",
            isPresented: $showsPasswordResetRequestConfirmation,
            titleVisibility: .visible
        ) {
            Button("Request reset") {
                Task { await model.requestHomeserverPasswordReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A homeserver administrator will be able to replace your password with a temporary password and log out your existing devices. No password is included in the request.")
        }
    }

    private var accountSwitcher: some View {
        Menu {
            ForEach(model.savedSessions, id: \.accountKey) { session in
                Button {
                    Task { await model.switchSession(session) }
                } label: {
                    if model.activeSessionAccountKey == session.accountKey {
                        Label(session.userId, systemImage: "checkmark")
                    } else {
                        Text(session.userId)
                    }
                }
                .disabled(model.activeSessionAccountKey == session.accountKey)
            }
            if !model.savedCredentials.isEmpty {
                Divider()
                ForEach(model.savedCredentials) { credential in
                    Button {
                        Task { await model.signIn(with: credential) }
                    } label: {
                        Label(
                            "Sign in as \(credential.username)",
                            systemImage: "key.fill"
                        )
                    }
                }
                Divider()
                Menu {
                    ForEach(model.savedCredentials) { credential in
                        Button("Delete \(credential.username)'s saved password…", role: .destructive) {
                            credentialPendingDeletion = credential
                        }
                    }
                } label: {
                    Label("Manage saved passwords", systemImage: "key.slash")
                }
                .accessibilityIdentifier("matrix.password.manage")
            }
            Divider()
            Button {
                Task {
                    await model.beginAddingAccount()
                    authRoute = .landing
                }
            } label: {
                Label("Sign in another account", systemImage: "person.badge.plus")
            }
            .accessibilityIdentifier("matrix.session.add")
        } label: {
            Label("Switch account", systemImage: "person.2.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("matrix.session.switcher")
    }

    private func sidebarCreationHeader(_ title: String, kind: MatrixRoomKind) -> some View {
        HStack(spacing: ZenithDesign.Space.x2) {
            sidebarSectionTitle(title)
            Spacer(minLength: 0)
            if kind == .room,
               !MatrixRoomInvitationPolicy.eligibleRooms(from: model.rooms).isEmpty {
                HyphaIconButton(
                    systemImage: "person.badge.plus",
                    accessibilityLabel: "Invite members to a room"
                ) {
                    showsRoomInvite = true
                }
                .accessibilityIdentifier("matrix.room.invite.inline")
            }
            HyphaIconButton(
                systemImage: "plus",
                accessibilityLabel: "Add \(kind == .space ? "Space" : "room")"
            ) {
                newRoomKind = kind
                showsNewRoom = true
            }
            .accessibilityIdentifier(kind == .space ? "matrix.space.create.inline" : "matrix.room.create.inline")
        }
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(ZenithDesign.Palette.muted)
            .padding(.horizontal, ZenithDesign.Space.x2)
            .padding(.bottom, ZenithDesign.Space.x1)
    }

    private func roomRow(_ room: MatrixRoomSummary) -> some View {
        HStack(spacing: ZenithDesign.Space.x2) {
            Button {
                Task { await model.open(room) }
            } label: {
                HStack(spacing: ZenithDesign.Space.x2) {
                    Image(systemName: room.isSpace ? "square.grid.2x2.fill" : (room.isEncrypted ? "lock.fill" : "lock.open.fill"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            room.isSpace || room.isEncrypted
                                ? ZenithDesign.Palette.brand
                                : ZenithDesign.Palette.warning
                        )
                    Text(room.name)
                        .font(ZenithDesign.Typography.corporate(.callout, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(ZenithDesign.Palette.content)
                    if room.isSpace {
                        Text("SPACE")
                            .font(ZenithDesign.Typography.technical(size: 9, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(ZenithDesign.Palette.brand)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(room.isSpace ? "Space" : "room") \(room.name)")
            .accessibilityHint(room.isSpace ? "Matrix Space containing related rooms" : (room.isEncrypted ? "Encrypted room" : "Unencrypted room"))
            .accessibilityIdentifier("matrix.room.row")

            if room.isCreatedByCurrentUser {
                Menu {
                    Button("Delete \(room.isSpace ? "space" : "room") from this account…", role: .destructive) {
                        roomPendingRemoval = room
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .accessibilityLabel("Room actions for \(room.name)")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("matrix.room.remove")
            }
        }
        .padding(.horizontal, ZenithDesign.Space.x2)
        .padding(.vertical, ZenithDesign.Space.x1)
        .background(
            isSelected(room)
                ? ZenithDesign.Palette.baseRaised
                : ZenithDesign.Palette.base.opacity(0.34)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: ZenithDesign.Radius.control,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ZenithDesign.Radius.control,
                style: .continuous
            )
            .stroke(
                isSelected(room)
                    ? ZenithDesign.Palette.borderStrong
                    : ZenithDesign.Palette.border,
                lineWidth: 1
            )
        }
    }

    private func isSelected(_ room: MatrixRoomSummary) -> Bool {
        switch model.state {
        case let .thread(selectedRoom, _, _), let .trustBlocked(selectedRoom):
            return selectedRoom.id == room.id
        default:
            return false
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.connectedHomeserver == nil {
            homeserverSetup
        } else {
            VStack(spacing: 0) {
                if isAuthenticated {
                    if model.showsFirstRunGuidance {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Account created. Encrypted rooms and chat are ready now.")
                                    .font(.headline)
                                Text("Device security and recovery are optional next steps.")
                                    .font(.caption)
                                    .foregroundStyle(ZenithDesign.Palette.muted)
                            }
                            Spacer()
                            Button("Not now") {
                                model.dismissFirstRunGuidance()
                            }
                        }
                        .padding(12)
                        .background(.blue.opacity(0.08))
                        .accessibilityIdentifier("matrix.registration.first-run")
                    }
                    if securityPresentation.requiresPersistentCriticalBanner {
                        criticalSecurityStrip
                    }
                }
                chatDetail
            }
        }
    }

    private var isAuthenticated: Bool {
        switch model.state {
        case .rooms, .thread, .trustBlocked:
            return true
        default:
            return false
        }
    }

    private func beginFirstDeviceSetup() {
        showsSecurityCenter = true
        Task {
            await model.bootstrapFirstDeviceTrust()
            if model.firstDeviceTrustBootstrapState == .passwordRequired {
                showsSecurityCenter = false
                await Task.yield()
                showsFirstDevicePassword = true
            }
        }
    }

    private func continueFirstDeviceSetup() {
        showsSecurityCenter = false
        Task {
            await Task.yield()
            showsFirstDevicePassword = true
        }
    }

    private func beginPeerVerification() {
        showsSecurityCenter = true
        Task { await model.requestDeviceVerification() }
    }

    private func openRecoverySetup() {
        showsSecurityCenter = false
        Task {
            await Task.yield()
            showsRecoverySetup = true
        }
    }

    private func openRecoveryRestore() {
        showsSecurityCenter = false
        Task {
            await Task.yield()
            showsRecovery = true
        }
    }

    private func openPasswordChange() {
        showsSecurityCenter = false
        Task {
            await Task.yield()
            showsPasswordChange = true
        }
    }

    private func openAdministration() {
        showsSecurityCenter = false
        Task {
            await Task.yield()
            showsAdministration = true
        }
    }

    private var securityPresentation: HyphaSecurityPresentationState {
        HyphaSecurityPresentationPolicy.presentation(
            trustState: model.trustState,
            firstDeviceTrustBootstrapState: model.firstDeviceTrustBootstrapState,
            verificationFlowState: model.verificationFlowState,
            recoveryState: model.recoveryState,
            peerVerificationEligibility: model.peerVerificationEligibility
        )
    }

    private var securityBanner: some View {
        HyphaSecurityBanner(
            presentation: securityPresentation,
            onSetUpDevice: beginFirstDeviceSetup,
            onContinueDeviceSetup: continueFirstDeviceSetup,
            onRequestVerification: beginPeerVerification,
            onApproveVerification: { Task { await model.approveDeviceVerification() } },
            onDeclineVerification: { Task { await model.declineDeviceVerification() } },
            onRefresh: { Task { await model.refreshDeviceVerification() } },
            onSetUpRecovery: openRecoverySetup,
            onRestoreRecovery: openRecoveryRestore
        )
    }

    private var securityCenter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x5) {
                securityBanner

                Divider()

                VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                    Text("ACCOUNT SECURITY")
                        .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                    Text("Password")
                        .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                    Text("Change the password used to sign in to this Hypha account.")
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                    Button("Change Password…", action: openPasswordChange)
                        .buttonStyle(HyphaButtonStyle(.secondary))
                        .accessibilityIdentifier("matrix.password.open")
                    if model.adminAccessState == .authorized {
                        Button("Homeserver Administration…", action: openAdministration)
                            .buttonStyle(HyphaButtonStyle(.secondary))
                            .accessibilityIdentifier("matrix.admin.open")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ZenithDesign.Space.x5)
                .padding(.bottom, ZenithDesign.Space.x5)
            }
            .padding(.top, ZenithDesign.Space.x2)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(ZenithDesign.Palette.base)
    }

    @ViewBuilder
    private var securityToolbarMenu: some View {
        if isAuthenticated {
            Menu {
                switch securityPresentation.primaryDeviceAction {
                case .setUpThisDevice:
                    Button("Set Up This Device", action: beginFirstDeviceSetup)
                case .verifyWithAnotherHyphaDevice:
                    Button("Verify with Another Hypha Device", action: beginPeerVerification)
                case .continueDeviceSetupWithPassword:
                    Button("Continue Device Setup…", action: continueFirstDeviceSetup)
                case nil:
                    EmptyView()
                }

                if case .deviceSetupFailed = securityPresentation.localOperation {
                    Button("Try Device Setup Again", action: beginFirstDeviceSetup)
                }

                switch securityPresentation.recoveryAction {
                case .setUpRecovery:
                    Button("Set Up Recovery…", action: openRecoverySetup)
                case .restoreEncryption:
                    Button("Restore Encryption…", action: openRecoveryRestore)
                case nil:
                    EmptyView()
                }

                Divider()
                Button("Change Password…", action: openPasswordChange)
                if model.adminAccessState == .authorized {
                    Button("Homeserver Administration…", action: openAdministration)
                        .accessibilityIdentifier("matrix.admin.open")
                }
                Button("Refresh Security Status") {
                    Task { await model.refreshDeviceVerification() }
                }
                Button("Security Center…") {
                    showsSecurityCenter = true
                }
                .accessibilityIdentifier("matrix.security.center.open")
            } label: {
                Label {
                    Text("Security")
                } icon: {
                    Image(systemName: securityToolbarSymbol)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help("Device verification and encryption recovery")
            .accessibilityIdentifier("matrix.security.menu")
        }
    }

    private var securityToolbarSymbol: String {
        switch securityPresentation.indicatorSeverity {
        case .unknown:
            return "questionmark.shield"
        case .recommended:
            return "exclamationmark.shield.fill"
        case .secure:
            return "checkmark.shield.fill"
        case .critical:
            return "xmark.shield.fill"
        }
    }

    private var criticalSecurityStrip: some View {
        Button {
            showsSecurityCenter = true
        } label: {
            HStack(spacing: ZenithDesign.Space.x2) {
                Image(systemName: "xmark.shield.fill")
                    .foregroundStyle(ZenithDesign.Palette.error)
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    Text("Device identity verification failed")
                        .font(.headline)
                    Text("Security-sensitive chat actions remain blocked. Open Security Center for details.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                Spacer()
                Text("Review")
                    .foregroundStyle(ZenithDesign.Palette.brand)
            }
            .padding(.horizontal, ZenithDesign.Space.x4)
            .padding(.vertical, ZenithDesign.Space.x2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ZenithDesign.Palette.error.opacity(0.11))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZenithDesign.Palette.error.opacity(0.5))
                .frame(height: 2)
        }
        .accessibilityIdentifier("matrix.security.critical")
    }

    @ViewBuilder
    private var chatDetail: some View {
        switch model.state {
        case let .signedOut(message):
            authenticationDetail(message: message)
        case .restoring:
            ProgressView("Restoring encrypted session…")
                .padding(40)
        case .rooms:
            statePanel(
                title: "Choose a room",
                message: "Encrypted rooms available to this account appear in the sidebar.",
                symbol: "message",
                identifier: "matrix.rooms.empty-selection"
            )
        case let .thread(room, events, composer):
            if room.isSpace {
                HyphaSpaceView(space: room)
            } else {
                thread(room: room, events: events, composerState: composer)
            }
        case .sessionExpired:
            passwordFallbackPanel(
                title: "Session expired",
                message: "Sign in again. Local crypto state is preserved unless you explicitly forget this device.",
                symbol: "person.crop.circle.badge.exclamationmark",
                identifier: "matrix.session.expired"
            )
        case .offline:
            statePanel(
                title: "Offline",
                message: "Hypha cannot reach the homeserver. No message was downgraded or sent.",
                symbol: "wifi.slash",
                identifier: "matrix.offline"
            )
        case let .trustBlocked(room):
            statePanel(
                title: "Device trust changed",
                message: "Sending to \(room.name) is blocked until the identity change is reviewed.",
                symbol: "exclamationmark.shield.fill",
                identifier: "matrix.trust.blocked"
            )
        case .recoveryRequired:
            passwordFallbackPanel(
                title: "Recovery required",
                message: "The encrypted store cannot be restored safely. Password sign-in remains available without overwriting the existing crypto store.",
                symbol: "key.horizontal.fill",
                identifier: "matrix.recovery.required"
            )
        case let .unavailable(reason):
            unavailablePanel(reason: reason)
        }
    }

    private var homeserverSetup: some View {
        VStack(spacing: 18) {
            Image(systemName: "network")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("Connect your homeserver")
                .font(ZenithDesign.Typography.technical(size: 32, weight: .semibold))
            Text("Enter the Matrix homeserver you want Hypha to use. Hypha checks its client endpoint before asking for credentials.")
                .multilineTextAlignment(.center)
                .foregroundStyle(ZenithDesign.Palette.muted)
                .frame(maxWidth: 480)
            TextField("https://matrix.example.org", text: $model.homeserverInput)
                .textFieldStyle(ZenithInputStyle())
                .accessibilityIdentifier("matrix.homeserver.url")
                .onSubmit {
                    guard !model.isCheckingHomeserver else { return }
                    Task { await model.connectHomeserver() }
                }
            Text("Remote homeservers must use HTTPS. HTTP is accepted only for a loopback development server.")
                .font(.caption)
                .foregroundStyle(ZenithDesign.Palette.muted)
            if case let .failed(message) = model.homeserverState {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(ZenithDesign.Palette.error)
                    .accessibilityIdentifier("matrix.homeserver.error")
            }
            Button {
                Task { await model.connectHomeserver() }
            } label: {
                if model.isCheckingHomeserver {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Check and connect")
                }
            }
            .buttonStyle(ZenithPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(
                model.isCheckingHomeserver ||
                model.homeserverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .accessibilityIdentifier("matrix.homeserver.connect")
        }
        .frame(maxWidth: 520)
        .padding(40)
    }

    @ViewBuilder
    private func authenticationDetail(message: MatrixSignOutMessage?) -> some View {
        let accountChoices = HyphaLoginAccountChoice.grouped(
            sessions: model.savedSessions,
            credentials: model.savedCredentials
        )

        switch authRoute {
        case .landing:
            HyphaAuthLandingView(
                model: model,
                hasSavedAccounts: !accountChoices.isEmpty,
                openSavedAccounts: { authRoute = .savedAccounts },
                openPasswordSignIn: { authRoute = .passwordSignIn },
                openRegistration: {
                    model.registrationError = nil
                    authRoute = .registration
                }
            )
        case .savedAccounts:
            HyphaSavedAccountsView(
                model: model,
                choices: accountChoices,
                back: { authRoute = .landing },
                continueSession: { session in
                    await model.switchSession(session)
                },
                signInWithSavedPassword: { credential in
                    await model.signIn(with: credential)
                    if case .signedOut = model.state {
                        authRoute = .passwordSignIn
                    }
                },
                deleteLocalSession: { session in
                    await model.deleteLocalSession(session)
                },
                deleteSavedPassword: { credential in
                    await model.deleteSavedPassword(credential)
                },
                usePassword: { authRoute = .passwordSignIn }
            )
        case .passwordSignIn:
            HyphaPasswordSignInView(
                model: model,
                message: message,
                back: { authRoute = .landing }
            )
        case .registration:
            HyphaRegistrationView(
                model: model,
                back: { authRoute = .landing }
            )
        }
    }

    private func thread(
        room: MatrixRoomSummary,
        events: [MatrixTimelineEvent],
        composerState: MatrixComposerState
    ) -> some View {
        VStack(spacing: 0) {
            HyphaChatTimeline(room: room, events: events)

            ZenithMessageComposer(
                text: $model.composer,
                roomName: room.name,
                isSending: model.messageDraft.isSending,
                disabledReason: composerDisabledReason(composerState),
                failureReason: model.messageDraft.failureReason,
                send: { Task { await model.send() } }
            )
        }
    }

    private func composerDisabledReason(_ state: MatrixComposerState) -> String? {
        switch state {
        case .ready:
            nil
        case .sending:
            "Another message is already sending."
        case let .disabled(reason):
            reason
        }
    }

    private func passwordFallbackPanel(
        title: String,
        message: String,
        symbol: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 0) {
            statePanel(title: title, message: message, symbol: symbol, identifier: identifier)
            Button("Sign in with password") {
                model.retrySignIn()
                authRoute = .passwordSignIn
            }
                .buttonStyle(ZenithPrimaryButtonStyle())
                .accessibilityIdentifier("matrix.login.password-fallback-action")
        }
    }

    private func unavailablePanel(reason: String) -> some View {
        VStack(spacing: 0) {
            statePanel(
                title: "Matrix unavailable",
                message: reason,
                symbol: "wrench.and.screwdriver.fill",
                identifier: "matrix.unavailable"
            )
            Button("Sign in with password") {
                model.retrySignIn()
                authRoute = .passwordSignIn
            }
                .buttonStyle(ZenithPrimaryButtonStyle())
                .accessibilityIdentifier("matrix.login.retry")
        }
    }

    private func statePanel(title: String, message: String, symbol: String, identifier: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 42))
                .foregroundStyle(ZenithDesign.Palette.muted)
            Text(title)
                .font(ZenithDesign.Typography.technical(size: 22, weight: .semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(ZenithDesign.Palette.muted)
                .frame(maxWidth: 440)
        }
            .accessibilityIdentifier(identifier)
            .padding(40)
    }
}

private struct HyphaChatTimeline: View {
    let room: MatrixRoomSummary
    let events: [MatrixTimelineEvent]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveEdgeState: HyphaChatLiveEdgePolicy.State?

    private var latestAnchor: String { "matrix.thread.latest.\(room.id)" }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                List {
                    if events.isEmpty {
                        HyphaChatEmptyState(isEncrypted: room.isEncrypted)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(events.indices, id: \.self) { index in
                            HyphaChatMessageRow(
                                event: events[index],
                                previousEvent: index > events.startIndex ? events[index - 1] : nil,
                                nextEvent: index < events.index(before: events.endIndex) ? events[index + 1] : nil
                            )
                            .id(events[index].id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(latestAnchor)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
                .scrollContentBackground(.hidden)
                .background(ZenithDesign.Palette.base)
                .accessibilityIdentifier("matrix.thread.timeline")
                .onAppear { openRoom(at: proxy) }
                .onChange(of: room.id) { _, _ in openRoom(at: proxy) }
                .onChange(of: events.map(\.id)) { _, eventIDs in
                    eventsUpdated(eventIDs: eventIDs, at: proxy)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height <= geometry.containerSize.height
                        || geometry.visibleRect.maxY >= geometry.contentSize.height - 80
                } action: { _, isAtLiveEdge in
                    guard liveEdgeState?.roomID == room.id else { return }
                    _ = HyphaChatLiveEdgePolicy.reduce(
                        state: &liveEdgeState,
                        event: .liveEdgeChanged(isAtLiveEdge)
                    )
                }

                if liveEdgeState?.showsNewMessageAffordance == true {
                    Button {
                        let decision = HyphaChatLiveEdgePolicy.reduce(
                            state: &liveEdgeState,
                            event: .jumpToLatest
                        )
                        scrollToLatest(if: decision.autoScrollToLatest, proxy: proxy, animated: true)
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down.to.line.compact")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(ZenithDesign.Space.x4)
                    .accessibilityHint("Moves to the newest message and resumes following new messages.")
                    .accessibilityIdentifier("matrix.thread.jump-to-latest")
                }
            }
            .onChange(of: liveEdgeState?.showsNewMessageAffordance) { previous, current in
                guard previous != true, current == true else { return }
                AccessibilityNotification.Announcement(
                    "New messages are available. Jump to latest is now available."
                ).post()
            }
        }
    }

    private func openRoom(at proxy: ScrollViewProxy) {
        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &liveEdgeState,
            event: .roomOpenedWithEvents(roomID: room.id, eventIDs: events.map(\.id))
        )
        scrollToLatest(if: decision.autoScrollToLatest, proxy: proxy, animated: false)
    }

    private func eventsUpdated(eventIDs: [String], at proxy: ScrollViewProxy) {
        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &liveEdgeState,
            event: .eventsUpdatedWithEvents(roomID: room.id, eventIDs: eventIDs)
        )
        scrollToLatest(if: decision.autoScrollToLatest, proxy: proxy, animated: true)
    }

    private func scrollToLatest(if shouldScroll: Bool, proxy: ScrollViewProxy, animated: Bool) {
        guard shouldScroll else { return }
        Task { @MainActor in
            await Task.yield()
            if animated && !reduceMotion {
                withAnimation { proxy.scrollTo(latestAnchor, anchor: .bottom) }
            } else {
                proxy.scrollTo(latestAnchor, anchor: .bottom)
            }
        }
    }
}

private struct ZenithMessageComposer: View {
    @Binding var text: String
    let roomName: String
    let isSending: Bool
    let disabledReason: String?
    let failureReason: String?
    let send: () -> Void
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isSending && disabledReason == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
            HStack(spacing: ZenithDesign.Space.x3) {
                TextField("Message \(roomName)", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(ZenithDesign.Typography.corporate(.body, weight: .medium))
                    .foregroundStyle(ZenithDesign.Palette.content)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .accessibilityIdentifier("matrix.thread.composer")
                    .onSubmit { submitIfReady() }

                Button(action: submitIfReady) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(canSend ? ZenithDesign.Palette.base : ZenithDesign.Palette.muted)
                        .background(canSend ? ZenithDesign.Palette.brand : ZenithDesign.Palette.baseRaised)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSend)
                .accessibilityLabel(isSending ? "Sending message" : "Send message")
                .accessibilityIdentifier("matrix.thread.send")
            }

            composerStatus
        }
        .padding(.leading, ZenithDesign.Space.x5)
        .padding(.trailing, ZenithDesign.Space.x3)
        .padding(.vertical, ZenithDesign.Space.x2)
        .frame(minHeight: 64)
        .background(.ultraThinMaterial)
        .background(ZenithDesign.Palette.glass)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(
                    isFocused ? ZenithDesign.Palette.brand : ZenithDesign.Palette.glassBorder,
                    lineWidth: isFocused ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .padding(.horizontal, ZenithDesign.Space.x6)
        .padding(.vertical, ZenithDesign.Space.x4)
        .background(ZenithDesign.Palette.base)
        .onChange(of: statusAnnouncement) { _, announcement in
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private var statusAnnouncement: String? {
        if isSending {
            return "Sending message."
        }
        if let failureReason {
            return "Message failed to send. \(failureReason) Draft preserved; press Send to retry."
        }
        if let disabledReason {
            return "Message composer unavailable. \(disabledReason)"
        }
        return nil
    }

    @ViewBuilder
    private var composerStatus: some View {
        if isSending {
            HStack(spacing: ZenithDesign.Space.x2) {
                ProgressView().controlSize(.small)
                Text("Sending…")
            }
            .font(ZenithDesign.Typography.technical(.caption, weight: .semibold))
            .foregroundStyle(ZenithDesign.Palette.muted)
            .accessibilityIdentifier("matrix.thread.sending")
        } else if let failureReason {
            Label(failureReason, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(ZenithDesign.Typography.technical(.caption, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.error)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHint("Review the preserved draft and press Send to retry.")
                .accessibilityIdentifier("matrix.thread.send-failure")
        } else if let disabledReason {
            Label(disabledReason, systemImage: "lock.fill")
                .font(ZenithDesign.Typography.technical(.caption, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("matrix.thread.composer-disabled")
        }
    }

    private func submitIfReady() {
        guard canSend else { return }
        send()
    }
}

private struct MatrixMandatoryPasswordResetSheet: View {
    @ObservedObject var model: MatrixAppModel

    var body: some View {
        MatrixChangePasswordSheet(
            model: model,
            isPresented: .constant(true),
            requiresCompletion: true
        )
        .interactiveDismissDisabled(true)
    }
}

private struct MatrixChangePasswordSheet: View {
    private enum CredentialResult: Equatable {
        case noneStored
        case updated
        case applePasswordsUpdated
        case allUpdated
        case updateFailed
    }

    private enum SubmissionState: Equatable {
        case idle
        case submitting
        case succeeded(CredentialResult)
        case failed(String)
    }

    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    let requiresCompletion: Bool
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var logoutOtherDevices = false
    @State private var saveInApplePasswords = false
    @State private var submissionState: SubmissionState = .idle

    private var isSubmitting: Bool { submissionState == .submitting }
    private var passwordsMatch: Bool { !confirmation.isEmpty && newPassword == confirmation }
    private var canSubmit: Bool {
        !currentPassword.isEmpty
            && !newPassword.isEmpty
            && passwordsMatch
            && newPassword != currentPassword
            && !isSubmitting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
            Text(requiresCompletion ? "Replace temporary password" : "Change password")
                .font(ZenithDesign.Typography.corporate(.title2, weight: .semibold))

            switch submissionState {
            case let .succeeded(credentialResult):
                Label("Password changed", systemImage: "checkmark.circle.fill")
                    .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.success)
                Text(successMessage(for: credentialResult))
                .font(ZenithDesign.Typography.corporate(.callout))
                .foregroundStyle(
                    credentialResult == .updateFailed
                        ? ZenithDesign.Palette.warning
                        : ZenithDesign.Palette.muted
                )
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Done") { isPresented = false }
                        .buttonStyle(HyphaButtonStyle(.primary))
                        .keyboardShortcut(.defaultAction)
                }

            case .idle, .submitting, .failed:
                Text(requiresCompletion
                     ? "This is the first password login for this account on Hypha. Replace the temporary password before entering chat."
                     : "Use the current account password to authorize this change. Hypha never logs or displays either password.")
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                HyphaRevealablePasswordField(
                    title: "Current password",
                    text: $currentPassword,
                    accessibilityIdentifier: "matrix.password.current"
                )
                .disabled(isSubmitting)
                HyphaRevealablePasswordField(
                    title: "New password",
                    text: $newPassword,
                    accessibilityIdentifier: "matrix.password.new",
                    isNewPassword: true
                )
                .disabled(isSubmitting)
                HyphaRevealablePasswordField(
                    title: "Confirm new password",
                    text: $confirmation,
                    accessibilityIdentifier: "matrix.password.confirmation",
                    isNewPassword: true
                )
                .disabled(isSubmitting)

                if !confirmation.isEmpty {
                    Label(
                        passwordsMatch ? "Passwords match" : "Passwords do not match",
                        systemImage: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(ZenithDesign.Typography.corporate(.caption, weight: .medium))
                    .foregroundStyle(passwordsMatch ? ZenithDesign.Palette.success : ZenithDesign.Palette.error)
                    .accessibilityIdentifier("matrix.password.match")
                }
                if !newPassword.isEmpty && newPassword == currentPassword {
                    Text("Choose a password different from the current password.")
                        .font(ZenithDesign.Typography.corporate(.caption))
                        .foregroundStyle(ZenithDesign.Palette.error)
                }

                if requiresCompletion {
                    Label("Other devices will be signed out after the temporary password is replaced.", systemImage: "rectangle.stack.badge.minus")
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                } else {
                    Toggle("Sign out other Hypha devices after changing the password", isOn: $logoutOtherDevices)
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .disabled(isSubmitting)
                }

                if model.applePasswordsAvailable {
                    Toggle("Update in Apple Passwords", isOn: $saveInApplePasswords)
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("matrix.password.save-apple-passwords")
                }

                if case let .failed(message) = submissionState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .foregroundStyle(ZenithDesign.Palette.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }

                HStack {
                    if !requiresCompletion {
                        Button("Cancel") {
                            clearSecrets()
                            isPresented = false
                        }
                        .buttonStyle(HyphaButtonStyle(.secondary))
                        .disabled(isSubmitting)
                    }

                    Spacer()

                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            HStack(spacing: ZenithDesign.Space.x2) {
                                ProgressView().controlSize(.small)
                                Text("Changing…")
                            }
                        } else {
                            Text("Change Password")
                        }
                    }
                    .buttonStyle(HyphaButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("matrix.password.submit")
                }
            }
        }
        .padding(ZenithDesign.Space.x6)
        .frame(width: 500)
        .interactiveDismissDisabled(requiresCompletion || isSubmitting)
        .onDisappear { clearSecrets() }
    }

    private func submit() {
        guard canSubmit else { return }
        let request = (
            currentPassword: currentPassword,
            newPassword: newPassword,
            logoutOtherDevices: requiresCompletion ? true : logoutOtherDevices,
            saveInApplePasswords: saveInApplePasswords
        )
        clearSecrets()
        submissionState = .submitting
        Task {
            let outcome = await model.changePassword(
                currentPassword: request.currentPassword,
                newPassword: request.newPassword,
                logoutOtherDevices: request.logoutOtherDevices,
                saveInApplePasswords: request.saveInApplePasswords
            )
            switch outcome {
            case .success:
                submissionState = .succeeded(.noneStored)
            case .successWithCredentialUpdate:
                submissionState = .succeeded(.updated)
            case .successWithApplePasswordsUpdate:
                submissionState = .succeeded(.applePasswordsUpdated)
            case .successWithCredentialUpdates:
                submissionState = .succeeded(.allUpdated)
            case .successWithCredentialWarning:
                submissionState = .succeeded(.updateFailed)
            case .invalidCurrentPassword:
                submissionState = .failed("The current password was not accepted. Re-enter all password fields and try again.")
            case let .failed(message):
                submissionState = .failed(message)
            }
        }
    }

    private func clearSecrets() {
        currentPassword = ""
        newPassword = ""
        confirmation = ""
        saveInApplePasswords = false
    }

    private func successMessage(for result: CredentialResult) -> String {
        switch result {
        case .noneStored:
            return "The homeserver accepted the new password. No saved sign-in credential was changed."
        case .updated:
            return "Hypha updated the saved account password in encrypted local storage."
        case .applePasswordsUpdated:
            return "Apple Passwords saved the new password for this homeserver and can sync it through iCloud Keychain."
        case .allUpdated:
            return "Hypha updated the existing local credential and Apple Passwords saved the new password for iCloud Keychain sync."
        case .updateFailed:
            return "The homeserver accepted the new password, but a selected password store was not updated. Enter the new password the next time you sign in."
        }
    }
}

private struct MatrixFirstDevicePasswordSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @State private var firstDevicePassword = ""
    @State private var isSubmitting = false
    @State private var attempted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authorize device security")
                .font(ZenithDesign.Typography.technical(size: 22, weight: .semibold))
            Text("Enter the account password to let the homeserver authorize this device. Hypha uses it only for this authorization request.")
                .foregroundStyle(ZenithDesign.Palette.muted)
            SecureField("Account password", text: $firstDevicePassword)
                .textContentType(.password)
                .textFieldStyle(ZenithInputStyle())
                .accessibilityIdentifier("matrix.first-device.password")
            if attempted && model.firstDeviceTrustBootstrapState == .passwordRequired {
                Text("Authorization did not complete. Check the password and try again.")
                    .font(.caption)
                    .foregroundStyle(ZenithDesign.Palette.error)
            }
            HStack {
                Button("Cancel") {
                    firstDevicePassword = ""
                    isPresented = false
                }
                Spacer()
                Button(isSubmitting ? "Authorizing…" : "Continue") { submit() }
                    .buttonStyle(ZenithPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(firstDevicePassword.isEmpty || isSubmitting)
                    .accessibilityIdentifier("matrix.first-device.continue")
            }
        }
        .padding(24)
        .frame(width: 430)
        .onDisappear { firstDevicePassword = "" }
    }

    private func submit() {
        guard !firstDevicePassword.isEmpty, !isSubmitting else { return }
        let passwordForRequest = firstDevicePassword
        firstDevicePassword = ""
        isSubmitting = true
        Task {
            await model.continueFirstDeviceTrust(password: passwordForRequest)
            if model.firstDeviceTrustBootstrapState == .verifiedByCurrentSelfSigningKey {
                isPresented = false
            } else {
                attempted = true
                isSubmitting = false
            }
        }
    }
}

private struct MatrixRecoverySetupSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @State private var generatedRecoveryKey: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let generatedRecoveryKey {
                Text("Save your recovery key")
                    .font(ZenithDesign.Typography.technical(size: 22, weight: .semibold))
                Text("This key is shown once. Store it in a password manager before continuing. Hypha does not save it and cannot recover it for you.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Text(generatedRecoveryKey)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .privacySensitive()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("matrix.recovery.generated-key")
                HStack {
                    Spacer()
                    Button("I've saved this key") {
                        self.generatedRecoveryKey = nil
                        isPresented = false
                    }
                    .buttonStyle(ZenithPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Set up encryption recovery")
                    .font(ZenithDesign.Typography.technical(size: 22, weight: .semibold))
                Text("Hypha will create account cross-signing recovery and Secure Backup, wait for existing room keys to upload, then show one recovery key. Do not continue unless you can store it safely.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
                if case let .failed(reason) = model.recoveryState {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ZenithDesign.Palette.error)
                }
                HStack {
                    Button("Cancel") { isPresented = false }
                        .disabled(isSubmitting)
                    Spacer()
                    Button {
                        setUpRecovery()
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Create recovery key")
                        }
                    }
                    .buttonStyle(ZenithPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("matrix.recovery.setup")
                }
            }
        }
        .padding(24)
        .frame(width: 560)
        .interactiveDismissDisabled(generatedRecoveryKey != nil)
        .onDisappear { generatedRecoveryKey = nil }
    }

    private func setUpRecovery() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            generatedRecoveryKey = await model.setupEncryptionRecovery()
            isSubmitting = false
        }
    }
}

private struct MatrixRecoverySheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @State private var recoveryKey = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore encryption")
                .font(ZenithDesign.Typography.technical(size: 22, weight: .semibold))
            Text("Enter the recovery key created by Matrix Secure Backup. It is used only for this recovery request and is not saved by Hypha.")
                .foregroundStyle(ZenithDesign.Palette.muted)
            recoveryErrorPresentation
            SecureField("Recovery key", text: $recoveryKey)
                .textFieldStyle(ZenithInputStyle())
                .accessibilityIdentifier("matrix.recovery.key")
                .onSubmit { submit() }
            HStack {
                Button("Cancel") {
                    recoveryKey = ""
                    isPresented = false
                }
                Spacer()
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Restore")
                    }
                }
                .buttonStyle(ZenithPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("matrix.recovery.restore")
            }
        }
        .padding(24)
        .frame(width: 500)
        .onDisappear { recoveryKey = "" }
    }

    @ViewBuilder
    private var recoveryErrorPresentation: some View {
        switch model.recoveryState {
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(ZenithDesign.Palette.error)
        case let .diagnostic(receipt):
            Label("Recovery diagnostic \(receipt.stableCode)", systemImage: "stethoscope")
                .foregroundStyle(ZenithDesign.Palette.error)
        default:
            EmptyView()
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        let keyForRequest = recoveryKey
        recoveryKey = ""
        isSubmitting = true
        Task {
            await model.restoreEncryption(recoveryKey: keyForRequest)
            isSubmitting = false
            if model.recoveryState == .ready { isPresented = false }
        }
    }
}

private struct MatrixRoomInviteSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @State private var selectedRoomID = ""
    @State private var invitees = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showsInviteConfirmation = false
    @State private var pendingRoomID = ""
    @State private var pendingUserIDs: [String] = []
    @State private var lookupResults: [MatrixUserLookupResult] = []

    private var eligibleRooms: [MatrixRoomSummary] {
        MatrixRoomInvitationPolicy.eligibleRooms(from: model.rooms)
    }

    private var allValidatedUsersExist: Bool {
        !lookupResults.isEmpty && lookupResults.allSatisfy {
            if case .exists = $0 { return true }
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                Text("Invite members")
                    .font(ZenithDesign.Typography.corporate(.title2, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.content)
                Text("Enter complete usernames. Hypha checks only those exact accounts—there is no directory search.")
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }

            if eligibleRooms.isEmpty {
                HyphaStatusMessage(
                    message: "No joined rooms currently allow this account to invite members.",
                    tone: .warning
                )
            } else {
                Picker("Room", selection: $selectedRoomID) {
                    ForEach(eligibleRooms) { room in
                        Text(room.name).tag(room.id)
                    }
                }
                .accessibilityIdentifier("matrix.room.invite.destination")

                TextField("Username or complete Matrix ID", text: $invitees)
                    .textFieldStyle(HyphaTextFieldStyle())
                    .accessibilityIdentifier("matrix.room.invite.userIDs")

                Text("Permission is checked again immediately before an invitation is sent.")
                    .font(ZenithDesign.Typography.corporate(.caption))
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }

            if !lookupResults.isEmpty {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                    ForEach(Array(lookupResults.enumerated()), id: \.offset) { _, result in
                        lookupResultRow(result)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Invitation recipient validation")
            }

            if let statusMessage {
                HyphaStatusMessage(message: statusMessage, tone: .success)
            }
            if let errorMessage {
                HyphaStatusMessage(message: errorMessage, tone: .warning)
            }

            HStack(spacing: ZenithDesign.Space.x2) {
                HyphaButton(title: "Cancel", variant: .secondary) {
                    isPresented = false
                }
                Spacer()
                HyphaButton(
                    title: submitButtonTitle,
                    systemImage: "person.badge.plus",
                    variant: .primary
                ) {
                    if allValidatedUsersExist {
                        prepareConfirmation()
                    } else {
                        validateRecipients()
                    }
                }
                .disabled(
                    isSubmitting
                        || selectedRoomID.isEmpty
                        || invitees.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("matrix.room.invite.submit")
            }
        }
        .padding(ZenithDesign.Space.x5)
        .frame(width: 560)
        .background(ZenithDesign.Palette.base)
        .onAppear { selectFirstEligibleRoomIfNeeded() }
        .onChange(of: model.rooms) { _, _ in
            selectFirstEligibleRoomIfNeeded()
            clearValidation()
        }
        .onChange(of: selectedRoomID) { _, _ in clearValidation() }
        .onChange(of: invitees) { _, _ in clearValidation() }
        .confirmationDialog(
            "Confirm invitations",
            isPresented: $showsInviteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Send \(pendingUserIDs.count == 1 ? "invitation" : "invitations")") {
                submitConfirmedInvitations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let roomName = eligibleRooms.first(where: { $0.id == pendingRoomID })?.name ?? "the selected room"
            Text("Invite \(pendingUserIDs.joined(separator: ", ")) to \(roomName)?")
        }
    }

    private var submitButtonTitle: String {
        if isSubmitting { return lookupResults.isEmpty ? "Checking…" : "Inviting…" }
        return allValidatedUsersExist ? "Review invitations" : "Check recipients"
    }

    @ViewBuilder
    private func lookupResultRow(_ result: MatrixUserLookupResult) -> some View {
        switch result {
        case let .exists(userID, displayName):
            HyphaStatusMessage(
                message: "User found: \(displayName ?? userID) (\(userID))",
                tone: .success
            )
        case let .notFound(userID, inviteLink):
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                HyphaStatusMessage(
                    message: "No Matrix account exists for \(userID).",
                    tone: .warning
                )
                Text("Share the room link for context. It does not bypass invite-only membership; invite them again after they create an account.")
                    .font(ZenithDesign.Typography.corporate(.caption))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                HyphaButton(title: "Copy invite link", systemImage: "doc.on.doc", variant: .secondary) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(inviteLink, forType: .string)
                    statusMessage = "Invite link copied."
                }
                .accessibilityHint("Copies the selected room's Matrix link")
            }
        case .unavailable:
            HyphaStatusMessage(
                message: "Hypha could not validate this exact account. Nothing was invited.",
                tone: .warning
            )
        }
    }

    private func selectFirstEligibleRoomIfNeeded() {
        guard !eligibleRooms.contains(where: { $0.id == selectedRoomID }) else { return }
        selectedRoomID = eligibleRooms.first?.id ?? ""
    }

    private func clearValidation() {
        lookupResults = []
        pendingRoomID = ""
        pendingUserIDs = []
        errorMessage = nil
        statusMessage = nil
    }

    private func validateRecipients() {
        guard !isSubmitting,
              let room = eligibleRooms.first(where: { $0.id == selectedRoomID }) else { return }
        guard let resolvedUserIDs = model.resolvedInviteUserIDs(invitees) else {
            errorMessage = "Enter a local username or a complete Matrix ID such as @name:server."
            return
        }
        isSubmitting = true
        errorMessage = nil
        statusMessage = nil
        Task {
            let results = await model.lookupInviteUsers(resolvedUserIDs, for: room)
            lookupResults = results
            pendingRoomID = room.id
            pendingUserIDs = results.allSatisfy {
                if case .exists = $0 { return true }
                return false
            } ? resolvedUserIDs : []
            if results.contains(.unavailable) {
                errorMessage = "Recipient validation is unavailable. No invitation was sent."
            }
            isSubmitting = false
        }
    }

    private func prepareConfirmation() {
        guard allValidatedUsersExist,
              !pendingUserIDs.isEmpty,
              eligibleRooms.contains(where: { $0.id == pendingRoomID }) else {
            clearValidation()
            errorMessage = "Validate the recipients again before inviting them."
            return
        }
        showsInviteConfirmation = true
    }

    private func submitConfirmedInvitations() {
        guard !isSubmitting,
              !pendingUserIDs.isEmpty,
              let room = eligibleRooms.first(where: { $0.id == pendingRoomID }) else {
            errorMessage = "The selected room is no longer eligible for invitations."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let userIDs = pendingUserIDs
        Task {
            if await model.inviteUsers(userIDs, to: room) {
                isPresented = false
            } else {
                clearValidation()
                errorMessage = "Not all invitations could be confirmed. Refresh room membership and your invite permission."
            }
            isSubmitting = false
        }
    }
}

private struct MatrixNewRoomSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @Binding var kind: MatrixRoomKind
    @State private var visibility: MatrixRoomVisibility = .inviteOnly
    @State private var name = ""
    @State private var topic = ""
    @State private var invitees = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                Text(kind == .space ? "Create a Space" : "Create a room")
                    .font(ZenithDesign.Typography.corporate(.title2, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.content)
                Text(kind == .space
                     ? "Spaces organize related rooms and subspaces."
                     : "Rooms are end-to-end encrypted conversation surfaces.")
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }

            Picker("Type", selection: $kind) {
                Label("Room", systemImage: "message.fill").tag(MatrixRoomKind.room)
                Label("Space", systemImage: "square.grid.2x2.fill").tag(MatrixRoomKind.space)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("matrix.room.kind")

            TextField(kind == .space ? "Space name" : "Room name", text: $name)
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.room.name")
            TextField("Topic (optional)", text: $topic)
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.room.topic")
            TextField("Invite Matrix IDs, separated by commas", text: $invitees)
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.room.invitees")

            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("ACCESS")
                    .font(ZenithDesign.Typography.technical(size: 11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Picker("Access", selection: $visibility) {
                    Label("Invite only", systemImage: "person.badge.key.fill")
                        .tag(MatrixRoomVisibility.inviteOnly)
                    Label("Public", systemImage: "globe")
                        .tag(MatrixRoomVisibility.public)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("matrix.room.visibility")
                Text(accessDescription)
                    .font(ZenithDesign.Typography.corporate(.caption))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenithDesign.Space.x3)
            .background(ZenithDesign.Palette.baseRaised)
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))

            HStack(spacing: ZenithDesign.Space.x2) {
                HyphaButton(title: "Cancel", variant: .secondary) {
                    isPresented = false
                }
                Spacer()
                HyphaButton(
                    title: isSubmitting ? "Creating…" : (kind == .space ? "Create Space" : "Create encrypted room"),
                    systemImage: kind == .space ? "square.grid.2x2.fill" : "lock.fill",
                    variant: .primary
                ) {
                    submit()
                }
                .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("matrix.room.create")
            }
        }
        .padding(ZenithDesign.Space.x5)
        .frame(width: 560)
        .background(ZenithDesign.Palette.base)
    }

    private var accessDescription: String {
        switch (kind, visibility) {
        case (.room, .inviteOnly):
            "Only invited members can join. Messages remain end-to-end encrypted."
        case (.room, .public):
            "The room is published and anyone can join. Messages remain end-to-end encrypted."
        case (.space, .inviteOnly):
            "Only invited members can join this Space and browse its published hierarchy."
        case (.space, .public):
            "The Space is published and anyone can join and browse its published hierarchy."
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            await model.createRoomOrSpace(
                name: name,
                topic: topic,
                invitees: invitees,
                kind: kind,
                visibility: visibility
            )
            isSubmitting = false
            if case .thread = model.state { isPresented = false }
        }
    }
}
