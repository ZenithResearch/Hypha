import Accessibility
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
            credentialStore: credentialStore
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
    case successWithCredentialWarning
    case invalidCurrentPassword
    case failed(String)
}

@MainActor
final class MatrixAppModel: ObservableObject {
    typealias ServiceFactory = (MatrixProductConfiguration) -> any MatrixChatService

    @Published var state: MatrixChatState = .signedOut(message: nil)
    @Published var homeserverInput = ""
    @Published var homeserverState: HomeserverOnboardingState = .awaitingInput
    @Published var username = ""
    @Published var password = ""
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
    @Published var savedSessions: [MatrixSDKSessionRecord] = []
    @Published var savedCredentials: [HyphaMatrixCredentialDescriptor] = []
    @Published var activeSessionAccountKey: String?
    @Published private(set) var isAuthenticationOperationInFlight = false

    private static let homeserverDefaultsKey = "ca.zenithresearch.macos.client.matrix.homeserver"
    private static let legacyHomeserverDefaultsKey = [
        "ca", "zenith-research", "mobile-macos", "matrix", "homeserver",
    ].joined(separator: ".")
    private static let legacyDefaultsSuite = ["ca", "zenithresearch", "mobile", "macos"].joined(separator: ".")
    private let defaults = UserDefaults.standard
    private let legacyDefaults = UserDefaults(suiteName: MatrixAppModel.legacyDefaultsSuite)
    private let healthChecker: MatrixHomeserverHealthChecker
    private let sessionVault: MatrixEncryptedSessionVault
    private let credentialStore: any HyphaMatrixCredentialStore
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
        serviceFactory: @escaping ServiceFactory
    ) {
        self.healthChecker = healthChecker
        self.sessionVault = sessionVault
        self.credentialStore = credentialStore
        self.serviceFactory = serviceFactory
    }

    var connectedHomeserver: URL? {
        guard case let .connected(url) = homeserverState else { return nil }
        return url
    }

    var isCheckingHomeserver: Bool { homeserverState == .checking }

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
        username = ""
        password = ""
        state = .signedOut(message: nil)
        resetSecurityState()
        homeserverState = .awaitingInput
    }

    func createAccount(username: String, password: String, registrationToken: String) async -> Bool {
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
            if let configuration = activeConfiguration {
                refreshSavedSessions(configuration: configuration)
                if case .rooms = state {
                    do {
                        try credentialStore.savePassword(
                            password,
                            username: username,
                            homeserver: configuration.homeserver
                        )
                        refreshSavedCredentials(configuration: configuration)
                    } catch {
                        roomSyncMessage = "Account created, but Hypha could not save this password."
                    }
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
        let passwordForRequest = password
        password = ""
        await coordinator.signIn(username: username, password: passwordForRequest)
        applyState(from: coordinator)
        applySecurityState(from: coordinator)
        if let configuration = activeConfiguration {
            refreshSavedSessions(configuration: configuration)
            if case .rooms = state {
                do {
                    let credential = try credentialStore.savePassword(
                        passwordForRequest,
                        username: username,
                        homeserver: configuration.homeserver
                    )
                    try credentialStore.finalizeAuthenticatedMigration(credential)
                    refreshSavedCredentials(configuration: configuration)
                } catch {
                    roomSyncMessage = "Signed in, but Hypha could not save this password."
                }
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
            refreshSavedSessions(configuration: configuration)
            if case .rooms = state {
                do {
                    try credentialStore.finalizeAuthenticatedMigration(credential)
                } catch {
                    roomSyncMessage = "Signed in, but Hypha could not finish credential migration."
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
            refreshSavedSessions(configuration: configuration)
        } catch {
            state = .unavailable(reason: "Saved Matrix session could not be opened")
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
        rooms = []
        resetSecurityState()
        state = .signedOut(message: nil)
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
            return true
        } catch {
            savedSessions = []
            activeSessionAccountKey = nil
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
        }
    }

    func retrySignIn(
        username: String? = nil,
        message: MatrixSignOutMessage? = nil
    ) {
        password = ""
        if let username { self.username = username }
        if let configuration = activeConfiguration {
            coordinator = MatrixChatCoordinator(service: serviceFactory(configuration))
        }
        state = .signedOut(message: message)
        resetSecurityState()
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
        logoutOtherDevices: Bool
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
            guard let accountKey = activeSessionAccountKey,
                  let existingCredential = savedCredentials.first(where: { $0.id == accountKey }),
                  let configuration = activeConfiguration else {
                return .success
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
                return .successWithCredentialUpdate
            } catch {
                return .successWithCredentialWarning
            }
        case .invalidCurrentPassword:
            return .invalidCurrentPassword
        case let .failed(message):
            return .failed(message)
        }
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

    func createEncryptedRoom(name: String, topic: String, invitees: String) async {
        guard let coordinator else { return }
        let parsedInvitees = invitees
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let request = MatrixRoomCreationRequest(name: name, topic: topic, invitees: parsedInvitees)
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
            return
        }
        let removed = await coordinator.removeRoom(room)
        applyState(from: coordinator)
        if removed {
            timelineRefreshTask?.cancel()
            rooms.removeAll { $0.id == room.id }
            roomSyncMessage = "Room left and forgotten for this account."
        } else {
            roomSyncMessage = "Room could not be removed. It remains available to this account."
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
    @State private var showsRecovery = false
    @State private var showsRecoverySetup = false
    @State private var showsNewRoom = false
    @State private var showsFirstDevicePassword = false
    @State private var showsSecurityCenter = false
    @State private var showsPasswordChange = false
    @State private var roomPendingRemoval: MatrixRoomSummary?
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
            MatrixNewRoomSheet(model: model, isPresented: $showsNewRoom)
        }
        .sheet(isPresented: $showsFirstDevicePassword) {
            MatrixFirstDevicePasswordSheet(model: model, isPresented: $showsFirstDevicePassword)
        }
        .sheet(isPresented: $showsPasswordChange) {
            MatrixChangePasswordSheet(model: model, isPresented: $showsPasswordChange)
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
            ToolbarItem(placement: .primaryAction) {
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

    private func roomList(_ rooms: [MatrixRoomSummary]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                if !model.savedSessions.isEmpty || !model.savedCredentials.isEmpty {
                    accountSwitcher
                }

                HStack(spacing: ZenithDesign.Space.x2) {
                    Button {
                        showsNewRoom = true
                    } label: {
                        Label("New encrypted room", systemImage: "plus.message.fill")
                            .font(ZenithDesign.Typography.corporate(.callout, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("matrix.room.create")

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
                        .foregroundStyle(ZenithDesign.Palette.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let invitations = rooms.filter(\.hasInvite)
                if !invitations.isEmpty {
                    sidebarSectionTitle("Invites")
                    ForEach(invitations) { room in
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
                    }
                }

                sidebarSectionTitle("Rooms")
                    .padding(.top, invitations.isEmpty ? 0 : ZenithDesign.Space.x2)

                let joinedRooms = rooms.filter { !$0.hasInvite }
                if joinedRooms.isEmpty {
                    Text("No joined rooms yet.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .padding(.horizontal, ZenithDesign.Space.x2)
                } else {
                    ForEach(joinedRooms) { room in
                        roomRow(room)
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
            "Delete room from this account?",
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
                    Image(systemName: room.isEncrypted ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            room.isEncrypted
                                ? ZenithDesign.Palette.brand
                                : ZenithDesign.Palette.warning
                        )
                    Text(room.name)
                        .font(ZenithDesign.Typography.corporate(.callout, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(ZenithDesign.Palette.content)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(room.name)")
            .accessibilityHint(room.isEncrypted ? "Encrypted room" : "Unencrypted room")
            .accessibilityIdentifier("matrix.room.row")

            if room.isCreatedByCurrentUser {
                Menu {
                    Button("Delete room from this account…", role: .destructive) {
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
            thread(room: room, events: events, composerState: composer)
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

private struct MatrixChangePasswordSheet: View {
    private enum CredentialResult: Equatable {
        case noneStored
        case updated
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
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var logoutOtherDevices = false
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
            Text("Change password")
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
                Text("Use the current account password to authorize this change. Hypha never logs or displays either password.")
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Current password", text: $currentPassword)
                    .textFieldStyle(ZenithInputStyle())
                    .privacySensitive()
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("matrix.password.current")
                SecureField("New password", text: $newPassword)
                    .textFieldStyle(ZenithInputStyle())
                    .privacySensitive()
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("matrix.password.new")
                SecureField("Confirm new password", text: $confirmation)
                    .textFieldStyle(ZenithInputStyle())
                    .privacySensitive()
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("matrix.password.confirmation")

                if !confirmation.isEmpty && !passwordsMatch {
                    Text("The new passwords do not match.")
                        .font(ZenithDesign.Typography.corporate(.caption))
                        .foregroundStyle(ZenithDesign.Palette.error)
                } else if !newPassword.isEmpty && newPassword == currentPassword {
                    Text("Choose a password different from the current password.")
                        .font(ZenithDesign.Typography.corporate(.caption))
                        .foregroundStyle(ZenithDesign.Palette.error)
                }

                Toggle("Sign out other Hypha devices after changing the password", isOn: $logoutOtherDevices)
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .disabled(isSubmitting)

                if case let .failed(message) = submissionState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(ZenithDesign.Typography.corporate(.callout))
                        .foregroundStyle(ZenithDesign.Palette.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }

                HStack {
                    Button("Cancel") {
                        clearSecrets()
                        isPresented = false
                    }
                    .buttonStyle(HyphaButtonStyle(.secondary))
                    .disabled(isSubmitting)

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
        .interactiveDismissDisabled(isSubmitting)
        .onDisappear { clearSecrets() }
    }

    private func submit() {
        guard canSubmit else { return }
        let request = (
            currentPassword: currentPassword,
            newPassword: newPassword,
            logoutOtherDevices: logoutOtherDevices
        )
        clearSecrets()
        submissionState = .submitting
        Task {
            let outcome = await model.changePassword(
                currentPassword: request.currentPassword,
                newPassword: request.newPassword,
                logoutOtherDevices: request.logoutOtherDevices
            )
            switch outcome {
            case .success:
                submissionState = .succeeded(.noneStored)
            case .successWithCredentialUpdate:
                submissionState = .succeeded(.updated)
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
    }

    private func successMessage(for result: CredentialResult) -> String {
        switch result {
        case .noneStored:
            return "The homeserver accepted the new password. No saved sign-in credential was changed."
        case .updated:
            return "Hypha updated the saved account password in encrypted local storage."
        case .updateFailed:
            return "The homeserver accepted the new password, but Hypha could not update the saved local credential. Enter the new password the next time you sign in."
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
            Text("Enter the account password to let the homeserver authorize this device. Hypha keeps the saved account password in macOS Keychain.")
                .foregroundStyle(ZenithDesign.Palette.muted)
            SecureField("Account password", text: $firstDevicePassword)
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

private struct MatrixNewRoomSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var topic = ""
    @State private var invitees = ""
    @State private var isSubmitting = false

    var body: some View {
        Form {
            Section {
                TextField("Room name", text: $name)
                    .accessibilityIdentifier("matrix.room.name")
                TextField("Topic (optional)", text: $topic)
                    .accessibilityIdentifier("matrix.room.topic")
                TextField("Invite Matrix IDs, separated by commas", text: $invitees)
                    .accessibilityIdentifier("matrix.room.invitees")
            }
            Section {
                Label("Encrypted and invite-only", systemImage: "lock.fill")
                Text("Hypha waits for the production homeserver to confirm the room before opening it.")
                    .font(.caption)
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create room")
                    }
                }
                .buttonStyle(ZenithPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("matrix.room.create")
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 520, height: 390)
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            await model.createEncryptedRoom(name: name, topic: topic, invitees: invitees)
            isSubmitting = false
            if case .thread = model.state { isPresented = false }
        }
    }
}
