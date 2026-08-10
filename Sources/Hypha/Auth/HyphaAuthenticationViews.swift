import SwiftUI
import HyphaCore

struct HyphaAuthLandingView: View {
    @ObservedObject var model: MatrixAppModel
    let hasSavedAccounts: Bool
    let openSavedAccounts: () -> Void
    let openPasswordSignIn: () -> Void
    let openRegistration: () -> Void

    var body: some View {
        HyphaAuthShell(
            title: "Welcome to Hypha",
            message: "Choose one secure path. Each sign-in and account-creation flow stays in its own view.",
            symbol: "leaf.fill"
        ) {
            VStack(spacing: ZenithDesign.Space.x3) {
                if hasSavedAccounts {
                    HyphaButton(
                        title: "Continue with a saved account",
                        systemImage: "person.crop.circle.badge.checkmark",
                        variant: .primary,
                        fillsWidth: true,
                        action: openSavedAccounts
                    )
                    .disabled(model.isAuthenticationOperationInFlight)
                    .accessibilityIdentifier("matrix.auth.saved-accounts")
                }

                HyphaButton(
                    title: "Sign in with password",
                    systemImage: "key.fill",
                    variant: hasSavedAccounts ? .secondary : .primary,
                    fillsWidth: true,
                    action: openPasswordSignIn
                )
                .disabled(model.isAuthenticationOperationInFlight)
                .accessibilityIdentifier("matrix.auth.password")

                if model.registrationAvailability == .inviteToken {
                    HyphaButton(
                        title: "Create account with invite token",
                        systemImage: "person.badge.plus",
                        variant: .quiet,
                        fillsWidth: true,
                        action: openRegistration
                    )
                    .disabled(model.isAuthenticationOperationInFlight)
                    .accessibilityIdentifier("matrix.registration.open")
                }
            }
            .frame(maxWidth: 420)
        }
    }
}

struct HyphaSavedAccountsView: View {
    @ObservedObject var model: MatrixAppModel
    let choices: [HyphaLoginAccountChoice]
    let back: () -> Void
    let continueSession: (MatrixSDKSessionRecord) async -> Void
    let signInWithSavedPassword: (HyphaMatrixCredentialDescriptor) async -> Void
    let deleteLocalSession: (MatrixSDKSessionRecord) async -> Void
    let deleteSavedPassword: (HyphaMatrixCredentialDescriptor) async -> Void
    let usePassword: () -> Void

    @State private var pendingAccountChoiceID: String?
    @State private var sessionPendingDeletion: MatrixSDKSessionRecord?
    @State private var credentialPendingDeletion: HyphaMatrixCredentialDescriptor?

    var body: some View {
        HyphaAuthShell(
            title: "Choose a saved account",
            message: "Resume the existing encrypted device session or reauthenticate the same device with its saved password.",
            symbol: "person.2.fill",
            back: back,
            isBackDisabled: model.isAuthenticationOperationInFlight || pendingAccountChoiceID != nil
        ) {
            LazyVStack(spacing: ZenithDesign.Space.x3) {
                ForEach(choices) { choice in
                    HyphaAccountChoiceCard(
                        choice: choice,
                        isPending: pendingAccountChoiceID == choice.id,
                        isInteractionDisabled: model.isAuthenticationOperationInFlight || pendingAccountChoiceID != nil,
                        continueSession: { session in
                            performAccountAction(choiceID: choice.id) {
                                await continueSession(session)
                            }
                        },
                        signInWithSavedPassword: { credential in
                            performAccountAction(choiceID: choice.id) {
                                await signInWithSavedPassword(credential)
                            }
                        },
                        deleteLocalSession: { session in
                            sessionPendingDeletion = session
                        },
                        deleteSavedPassword: { credential in
                            credentialPendingDeletion = credential
                        }
                    )
                }

                HyphaButton(
                    title: "Use a different account password",
                    systemImage: "person.badge.plus",
                    variant: .quiet,
                    action: usePassword
                )
                .disabled(model.isAuthenticationOperationInFlight || pendingAccountChoiceID != nil)
            }
            .frame(maxWidth: 560)
        }
        .confirmationDialog(
            "Delete this local session?",
            isPresented: Binding(
                get: { sessionPendingDeletion != nil },
                set: { if !$0 { sessionPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: sessionPendingDeletion
        ) { session in
            Button("Delete local session", role: .destructive) {
                sessionPendingDeletion = nil
                performAccountAction(choiceID: session.accountKey) {
                    await deleteLocalSession(session)
                }
            }
            Button("Cancel", role: .cancel) { sessionPendingDeletion = nil }
        } message: { session in
            Text("This removes the access-token session for \(session.userId) from \(HyphaPlatform.localDevicePhrase). It does not delete the account, encryption store, or saved password.")
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
                performAccountAction(choiceID: credential.id) {
                    await deleteSavedPassword(credential)
                }
            }
            Button("Cancel", role: .cancel) { credentialPendingDeletion = nil }
        } message: { credential in
            Text("This removes the saved password for \(credential.username) from Hypha on \(HyphaPlatform.localDevicePhrase). It does not delete the Matrix account or encrypted session.")
        }
    }

    private func performAccountAction(
        choiceID: String,
        action: @escaping () async -> Void
    ) {
        guard pendingAccountChoiceID == nil,
              !model.isAuthenticationOperationInFlight else { return }
        pendingAccountChoiceID = choiceID
        Task {
            await action()
            pendingAccountChoiceID = nil
        }
    }
}

struct HyphaPasswordSignInView: View {
    @ObservedObject var model: MatrixAppModel
    let message: MatrixSignOutMessage?
    let back: () -> Void

    var body: some View {
        HyphaAuthShell(
            title: "Sign in with password",
            message: "Manual password sign-in is always available. Known accounts preserve their existing Matrix device and encrypted store.",
            symbol: "key.horizontal.fill",
            back: leavePasswordSignIn,
            isBackDisabled: model.isAuthenticationOperationInFlight
        ) {
            VStack(spacing: ZenithDesign.Space.x3) {
                TextField("Matrix username", text: $model.username)
                    .textContentType(.username)
                    .hyphaIdentityInputTraits()
                    .textFieldStyle(HyphaTextFieldStyle())
                    .accessibilityIdentifier("matrix.login.username")
                HyphaRevealablePasswordField(
                    title: "Password",
                    text: $model.password,
                    accessibilityIdentifier: "matrix.login.password",
                    onSubmit: submitIfReady
                )

                if model.applePasswordsAvailable {
                    Toggle("Save in Apple Passwords", isOn: $model.savePasswordToApplePasswords)
                        .hyphaCredentialToggleStyle()
                        .accessibilityIdentifier("matrix.login.save-apple-passwords")
                    Text("Optional. Apple Passwords can sync this login through iCloud Keychain and offer it on your other Apple devices.")
                        .font(ZenithDesign.Typography.corporate(size: 12))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if message == .invalidCredentials {
                    HyphaStatusMessage(message: "Invalid username or password")
                } else if message == .savedCredentialUnavailable {
                    HyphaStatusMessage(
                        message: "Saved sign-in could not be opened. Enter your password to continue.",
                        tone: .warning
                    )
                    .accessibilityIdentifier("matrix.login.password-fallback")
                }

                HyphaButton(
                    title: "Sign in with password",
                    systemImage: "arrow.right",
                    variant: .primary,
                    fillsWidth: true
                ) {
                    submitIfReady()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
                .accessibilityIdentifier("matrix.login.submit")
            }
            .frame(maxWidth: 440)
        }
        .onDisappear {
            model.password = ""
            model.savePasswordToApplePasswords = false
        }
    }

    private var canSubmit: Bool {
        !model.isAuthenticationOperationInFlight
            && !model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.password.isEmpty
    }

    private func submitIfReady() {
        guard canSubmit else { return }
        Task { await model.signIn() }
    }

    private func leavePasswordSignIn() {
        model.password = ""
        model.savePasswordToApplePasswords = false
        back()
    }
}

struct HyphaRegistrationView: View {
    @ObservedObject var model: MatrixAppModel
    let back: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var inviteToken = ""
    @State private var saveInApplePasswords = false
    @State private var localError: String?
    @State private var isSubmitting = false

    var body: some View {
        HyphaAuthShell(
            title: "Create an invite-only account",
            message: "Create one Matrix account, then continue into its new encrypted device session.",
            symbol: "person.badge.plus",
            back: leaveRegistration,
            isBackDisabled: model.isAuthenticationOperationInFlight || isSubmitting
        ) {
            if model.registrationAvailability == .inviteToken {
                registrationForm
            } else {
                HyphaStatusMessage(
                    message: "Invite-token account creation is not available on this homeserver.",
                    tone: .warning
                )
                .frame(maxWidth: 440)
            }
        }
        .onDisappear { clearSecrets() }
        .onChange(of: model.registrationAvailability) { _, availability in
            if availability != .inviteToken {
                clearSecrets()
            }
        }
    }

    private var registrationForm: some View {
        VStack(spacing: ZenithDesign.Space.x3) {
            TextField("Username", text: $username)
                .textContentType(.username)
                .hyphaIdentityInputTraits()
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.registration.username")
            HyphaRevealablePasswordField(
                title: "Password",
                text: $password,
                accessibilityIdentifier: "matrix.registration.password",
                isNewPassword: true
            )
            HyphaRevealablePasswordField(
                title: "Confirm password",
                text: $confirmation,
                accessibilityIdentifier: "matrix.registration.confirmation",
                isNewPassword: true
            )
            if !confirmation.isEmpty {
                Label(
                    password == confirmation ? "Passwords match" : "Passwords do not match",
                    systemImage: password == confirmation ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(ZenithDesign.Typography.corporate(size: 12, weight: .medium))
                .foregroundStyle(password == confirmation ? ZenithDesign.Palette.success : ZenithDesign.Palette.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("matrix.registration.password-match")
            }
            SecureField("Invite token", text: $inviteToken)
                .hyphaIdentityInputTraits()
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.registration.token")
                .onSubmit { submit() }

            if model.applePasswordsAvailable {
                Toggle("Save in Apple Passwords", isOn: $saveInApplePasswords)
                    .hyphaCredentialToggleStyle()
                    .accessibilityIdentifier("matrix.registration.save-apple-passwords")
            }

            Text(model.applePasswordsAvailable
                 ? "The invite token is never saved. Password saving is optional; Apple Passwords can suggest a strong password and sync it through iCloud Keychain."
                 : "The invite token and account password are not saved by Hypha.")
                .font(ZenithDesign.Typography.corporate(size: 12))
                .foregroundStyle(ZenithDesign.Palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = localError ?? model.registrationError {
                HyphaStatusMessage(message: error)
                    .accessibilityIdentifier("matrix.registration.error")
            }

            HyphaButton(
                title: isSubmitting ? "Creating account…" : "Create account",
                systemImage: isSubmitting ? nil : "arrow.right",
                variant: .primary,
                fillsWidth: true,
                action: submit
            )
            .keyboardShortcut(.defaultAction)
            .disabled(!canSubmit)
            .accessibilityIdentifier("matrix.registration.submit")
        }
        .frame(maxWidth: 460)
    }

    private var canSubmit: Bool {
        !model.isAuthenticationOperationInFlight
            && !isSubmitting
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !confirmation.isEmpty
            && password == confirmation
            && !inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func leaveRegistration() {
        clearSecrets()
        back()
    }

    private func submit() {
        guard canSubmit else { return }
        guard password == confirmation else {
            localError = "Passwords do not match."
            return
        }
        let usernameForRequest = username
        let passwordForRequest = password
        let tokenForRequest = inviteToken
        let shouldSaveInApplePasswords = saveInApplePasswords
        clearSecrets()
        isSubmitting = true
        Task {
            let created = await model.createAccount(
                username: usernameForRequest,
                password: passwordForRequest,
                registrationToken: tokenForRequest,
                saveInApplePasswords: shouldSaveInApplePasswords
            )
            if !created { isSubmitting = false }
        }
    }

    private func clearSecrets() {
        username = ""
        password = ""
        confirmation = ""
        inviteToken = ""
        saveInApplePasswords = false
        localError = nil
    }
}


#if os(iOS)
struct HyphaMobileLoginView: View {
    @ObservedObject var model: MatrixAppModel
    let message: MatrixSignOutMessage?

    @State private var showsExistingDeviceSetup = false

    private var canSubmit: Bool {
        !model.isAuthenticationOperationInFlight
            && !model.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.password.isEmpty
    }

    var body: some View {
        ZStack {
            ZenithDesign.Palette.base
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: ZenithDesign.Space.x5) {
                    HyphaPulsingAppIcon()

                    VStack(spacing: ZenithDesign.Space.x2) {
                        Text("Sign in to Hypha")
                            .font(ZenithDesign.Typography.technical(.title2, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text("Use your Zenith account to open this encrypted device.")
                            .font(ZenithDesign.Typography.corporate(.callout))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: ZenithDesign.Space.x3) {
                        TextField("Username", text: $model.username)
                            .textContentType(.username)
                            .hyphaIdentityInputTraits()
                            .textFieldStyle(HyphaTextFieldStyle())
                            .accessibilityIdentifier("matrix.login.username")

                        HyphaRevealablePasswordField(
                            title: "Password",
                            text: $model.password,
                            accessibilityIdentifier: "matrix.login.password",
                            onSubmit: submitIfReady
                        )

                        if model.applePasswordsAvailable {
                            Toggle("Save in Apple Passwords", isOn: $model.savePasswordToApplePasswords)
                                .hyphaCredentialToggleStyle()
                                .accessibilityIdentifier("matrix.login.save-apple-passwords")
                        }

                        if message == .invalidCredentials {
                            HyphaStatusMessage(message: "Invalid username or password")
                        } else if message == .savedCredentialUnavailable {
                            HyphaStatusMessage(
                                message: "Saved sign-in could not be opened. Enter your password to continue.",
                                tone: .warning
                            )
                        }

                        HyphaButton(
                            title: model.isAuthenticationOperationInFlight ? "Signing in…" : "Sign in",
                            systemImage: model.isAuthenticationOperationInFlight ? nil : "arrow.right",
                            variant: .primary,
                            fillsWidth: true,
                            action: submitIfReady
                        )
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("matrix.login.submit")
                    }
                    .frame(maxWidth: 440)

                    HStack(spacing: ZenithDesign.Space.x3) {
                        Rectangle()
                            .fill(ZenithDesign.Palette.border)
                            .frame(height: 1)
                        Text("OR")
                            .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                        Rectangle()
                            .fill(ZenithDesign.Palette.border)
                            .frame(height: 1)
                    }
                    .frame(maxWidth: 440)

                    HyphaButton(
                        title: "Set up from another Hypha device",
                        systemImage: "qrcode.viewfinder",
                        variant: .secondary,
                        fillsWidth: true,
                        action: { showsExistingDeviceSetup = true }
                    )
                    .frame(maxWidth: 440)
                    .accessibilityIdentifier("matrix.login.existing-device")
                }
                .padding(.horizontal, ZenithDesign.Space.x4)
                .padding(.vertical, ZenithDesign.Space.x5)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .sheet(isPresented: $showsExistingDeviceSetup) {
            HyphaExistingDeviceSetupView(model: model)
                .hyphaMobileSheetPresentation()
        }
        .onDisappear {
            model.password = ""
            model.savePasswordToApplePasswords = false
        }
    }

    private func submitIfReady() {
        guard canSubmit else { return }
        Task { await model.signIn() }
    }
}

struct HyphaPulsingAppIcon: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isPulsing = false

    var body: some View {
        Image("HyphaMark")
            .resizable()
            .scaledToFit()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
            .shadow(
                color: ZenithDesign.Palette.brand.opacity(isPulsing ? 0.42 : 0.16),
                radius: isPulsing ? 22 : 8
            )
            .scaleEffect(accessibilityReduceMotion ? 1 : (isPulsing ? 1.045 : 0.975))
            .opacity(accessibilityReduceMotion ? 1 : (isPulsing ? 1 : 0.88))
            .onAppear { updateAnimation() }
            .onChange(of: accessibilityReduceMotion) { _, _ in updateAnimation() }
            .accessibilityLabel("Hypha")
    }

    private func updateAnimation() {
        if accessibilityReduceMotion {
            isPulsing = false
        } else {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

private struct HyphaExistingDeviceSetupView: View {
    @ObservedObject var model: MatrixAppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x5) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(ZenithDesign.Palette.brand)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                        Text("Set up from another device")
                            .font(ZenithDesign.Typography.technical(.title2, weight: .semibold))
                        Text("Hypha will never encode your password or access token in a QR code.")
                            .font(ZenithDesign.Typography.corporate(.body))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }

                    switch model.qrLoginAvailability {
                    case .available:
                        availableContent
                    case let .unavailable(reason):
                        HyphaStatusMessage(message: reason, tone: .warning)
                        Text("Secure setup requires Matrix OAuth QR login support from this homeserver.")
                            .font(ZenithDesign.Typography.corporate(.callout))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                        HyphaButton(
                            title: "Check again",
                            systemImage: "arrow.clockwise",
                            variant: .secondary,
                            fillsWidth: true,
                            action: { Task { await model.refreshQrLoginAvailability() } }
                        )
                    }
                }
                .padding(ZenithDesign.Space.x5)
            }
            .navigationTitle("Existing device setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await model.cancelQrLogin() }
                        dismiss()
                    }
                }
            }
        }
        .task { await model.refreshQrLoginAvailability() }
        .onChange(of: model.state) { _, state in
            if case .rooms = state { dismiss() }
        }
    }

    @ViewBuilder
    private var availableContent: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            Text("On your signed-in Hypha device")
                .font(ZenithDesign.Typography.technical(.headline, weight: .semibold))
            Label("Open Security.", systemImage: "1.circle.fill")
            Label("Choose Set Up Another Device.", systemImage: "2.circle.fill")
            Label("Display the secure QR code, then scan it here.", systemImage: "3.circle.fill")
        }
        .font(ZenithDesign.Typography.corporate(.callout))

        if isScanning {
            HyphaQrScannerView(
                onPayload: { payload in
                    isScanning = false
                    Task { await model.signInWithQrCode(payload) }
                },
                onFailure: { message in
                    isScanning = false
                    model.qrLoginProgress = .failed(message)
                }
            )
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZenithDesign.Radius.sheet, style: .continuous)
                    .stroke(ZenithDesign.Palette.brand, lineWidth: 2)
            }
            .accessibilityIdentifier("matrix.qr-login.scanner")
        } else {
            progressContent
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        switch model.qrLoginProgress {
        case let .checkCodeDisplay(code):
            VStack(spacing: ZenithDesign.Space.x2) {
                Text("Confirm this code on the other device")
                    .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                Text(code)
                    .font(ZenithDesign.Typography.technical(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel("Check code \(code)")
            }
            .frame(maxWidth: .infinity)
        case .starting, .waitingForToken, .syncingSecrets:
            HStack(spacing: ZenithDesign.Space.x3) {
                ProgressView()
                Text(model.qrLoginProgress == .syncingSecrets ? "Securing encryption keys…" : "Completing secure sign in…")
            }
        case let .failed(message):
            HyphaStatusMessage(message: message)
            scanButton
        case .completed:
            HyphaStatusMessage(message: "This device is signed in and verified.", tone: .success)
        default:
            scanButton
        }
    }

    private var scanButton: some View {
        HyphaButton(
            title: "Scan secure setup code",
            systemImage: "camera.viewfinder",
            variant: .primary,
            fillsWidth: true,
            action: {
                model.qrLoginProgress = nil
                isScanning = true
            }
        )
        .accessibilityIdentifier("matrix.qr-login.scan")
    }
}
#endif
