import SwiftUI
import ZenithMacOSClientCore

enum MatrixAdminAccountRole: String, CaseIterable, Identifiable {
    case user
    case administrator

    var id: String { rawValue }
    var label: String { self == .administrator ? "Administrator" : "User" }
}

struct MatrixAdminSheet: View {
    @ObservedObject var model: MatrixAppModel
    @Binding var isPresented: Bool

    @State private var localpart = ""
    @State private var temporaryPassword = ""
    @State private var passwordConfirmation = ""
    @State private var selectedRole: MatrixAdminAccountRole = .user
    @State private var showsAdministratorCreationConfirmation = false
    @State private var userPendingDeactivation: MatrixAdminUserSummary?
    @State private var userPendingLogout: MatrixAdminUserSummary?
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
                    ContentUnavailableView(
                        "Administrator access required",
                        systemImage: "person.badge.shield.checkmark",
                        description: Text("The active Matrix session is not authorized by this homeserver's administrator API.")
                    )
                }
            }
            .navigationTitle("Homeserver Administration")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .disabled(model.isAdminOperationInFlight)
                }
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 560, idealHeight: 680)
        .task {
            await model.refreshAdministratorAccess()
            await model.refreshAdministratorSnapshot()
        }
        .onDisappear(perform: clearSecrets)
        .confirmationDialog(
            "Create administrator?",
            isPresented: $showsAdministratorCreationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Create administrator", role: .destructive, action: performAccountCreation)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The new user will be able to create and deactivate users, including other administrators. The active administrator remains protected from self-deactivation.")
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
            Label("Administrator authority confirmed by the homeserver", systemImage: "checkmark.shield.fill")
                .font(ZenithDesign.Typography.corporate(.headline, weight: .semibold))
                .foregroundStyle(ZenithDesign.Palette.success)
            Text("These controls use the active Matrix administrator session. Hypha does not contain or accept the Synapse registration shared secret.")
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
            SecureField("Temporary password", text: $temporaryPassword)
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .accessibilityIdentifier("matrix.admin.account.password")
            SecureField("Confirm temporary password", text: $passwordConfirmation)
                .textContentType(.newPassword)
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .accessibilityIdentifier("matrix.admin.account.password.confirmation")

            Picker("Role", selection: $selectedRole) {
                ForEach(MatrixAdminAccountRole.allCases) { role in
                    Text(role.label).tag(role)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("matrix.admin.account.role")

            Button("Create user", action: submitAccountCreation)
                .buttonStyle(HyphaButtonStyle(.primary))
                .disabled(model.isAdminOperationInFlight)
                .accessibilityIdentifier("matrix.admin.account.create")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        temporaryPassword = ""
        passwordConfirmation = ""
    }
}
