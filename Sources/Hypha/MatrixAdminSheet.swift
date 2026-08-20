import SwiftUI
import HyphaCore

enum MatrixAdminAccountRole: String, CaseIterable, Identifiable {
    case user
    case administrator

    var id: String { rawValue }
    var label: String { self == .administrator ? "Administrator" : "User" }
}

struct MatrixAdminSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool

    @State private var administrationSecret = ""
    @State private var localpart = ""
    @State private var temporaryPassword = ""
    @State private var passwordConfirmation = ""
    @State private var selectedRole: MatrixAdminAccountRole = .user
    @State private var showsAdministratorCreationConfirmation = false
    @State private var userPendingPromotion: MatrixAdminUserSummary?
    @State private var userPendingDeactivation: MatrixAdminUserSummary?
    @State private var userPendingLogout: MatrixAdminUserSummary?
    @State private var passwordResetRequest: MatrixPasswordResetRequest?
    @State private var roomPendingPurge: MatrixAdminRoomSummary?
    @State private var roomName = ""
    @State private var roomTopic = ""
    @State private var createsSpace = false
    @State private var roomVisibility: MatrixRoomVisibility = .inviteOnly
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch model.adminAccessState {
                case .authorized:
                    administrationContent
                case .checking, .unknown:
                    ProgressView("Checking administrator authority…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    VStack(spacing: ZenithDesign.Space.x4) {
                        ContentUnavailableView(
                            "Authenticate for administration",
                            systemImage: "person.badge.shield.checkmark",
                            description: Text(model.adminMessage ?? "Enter the dedicated homeserver administration secret.")
                        )
                        HyphaRevealablePasswordField(
                            title: "Administration secret",
                            text: $administrationSecret,
                            accessibilityIdentifier: "matrix.admin.secret",
                            isNewPassword: false
                        )
                        .frame(maxWidth: 420)
                        Text("This creates a short-lived, scoped Hypha administration session. It does not sign in to Matrix and is not saved by Hypha.")
                            .font(ZenithDesign.Typography.corporate(.callout))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 520)
                        Button("Authenticate for administration") {
                            let secretForRequest = administrationSecret
                            administrationSecret = ""
                            Task {
                                await model.authenticateAdministrator(secret: secretForRequest)
                            }
                        }
                        .buttonStyle(HyphaButtonStyle(.primary))
                        .disabled(
                            model.isAdminOperationInFlight
                                || !(32...512).contains(administrationSecret.utf8.count)
                        )
                        .accessibilityIdentifier("matrix.admin.authenticate")
                    }
                    .padding(ZenithDesign.Space.x5)
                }
            }
            .navigationTitle("Homeserver Administration")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        clearSecrets()
                        Task {
                            if await model.endAdministratorAccess() {
                                isPresented = false
                            }
                        }
                    }
                    .disabled(model.isAdminOperationInFlight)
                }
            }
        }
        .hyphaFlexibleSheetFrame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 680)
        .hyphaMobileSheetPresentation()
        .interactiveDismissDisabled(
            model.adminAccessState == .authorized
                || model.isAdminOperationInFlight
        )
        .task {
            await model.refreshAdministratorAccess()
            await model.refreshAdministratorSnapshot()
        }
        .onDisappear {
            clearSecrets()
            Task { await model.endAdministratorAccess() }
        }
        .sheet(item: $passwordResetRequest) { request in
            MatrixAdminPasswordResetSheet(
                model: model,
                request: request,
                isPresented: Binding(
                    get: { passwordResetRequest != nil },
                    set: { if !$0 { passwordResetRequest = nil } }
                )
            )
        }
        .confirmationDialog(
            "Create administrator?",
            isPresented: $showsAdministratorCreationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create administrator", role: .destructive, action: performAccountCreation)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new user will be able to create and deactivate users, including other administrators. The hidden broker service administrator remains protected from client operations.")
        }
        .confirmationDialog(
            "Delete account permanently?",
            isPresented: Binding(
                get: { userPendingDeactivation != nil },
                set: { if !$0 { userPendingDeactivation = nil } }
            ),
            titleVisibility: .visible,
            presenting: userPendingDeactivation
        ) { user in
            Button("Delete account", role: .destructive) {
                userPendingDeactivation = nil
                Task { await model.deactivateAdministratorManagedAccount(user) }
            }
            Button("Cancel", role: .cancel) { userPendingDeactivation = nil }
        } message: { user in
            Text("This permanently disables \(user.isAdministrator ? "administrator " : "")\(user.userID), signs out every device, and erases profile data. Synapse retains the Matrix ID and event references so room history remains internally consistent; the ID cannot be recreated.")
        }
        .confirmationDialog(
            "Promote existing account?",
            isPresented: Binding(
                get: { userPendingPromotion != nil },
                set: { if !$0 { userPendingPromotion = nil } }
            ),
            titleVisibility: .visible,
            presenting: userPendingPromotion
        ) { user in
            Button("Promote to administrator", role: .destructive) {
                userPendingPromotion = nil
                Task { await model.promoteAdministratorManagedAccount(user) }
            }
            Button("Cancel", role: .cancel) { userPendingPromotion = nil }
        } message: { user in
            Text("Promote \(user.userID)? This changes only the Synapse administrator role and does not reset the account password.")
        }
        .confirmationDialog(
            "Log out every device for this account?",
            isPresented: Binding(get: { userPendingLogout != nil }, set: { if !$0 { userPendingLogout = nil } }),
            titleVisibility: .visible,
            presenting: userPendingLogout
        ) { user in
            Button("Log out every device", role: .destructive) {
                userPendingLogout = nil
                Task { await model.logoutAdministratorManagedAccount(user) }
            }
            Button("Cancel", role: .cancel) { userPendingLogout = nil }
        } message: { user in
            Text("This revokes every access token for \(user.userID). Saved passwords are not deleted.")
        }
        .confirmationDialog(
            "Block and purge this room?",
            isPresented: Binding(
                get: { roomPendingPurge != nil },
                set: { if !$0 { roomPendingPurge = nil } }
            ),
            titleVisibility: .visible,
            presenting: roomPendingPurge
        ) { room in
            Button("Block and purge", role: .destructive) {
                roomPendingPurge = nil
                Task { await model.purgeAdministratorManagedRoom(room) }
            }
            Button("Cancel", role: .cancel) { roomPendingPurge = nil }
        } message: { room in
            Text("This removes \(room.name) from this homeserver and blocks reuse of its room ID. Copies retained by federated servers or members are outside this server's deletion authority.")
        }
    }

    private var administrationContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x5) {
                authorityNotice
                passwordResetSection
                createRoomSection
                createAccountSection
                accountSection
                roomSection
            }
            .padding(ZenithDesign.Space.x5)
        }
        .background(ZenithDesign.Palette.base)
    }

    private var authorityNotice: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
            Label("Scoped administration session confirmed by the homeserver", systemImage: "checkmark.shield.fill")
                .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.success)
            Text("These controls use a short-lived Hypha broker session that is independent from Matrix sign-in. The dedicated administration secret, Synapse service credential, and Synapse registration shared secret are never retained by Hypha.")
                .font(ZenithDesign.Typography.corporate(.callout))
                .foregroundStyle(ZenithDesign.Palette.muted)
            if let message = validationMessage ?? model.adminMessage {
                Text(message)
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("matrix.admin.message")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZenithDesign.Space.x4)
        .background(ZenithDesign.Palette.baseRaised)
        .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
    }

    private var passwordResetSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            HStack {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    sectionTitle("PASSWORD RESET REQUESTS")
                    Text("Pending homeserver requests")
                        .font(ZenithDesign.Typography.corporate(.title3, weight: .semibold))
                }
                Spacer()
                refreshButton
            }
            Text("Requests are authenticated Matrix account data and contain no passwords. Resetting preserves the account role, replaces the password, and logs out existing devices.")
                .font(ZenithDesign.Typography.corporate(.callout))
                .foregroundStyle(ZenithDesign.Palette.muted)

            if model.adminPasswordResetRequests.isEmpty {
                Text("No pending password reset requests.")
                    .font(ZenithDesign.Typography.corporate(.callout))
                    .foregroundStyle(ZenithDesign.Palette.muted)
            } else {
                ForEach(model.adminPasswordResetRequests) { request in
                    let resetIssued = model.issuedPasswordResetRequestIDs.contains(request.id)
                    HStack(spacing: ZenithDesign.Space.x3) {
                        Image(systemName: "person.badge.key.fill")
                            .foregroundStyle(ZenithDesign.Palette.warning)
                        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                            Text(request.userID)
                                .font(ZenithDesign.Typography.corporate(.callout, weight: .medium))
                                .textSelection(.enabled)
                            Text(
                                Date(timeIntervalSince1970: TimeInterval(request.requestedAtMilliseconds) / 1_000),
                                style: .relative
                            )
                            .font(ZenithDesign.Typography.technical(.caption2, weight: .medium))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                        }
                        Spacer()
                        Button(resetIssued ? "Awaiting user" : "Reset temporary password…") {
                            passwordResetRequest = request
                        }
                        .disabled(model.isAdminOperationInFlight || resetIssued)
                        .accessibilityIdentifier("matrix.admin.password-reset.\(request.id)")
                    }
                    .padding(ZenithDesign.Space.x3)
                    .background(ZenithDesign.Palette.baseRaised)
                    .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.control, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var createRoomSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            sectionTitle("CREATE ROOM OR SPACE")
            TextField("Name", text: $roomName).textFieldStyle(.roundedBorder)
            TextField("Topic (optional)", text: $roomTopic).textFieldStyle(.roundedBorder)
            Toggle("Create a Matrix space", isOn: $createsSpace)
            Picker("Access", selection: $roomVisibility) {
                Text("Invite only").tag(MatrixRoomVisibility.inviteOnly)
                Text("Public").tag(MatrixRoomVisibility.public)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("matrix.admin.room.visibility")
            Text(roomVisibility == .public
                 ? "Published and open to anyone. Rooms remain encrypted; Spaces organize public hierarchy."
                 : (createsSpace ? "Only invited members can join this Space." : "Only invited members can join. Messages are encrypted."))
                .font(.caption).foregroundStyle(ZenithDesign.Palette.muted)
            Button(createsSpace ? "Create space" : "Create encrypted room") {
                let name = roomName
                let topic = roomTopic
                let isSpace = createsSpace
                let visibility = roomVisibility
                Task {
                    if await model.createAdministratorManagedRoom(name: name, topic: topic, asSpace: isSpace, visibility: visibility) {
                        roomName = ""; roomTopic = ""; createsSpace = false; roomVisibility = .inviteOnly
                    }
                }
            }
            .buttonStyle(HyphaButtonStyle(.primary))
            .disabled(model.isAdminOperationInFlight || roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("matrix.admin.room.create")
        }
    }

    private var createAccountSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            sectionTitle("CREATE ACCOUNT")
            Text("Create user")
                .font(ZenithDesign.Typography.corporate(.title3, weight: .semibold))
            Text("Choose a one-time temporary password and transfer it through a secure channel. Hypha clears it before contacting the homeserver and does not save it.")
                .font(ZenithDesign.Typography.corporate(.callout))
                .foregroundStyle(ZenithDesign.Palette.muted)

            TextField("Username", text: $localpart)
                .textContentType(.username)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("matrix.admin.account.username")
            HyphaRevealablePasswordField(
                title: "Temporary password",
                text: $temporaryPassword,
                accessibilityIdentifier: "matrix.admin.account.password",
                isNewPassword: true
            )
            HyphaRevealablePasswordField(
                title: "Confirm temporary password",
                text: $passwordConfirmation,
                accessibilityIdentifier: "matrix.admin.account.password.confirmation",
                isNewPassword: true
            )
            if !passwordConfirmation.isEmpty {
                Label(
                    temporaryPassword == passwordConfirmation ? "Passwords match" : "Passwords do not match",
                    systemImage: temporaryPassword == passwordConfirmation ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .font(ZenithDesign.Typography.corporate(.caption, weight: .medium))
                .foregroundStyle(temporaryPassword == passwordConfirmation ? ZenithDesign.Palette.success : ZenithDesign.Palette.error)
                .accessibilityIdentifier("matrix.admin.account.password-match")
            }

            Picker("Role", selection: $selectedRole) {
                ForEach(MatrixAdminAccountRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("matrix.admin.account.role")

            Button("Create user", action: submitAccountCreation)
                .buttonStyle(HyphaButtonStyle(.primary))
                .disabled(!canSubmitAccountCreation)
                .accessibilityIdentifier("matrix.admin.account.create")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSubmitAccountCreation: Bool {
        !model.isAdminOperationInFlight
            && !localpart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && temporaryPassword.count >= 12
            && !passwordConfirmation.isEmpty
            && temporaryPassword == passwordConfirmation
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            HStack {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    sectionTitle("ACCOUNTS")
                    Text("Active local accounts")
                        .font(ZenithDesign.Typography.corporate(.title3, weight: .semibold))
                }
                Spacer()
                refreshButton
            }

            if let users = model.adminSnapshot?.users, !users.isEmpty {
                ForEach(users) { user in
                    HStack(spacing: ZenithDesign.Space.x3) {
                        Image(systemName: user.isAdministrator ? "person.badge.shield.checkmark" : "person.crop.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(user.isAdministrator ? ZenithDesign.Palette.brand : ZenithDesign.Palette.muted)
                        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                            Text(user.userID)
                                .font(ZenithDesign.Typography.corporate(.callout, weight: .medium))
                                .textSelection(.enabled)
                            Text(user.isAdministrator ? "Administrator" : "User")
                                .font(ZenithDesign.Typography.technical(.caption2, weight: .medium))
                                .foregroundStyle(ZenithDesign.Palette.muted)
                        }
                        Spacer()
                        if !user.isAdministrator && user.userType == nil {
                            Button("Promote to administrator…") {
                                userPendingPromotion = user
                            }
                            .disabled(model.isAdminOperationInFlight)
                            .accessibilityLabel("Promote \(user.userID) to administrator")
                        }
                        Button("Log out devices…", role: .destructive) {
                            userPendingLogout = user
                        }
                        .disabled(model.isAdminOperationInFlight)
                        .accessibilityLabel("Log out every device for \(user.userID)")
                        if user.userID == model.adminSnapshot?.currentUserID || user.userType != nil {
                            Text("Protected")
                                .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
                                .foregroundStyle(ZenithDesign.Palette.muted)
                        } else {
                            Button("Delete…", role: .destructive) {
                                userPendingDeactivation = user
                            }
                            .disabled(model.isAdminOperationInFlight)
                            .accessibilityLabel("Delete \(user.userID)")
                        }
                    }
                    .padding(.vertical, ZenithDesign.Space.x2)
                    Divider()
                }
            } else if model.isAdminOperationInFlight {
                ProgressView("Loading accounts…")
            } else {
                Text("No active accounts returned by the homeserver.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            sectionTitle("ROOMS")
            Text("Homeserver rooms")
                .font(ZenithDesign.Typography.corporate(.title3, weight: .semibold))

            if let rooms = model.adminSnapshot?.rooms, !rooms.isEmpty {
                ForEach(rooms) { room in
                    HStack(spacing: ZenithDesign.Space.x3) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ZenithDesign.Palette.muted)
                        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                            Text(room.name)
                                .font(ZenithDesign.Typography.corporate(.callout, weight: .medium))
                            Text("\(room.joinedMemberCount) joined · \(room.roomID)")
                                .font(ZenithDesign.Typography.technical(.caption2))
                                .foregroundStyle(ZenithDesign.Palette.muted)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Purge…", role: .destructive) {
                            roomPendingPurge = room
                        }
                        .disabled(model.isAdminOperationInFlight)
                        .accessibilityLabel("Block and purge \(room.name)")
                    }
                    .padding(.vertical, ZenithDesign.Space.x2)
                    Divider()
                }
            } else if model.isAdminOperationInFlight {
                ProgressView("Loading rooms…")
            } else {
                Text("No rooms remain on this homeserver.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refreshAdministratorSnapshot() }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(HyphaButtonStyle(.quiet))
        .disabled(model.isAdminOperationInFlight)
        .accessibilityIdentifier("matrix.admin.refresh")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(ZenithDesign.Palette.muted)
    }

    private func submitAccountCreation() {
        let normalizedLocalpart = localpart.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedLocalpart.isEmpty else {
            validationMessage = "Enter a username."
            return
        }
        guard temporaryPassword.count >= 12 else {
            validationMessage = "Use a temporary password with at least 12 characters."
            return
        }
        guard temporaryPassword == passwordConfirmation else {
            validationMessage = "The temporary passwords do not match."
            return
        }
        validationMessage = nil
        if selectedRole == .administrator {
            showsAdministratorCreationConfirmation = true
        } else {
            performAccountCreation()
        }
    }

    private func performAccountCreation() {
        let normalizedLocalpart = localpart.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let passwordForRequest = temporaryPassword
        let administrator = selectedRole == .administrator
        clearSecrets()
        validationMessage = nil
        Task {
            let created = await model.createAdministratorManagedAccount(
                localpart: normalizedLocalpart,
                temporaryPassword: passwordForRequest,
                administrator: administrator
            )
            if created {
                localpart = ""
                selectedRole = .user
            }
        }
    }

    private func clearSecrets() {
        administrationSecret = ""
        temporaryPassword = ""
        passwordConfirmation = ""
    }
}

private struct MatrixAdminPasswordResetSheet: View {
    @ObservedObject var model: MatrixAppModel
    let request: MatrixPasswordResetRequest
    @Binding var isPresented: Bool

    @State private var temporaryPassword = ""
    @State private var passwordConfirmation = ""
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Requested account") {
                    Text(request.userID)
                        .textSelection(.enabled)
                    Text("Set a one-time temporary password. The homeserver will preserve this account's role and log out every existing device.")
                        .font(.callout)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                Section("Temporary password") {
                    HyphaRevealablePasswordField(
                        title: "Temporary password",
                        text: $temporaryPassword,
                        accessibilityIdentifier: "matrix.admin.password-reset.password",
                        isNewPassword: true
                    )
                    HyphaRevealablePasswordField(
                        title: "Confirm temporary password",
                        text: $passwordConfirmation,
                        accessibilityIdentifier: "matrix.admin.password-reset.password.confirmation",
                        isNewPassword: true
                    )
                    if !passwordConfirmation.isEmpty {
                        Label(
                            temporaryPassword == passwordConfirmation ? "Passwords match" : "Passwords do not match",
                            systemImage: temporaryPassword == passwordConfirmation ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(temporaryPassword == passwordConfirmation ? ZenithDesign.Palette.success : ZenithDesign.Palette.error)
                        .accessibilityIdentifier("matrix.admin.password-reset.password-match")
                    }
                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(ZenithDesign.Palette.error)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reset temporary password")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(model.isAdminOperationInFlight)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset password", action: submit)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("matrix.admin.password-reset.submit")
                }
            }
        }
        .hyphaFlexibleSheetFrame(minWidth: 500, idealWidth: 560, minHeight: 340)
        .hyphaMobileSheetPresentation()
        .interactiveDismissDisabled(model.isAdminOperationInFlight)
        .onDisappear(perform: clearSecrets)
    }

    private var canSubmit: Bool {
        !model.isAdminOperationInFlight
            && temporaryPassword.count >= 12
            && !passwordConfirmation.isEmpty
            && temporaryPassword == passwordConfirmation
    }

    private func submit() {
        guard temporaryPassword.count >= 12 else {
            validationMessage = "Use a temporary password with at least 12 characters."
            return
        }
        guard temporaryPassword == passwordConfirmation else {
            validationMessage = "The temporary passwords do not match."
            return
        }
        let passwordForRequest = temporaryPassword
        clearSecrets()
        Task {
            if await model.resetAdministratorManagedPassword(
                for: request,
                temporaryPassword: passwordForRequest
            ) {
                isPresented = false
            } else {
                validationMessage = model.adminMessage ?? "The homeserver did not confirm the password reset."
            }
        }
    }

    private func clearSecrets() {
        temporaryPassword = ""
        passwordConfirmation = ""
    }
}
