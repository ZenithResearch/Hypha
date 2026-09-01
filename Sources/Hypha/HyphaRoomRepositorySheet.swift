#if os(macOS)
import AppKit
import HyphaCore
import SwiftUI

struct HyphaRoomRepositorySheet: View {
    @ObservedObject var model: MatrixAppModel
    @ObservedObject var githubConnection: HyphaGitHubConnectionModel
    let room: MatrixRoomSummary
    @Binding var isPresented: Bool

    @State private var repositoryState = MatrixRoomRepositoryState.empty
    @State private var remoteRepositoryURL = ""
    @State private var repositoryName = ""
    @State private var requestedRef = "main"
    @State private var attachRepositoryRoot: URL?
    @State private var attachRepositoryPath = ""
    @State private var attachBuildCommand = ""
    @State private var selectedAttachmentID: String?
    @State private var bindingRepositoryRoot: URL?
    @State private var bindingRepositoryPath = ""
    @State private var bindingBuildCommand = ""
    @State private var githubAccessMessage: String?
    @State private var githubAccessIsError = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true
    @State private var isMutating = false
    @State private var isVerifyingGitHubAccess = false
    @State private var availableGitHubRepositories: [HyphaGitHubRepositoryChoice] = []
    @State private var selectedGitHubRepositoryID: String?
    @State private var isLoadingGitHubRepositories = false
    @State private var githubRepositoryLoadMessage: String?
    @State private var showsManualRepositoryEntry = false
    @State private var showsAttachLocalOptions = false
    @State private var pendingRemoval: MatrixRoomRepositoryDescriptor?
    @State private var confirmsGitHubDisconnect = false

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()

    private var repositorySet: MatrixRoomRepositorySet {
        repositoryState.repositorySet
    }

    private var selectedAttachment: MatrixRoomRepositoryDescriptor? {
        guard let selectedAttachmentID else { return nil }
        return repositorySet.repositories.first { $0.id == selectedAttachmentID }
    }

    private var selectedGitHubRepository: HyphaGitHubRepositoryChoice? {
        guard let selectedGitHubRepositoryID else { return nil }
        return availableGitHubRepositories.first { $0.id == selectedGitHubRepositoryID }
    }

    private var canAttach: Bool {
        !isMutating
            && repositorySet.repositories.count < MatrixRoomRepositorySet.maximumAttachmentCount
            && !remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !requestedRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: ZenithDesign.Space.x4) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ZenithDesign.Palette.brand)
                    .frame(width: 42, height: 42)
                    .background(ZenithDesign.Palette.brand.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    Text("Room repositories")
                        .font(ZenithDesign.Typography.corporate(size: 22, weight: .semibold))
                    Text(room.name)
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(repositorySet.repositories.count) / \(MatrixRoomRepositorySet.maximumAttachmentCount)")
                        .font(ZenithDesign.Typography.technical(size: 17, weight: .semibold))
                    Text("attached")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(repositorySet.repositories.count) of \(MatrixRoomRepositorySet.maximumAttachmentCount) repositories attached")
            }
            .padding(.horizontal, ZenithDesign.Space.x6)
            .padding(.vertical, ZenithDesign.Space.x5)

            Divider()

            Form {
                Section("Attached") {
                    if isLoading {
                        ProgressView("Reading room repository state…")
                    } else if repositorySet.repositories.isEmpty {
                        Label("No repositories are attached to this room.", systemImage: "shippingbox")
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    } else {
                        ForEach(repositorySet.repositories) { repository in
                            repositoryRow(repository)
                        }
                    }

                    if repositoryState.mirrorStatus == .missing
                        || repositoryState.mirrorStatus == .divergent {
                        HyphaStatusMessage(
                            message: "The compatibility mirror needs repair. The repository collection remains authoritative.",
                            tone: .warning
                        )
                    }
                }

                if !repositorySet.repositories.isEmpty {
                    Section("Local checkout on this Mac") {
                        Picker("Repository", selection: $selectedAttachmentID) {
                            ForEach(repositorySet.repositories) { repository in
                                Text(repository.name).tag(Optional(repository.id))
                            }
                        }
                        .onChange(of: selectedAttachmentID) { _, _ in loadSelectedBinding() }

                        HStack {
                            TextField("/path/to/repository", text: $bindingRepositoryPath)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { useTypedBindingPath() }
                                .accessibilityIdentifier("matrix.room.repositories.binding.path")
                            Button("Choose…", action: chooseBindingRepository)
                                .accessibilityIdentifier("matrix.room.repositories.binding.choose")
                        }

                        Text("Build command (optional)")
                            .font(.headline)
                        TextEditor(text: $bindingBuildCommand)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 58, maxHeight: 96)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(ZenithDesign.Palette.border))
                            .accessibilityIdentifier("matrix.room.repositories.binding.command")

                        HStack {
                            Button("Save local binding", action: saveSelectedBinding)
                                .disabled(bindingRepositoryRoot == nil || selectedAttachment == nil)
                                .accessibilityIdentifier("matrix.room.repositories.binding.save")
                            if bindingRepositoryRoot != nil {
                                Button("Remove local binding", role: .destructive) {
                                    removeSelectedBinding()
                                }
                                .accessibilityIdentifier("matrix.room.repositories.binding.remove")
                            }
                        }
                        Text("The checkout, bookmark, build command, and logs remain device-local. Saving a local binding never changes the shared repository ref.")
                            .font(.caption)
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                }

                Section("Attach a repository") {
                    repositorySelectionSection
                }

                if let statusMessage {
                    Section {
                        HyphaStatusMessage(
                            message: statusMessage,
                            tone: statusIsError ? .error : .success
                        )
                        .textSelection(.enabled)
                        .accessibilityIdentifier("matrix.room.repositories.status")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Button("Close") { isPresented = false }
                Spacer()
                Button(isMutating ? "Attaching…" : "Attach repository", action: attach)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAttach)
                    .accessibilityIdentifier("matrix.room.repositories.attach")
            }
            .padding(ZenithDesign.Space.x4)
        }
        .frame(minWidth: 720, idealWidth: 840, minHeight: 620, idealHeight: 760)
        .task {
            await load()
            await loadGitHubRepositories()
        }
        .onChange(of: githubConnection.isConnected) { _, _ in
            Task { await loadGitHubRepositories() }
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.name ?? "this repository")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove repository", role: .destructive) {
                if let repository = pendingRemoval { remove(repository) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its Assets will leave the room. The local checkout itself is never deleted.")
        }
        .confirmationDialog(
            "Disconnect GitHub from this Mac?",
            isPresented: $confirmsGitHubDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect GitHub", role: .destructive) {
                githubConnection.disconnect()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Repository attachments stay in their rooms. Private repository discovery and refresh remain unavailable until GitHub is connected again.")
        }
    }

    @ViewBuilder
    private var repositorySelectionSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
            githubConnectionCard

            if githubConnection.isConnected {
                githubRepositoryPicker
            }

            if let selectedGitHubRepository {
                HStack(spacing: ZenithDesign.Space.x3) {
                    Image(systemName: selectedGitHubRepository.isPrivate ? "lock.fill" : "globe")
                        .foregroundStyle(ZenithDesign.Palette.brand)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGitHubRepository.fullName)
                            .font(.headline)
                        Text("Default branch: \(selectedGitHubRepository.defaultBranch)")
                            .font(.caption.monospaced())
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    Spacer()
                    if selectedGitHubRepository.isArchived {
                        Text("Archived")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ZenithDesign.Palette.warning)
                    }
                }
                .padding(ZenithDesign.Space.x3)
                .background(ZenithDesign.Palette.baseSubtle)
                .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous)
                        .stroke(ZenithDesign.Palette.borderStrong, lineWidth: 1)
                }
            }

            DisclosureGroup("Enter a repository URL manually", isExpanded: $showsManualRepositoryEntry) {
                manualRepositoryFields
                    .padding(.top, ZenithDesign.Space.x3)
            }
            .font(.headline)

            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("Branch, tag, or commit")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                TextField("", text: $requestedRef, prompt: Text("main"))
                    .labelsHidden()
                    .textFieldStyle(HyphaTextFieldStyle())
                    .accessibilityIdentifier("matrix.room.repositories.ref")
            }

            DisclosureGroup("Local checkout and Rebuild (optional)", isExpanded: $showsAttachLocalOptions) {
                attachLocalCheckoutFields
                    .padding(.top, ZenithDesign.Space.x3)
            }
            .font(.headline)

            Text("Hypha uses existing remote output first. Attaching never runs a build; a local checkout only enables fallback and the separately confirmed Rebuild action.")
                .font(.caption)
                .foregroundStyle(ZenithDesign.Palette.muted)
        }
        .padding(.vertical, ZenithDesign.Space.x1)
    }

    @ViewBuilder
    private var githubConnectionCard: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            if githubConnection.isConnected {
                HStack(alignment: .center, spacing: ZenithDesign.Space.x3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                        Text("GitHub connected")
                            .font(.headline)
                        Text("@\(githubConnection.accountLogin ?? "account")")
                            .font(.caption.monospaced())
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    Spacer()
                    HyphaButton(title: "Refresh", systemImage: "arrow.clockwise", variant: .secondary) {
                        Task { await loadGitHubRepositories() }
                    }
                    .disabled(isLoadingGitHubRepositories)
                    .accessibilityIdentifier("matrix.room.repositories.github-refresh")
                    HyphaButton(title: "Disconnect", variant: .quiet) {
                        confirmsGitHubDisconnect = true
                    }
                    .accessibilityIdentifier("matrix.room.repositories.github-disconnect")
                }

                if isLoadingGitHubRepositories {
                    HStack(spacing: ZenithDesign.Space.x2) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading repositories available to this account…")
                            .font(.caption)
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    .accessibilityIdentifier("matrix.room.repositories.github-status")
                } else if let githubRepositoryLoadMessage {
                    HyphaStatusMessage(message: githubRepositoryLoadMessage, tone: .warning)
                        .accessibilityIdentifier("matrix.room.repositories.github-status")
                } else {
                    Label(
                        "\(availableGitHubRepositories.count) repositories available",
                        systemImage: "shippingbox"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .accessibilityIdentifier("matrix.room.repositories.github-status")
                }
            } else {
                HStack(alignment: .top, spacing: ZenithDesign.Space.x3) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.brand)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                        Text("Connect GitHub")
                            .font(.headline)
                        Text("Choose private, organization, and public repositories without copying their URLs.")
                            .font(.caption)
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                }

                SecureField(
                    "",
                    text: $githubConnection.tokenInput,
                    prompt: Text("GitHub personal access token")
                )
                .labelsHidden()
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityLabel("GitHub personal access token")
                .accessibilityIdentifier("matrix.room.repositories.github-token")

                HStack(alignment: .center, spacing: ZenithDesign.Space.x3) {
                    Text("Saved once in this Mac's protected Keychain and reused globally by Hypha. It is never stored in the room.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                    Spacer()
                    HyphaButton(
                        title: githubConnection.isConnecting ? "Connecting…" : "Connect GitHub",
                        systemImage: githubConnection.isConnecting ? nil : "link",
                        variant: .primary
                    ) {
                        githubConnection.connect()
                    }
                    .disabled(
                        githubConnection.isConnecting
                            || githubConnection.tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("matrix.room.repositories.github-connect")
                }

                if let message = githubConnection.statusMessage {
                    HyphaStatusMessage(
                        message: message,
                        tone: githubConnection.statusIsError ? .error : .success
                    )
                    .accessibilityIdentifier("matrix.room.repositories.github-status")
                }
            }
        }
        .padding(ZenithDesign.Space.x4)
        .background(ZenithDesign.Palette.baseSubtle)
        .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous)
                .stroke(
                    githubConnection.isConnected
                        ? ZenithDesign.Palette.success.opacity(0.45)
                        : ZenithDesign.Palette.borderStrong,
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var githubRepositoryPicker: some View {
        if !isLoadingGitHubRepositories,
           githubRepositoryLoadMessage == nil,
           availableGitHubRepositories.isEmpty {
            HyphaStatusMessage(
                message: "No accessible GitHub repositories were returned. You can still attach one by URL.",
                tone: .warning
            )
        } else if !availableGitHubRepositories.isEmpty {
            Picker("GitHub repository", selection: $selectedGitHubRepositoryID) {
                Text("Choose a GitHub repository…").tag(String?.none)
                ForEach(availableGitHubRepositories) { repository in
                    Text(repositoryPickerLabel(repository)).tag(Optional(repository.id))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("matrix.room.repositories.github-picker")
            .onChange(of: selectedGitHubRepositoryID) { _, identifier in
                guard let identifier,
                      let repository = availableGitHubRepositories.first(where: { $0.id == identifier }) else {
                    return
                }
                selectGitHubRepository(repository)
            }
        }
    }

    @ViewBuilder
    private var manualRepositoryFields: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("Repository URL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                TextField(
                    "",
                    text: $remoteRepositoryURL,
                    prompt: Text("https://github.com/owner/repository")
                )
                .labelsHidden()
                .textFieldStyle(HyphaTextFieldStyle())
                .accessibilityIdentifier("matrix.room.repositories.remote")
                .onChange(of: remoteRepositoryURL) { _, value in
                    githubAccessMessage = nil
                    if selectedGitHubRepository?.remoteURL != value {
                        selectedGitHubRepositoryID = nil
                    }
                    if repositoryName.isEmpty {
                        repositoryName = inferredRepositoryName(from: value)
                    }
                }
            }

            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("Room label")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ZenithDesign.Palette.muted)
                TextField("", text: $repositoryName, prompt: Text("Repository name"))
                    .labelsHidden()
                    .textFieldStyle(HyphaTextFieldStyle())
                    .accessibilityIdentifier("matrix.room.repositories.name")
            }

            HStack(alignment: .center, spacing: ZenithDesign.Space.x3) {
                Button(isVerifyingGitHubAccess ? "Verifying…" : "Verify GitHub access") {
                    verifyGitHubAccess()
                }
                .disabled(
                    isVerifyingGitHubAccess
                        || !githubConnection.isConnected
                        || remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier("matrix.room.repositories.github-verify")
                if let githubAccessMessage {
                    Text(githubAccessMessage)
                        .font(.caption)
                        .foregroundStyle(
                            githubAccessIsError
                                ? ZenithDesign.Palette.error
                                : ZenithDesign.Palette.success
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var attachLocalCheckoutFields: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
            HStack {
                TextField("Remote-only is supported", text: $attachRepositoryPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { useTypedAttachPath() }
                    .accessibilityIdentifier("matrix.room.repositories.attach-local.path")
                Button("Choose…", action: chooseAttachRepository)
                    .accessibilityIdentifier("matrix.room.repositories.attach-local.choose")
            }
            Text("Build command (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ZenithDesign.Palette.muted)
            TextEditor(text: $attachBuildCommand)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 52, maxHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ZenithDesign.Palette.border))
                .accessibilityIdentifier("matrix.room.repositories.attach-local.command")
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repository: MatrixRoomRepositoryDescriptor) -> some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
            HStack {
                Text(repository.name)
                    .font(.headline)
                if repository.id == repositorySet.primaryID {
                    Text("Primary")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(ZenithDesign.Palette.brand)
                }
                Spacer()
                if repository.id != repositorySet.primaryID {
                    Button("Make primary") { makePrimary(repository) }
                        .disabled(isMutating)
                }
                Button("Remove", role: .destructive) { pendingRemoval = repository }
                    .disabled(isMutating)
            }
            Text(repository.repository)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            HStack {
                Text("Ref \(repository.requestedRef)")
                if let commit = repository.resolvedCommit {
                    Text("• \(commit.prefix(10))")
                }
                Text("• \(repository.outputDirectory)/\(repository.manifestPath)")
            }
            .font(.caption)
            .foregroundStyle(ZenithDesign.Palette.muted)
        }
        .padding(.vertical, ZenithDesign.Space.x1)
        .accessibilityIdentifier("matrix.room.repositories.row.\(repository.id)")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            repositoryState = try await model.repositoryState(for: room)
            selectedAttachmentID = repositorySet.primaryID ?? repositorySet.repositories.first?.id
            loadSelectedBinding()
        } catch {
            status("Hypha could not read the room's repository collection from Matrix.", error: true)
        }
    }

    private func loadGitHubRepositories() async {
        guard githubConnection.isConnected else {
            availableGitHubRepositories = []
            selectedGitHubRepositoryID = nil
            githubRepositoryLoadMessage = nil
            showsManualRepositoryEntry = true
            return
        }
        isLoadingGitHubRepositories = true
        githubRepositoryLoadMessage = nil
        defer { isLoadingGitHubRepositories = false }
        do {
            availableGitHubRepositories = try await githubConnection.repositories()
            if !availableGitHubRepositories.isEmpty,
               remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showsManualRepositoryEntry = false
            }
            if let selectedGitHubRepositoryID,
               !availableGitHubRepositories.contains(where: { $0.id == selectedGitHubRepositoryID }) {
                self.selectedGitHubRepositoryID = nil
            }
        } catch let error as HyphaGitHubRepositoryAccessError {
            availableGitHubRepositories = []
            selectedGitHubRepositoryID = nil
            githubRepositoryLoadMessage = githubAccessErrorMessage(error)
            showsManualRepositoryEntry = true
        } catch {
            availableGitHubRepositories = []
            selectedGitHubRepositoryID = nil
            githubRepositoryLoadMessage = "GitHub repositories could not be loaded right now."
            showsManualRepositoryEntry = true
        }
    }

    private func selectGitHubRepository(_ repository: HyphaGitHubRepositoryChoice) {
        selectedGitHubRepositoryID = repository.id
        remoteRepositoryURL = repository.remoteURL
        repositoryName = repository.name
        requestedRef = repository.defaultBranch
        githubAccessMessage = nil
        githubAccessIsError = false
        showsManualRepositoryEntry = false
    }

    private func repositoryPickerLabel(_ repository: HyphaGitHubRepositoryChoice) -> String {
        var details: [String] = []
        if repository.isPrivate { details.append("Private") }
        if repository.isArchived { details.append("Archived") }
        return details.isEmpty
            ? repository.fullName
            : "\(repository.fullName)  ·  \(details.joined(separator: " · "))"
    }

    private func attach() {
        isMutating = true
        statusMessage = nil
        Task {
            defer { isMutating = false }
            do {
                let cleanName = repositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseID = MatrixRoomRepositorySet.attachmentID(name: cleanName)
                let identifier = uniqueAttachmentID(base: baseID)
                let descriptor = try MatrixRoomRepositoryDescriptor(
                    id: identifier,
                    repository: remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: cleanName,
                    requestedRef: requestedRef.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let updated = try repositorySet.appending(descriptor)
                let result = try await model.setRepositorySet(updated, for: room)
                if let attachRepositoryRoot {
                    guard FileManager.default.fileExists(
                        atPath: attachRepositoryRoot.appendingPathComponent(".git").path
                    ) else {
                        status("The collection was saved, but the selected local folder is not a Git repository. Choose its repository root to add fallback.", error: true)
                        apply(updated, result: result)
                        return
                    }
                    try bindingStore.save(
                        roomID: room.id,
                        attachmentID: descriptor.id,
                        repositoryRoot: attachRepositoryRoot,
                        buildCommand: attachBuildCommand
                    )
                }
                apply(updated, result: result)
                selectedAttachmentID = descriptor.id
                resetAttachForm()
                loadSelectedBinding()
                status(
                    result == .applied
                        ? "Repository attached. Existing output can open without a build."
                        : "Repository attached. The legacy compatibility mirror still needs repair."
                )
            } catch let error as MatrixRoomRepositorySetError {
                status(repositorySetErrorMessage(error), error: true)
            } catch {
                status("Matrix did not accept the repository collection. No new local binding was saved.", error: true)
            }
        }
    }

    private func makePrimary(_ repository: MatrixRoomRepositoryDescriptor) {
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                let updated = try repositorySet.replacingPrimary(with: repository.id)
                let result = try await model.setRepositorySet(updated, for: room)
                apply(updated, result: result)
                status(
                    result == .applied
                        ? "\(repository.name) is now primary."
                        : "Primary changed; the legacy mirror needs repair."
                )
            } catch {
                status("The primary repository could not be changed.", error: true)
            }
        }
    }

    private func remove(_ repository: MatrixRoomRepositoryDescriptor) {
        pendingRemoval = nil
        isMutating = true
        Task {
            defer { isMutating = false }
            do {
                let updated = try repositorySet.removing(id: repository.id)
                let result = try await model.setRepositorySet(updated, for: room)
                try bindingStore.remove(roomID: room.id, attachmentID: repository.id)
                apply(updated, result: result)
                selectedAttachmentID = updated.primaryID ?? updated.repositories.first?.id
                loadSelectedBinding()
                status(
                    result == .applied
                        ? "\(repository.name) was removed. Its local checkout was not changed."
                        : "Repository removed; the legacy mirror needs repair."
                )
            } catch {
                status("The repository could not be removed safely.", error: true)
            }
        }
    }

    private func apply(
        _ repositorySet: MatrixRoomRepositorySet,
        result: MatrixRoomRepositorySetWriteResult
    ) {
        repositoryState = MatrixRoomRepositoryState(
            repositorySet: repositorySet,
            source: .collection,
            mirrorStatus: result == .applied ? .current : .missing
        )
    }

    private func chooseAttachRepository() {
        chooseRepository(title: "Choose optional local checkout") { url in
            attachRepositoryRoot = url
            attachRepositoryPath = url.path
            if remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { remoteRepositoryURL = await gitOrigin(at: url) ?? "" }
            }
            if repositoryName.isEmpty { repositoryName = url.lastPathComponent }
        }
    }

    private func chooseBindingRepository() {
        chooseRepository(title: "Choose local checkout for \(selectedAttachment?.name ?? room.name)") { url in
            bindingRepositoryRoot = url
            bindingRepositoryPath = url.path
        }
    }

    private func chooseRepository(title: String, completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = "Choose Repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        completion(url.standardizedFileURL)
    }

    private func useTypedAttachPath() {
        let path = NSString(string: attachRepositoryPath).expandingTildeInPath
        attachRepositoryRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private func useTypedBindingPath() {
        let path = NSString(string: bindingRepositoryPath).expandingTildeInPath
        bindingRepositoryRoot = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private func loadSelectedBinding() {
        bindingRepositoryRoot = nil
        bindingRepositoryPath = ""
        bindingBuildCommand = ""
        guard let selectedAttachmentID else { return }
        do {
            if let binding = try bindingStore.load(
                roomID: room.id,
                attachmentID: selectedAttachmentID
            ) {
                bindingRepositoryRoot = binding.repositoryRoot
                bindingRepositoryPath = binding.repositoryRoot.path
                bindingBuildCommand = binding.buildCommand
            }
        } catch {
            status("The saved local permission is unavailable. Choose the checkout again.", error: true)
        }
    }

    private func saveSelectedBinding() {
        guard let selectedAttachmentID, let bindingRepositoryRoot else { return }
        let accessed = bindingRepositoryRoot.startAccessingSecurityScopedResource()
        defer { if accessed { bindingRepositoryRoot.stopAccessingSecurityScopedResource() } }
        do {
            guard FileManager.default.fileExists(
                atPath: bindingRepositoryRoot.appendingPathComponent(".git").path
            ) else {
                status("Choose a Git repository root containing .git.", error: true)
                return
            }
            try bindingStore.save(
                roomID: room.id,
                attachmentID: selectedAttachmentID,
                repositoryRoot: bindingRepositoryRoot,
                buildCommand: bindingBuildCommand
            )
            status("Local fallback and Rebuild are available for \(selectedAttachment?.name ?? "this repository").")
        } catch {
            status("Hypha could not save the local repository permission.", error: true)
        }
    }

    private func removeSelectedBinding() {
        guard let selectedAttachmentID else { return }
        do {
            try bindingStore.remove(roomID: room.id, attachmentID: selectedAttachmentID)
            bindingRepositoryRoot = nil
            bindingRepositoryPath = ""
            bindingBuildCommand = ""
            status("Local fallback removed. The shared repository attachment remains.")
        } catch {
            status("Hypha could not remove the local binding.", error: true)
        }
    }

    private func verifyGitHubAccess() {
        let remote = remoteRepositoryURL
        githubAccessMessage = nil
        isVerifyingGitHubAccess = true
        Task {
            defer { isVerifyingGitHubAccess = false }
            do {
                let access = try await githubConnection.verify(remote: remote)
                githubAccessMessage = "Access confirmed for \(access.fullName) (\(access.isPrivate ? "private" : "public"))."
                githubAccessIsError = false
                if repositoryName.isEmpty { repositoryName = access.fullName.split(separator: "/").last.map(String.init) ?? "" }
            } catch let error as HyphaGitHubRepositoryAccessError {
                githubAccessMessage = githubAccessErrorMessage(error)
                githubAccessIsError = true
            } catch {
                githubAccessMessage = "GitHub access could not be verified."
                githubAccessIsError = true
            }
        }
    }

    private func uniqueAttachmentID(base: String) -> String {
        let identifiers = Set(repositorySet.repositories.map(\.id))
        if !identifiers.contains(base) { return base }
        for suffix in 2...MatrixRoomRepositorySet.maximumAttachmentCount {
            let trimmed = String(base.prefix(max(1, 64 - String(suffix).count - 1)))
            let candidate = "\(trimmed)-\(suffix)"
            if !identifiers.contains(candidate) { return candidate }
        }
        return String(UUID().uuidString.lowercased().prefix(36))
    }

    private func inferredRepositoryName(from remote: String) -> String {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value.split(separator: "/").last
            .map { String($0.split(separator: ":").last ?? $0) } ?? ""
    }

    private func resetAttachForm() {
        selectedGitHubRepositoryID = nil
        remoteRepositoryURL = ""
        repositoryName = ""
        requestedRef = "main"
        attachRepositoryRoot = nil
        attachRepositoryPath = ""
        attachBuildCommand = ""
        githubAccessMessage = nil
    }

    private func gitOrigin(at root: URL) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root.path, "config", "--get", "remote.origin.url"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let value = String(
                    decoding: output.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            } catch {
                return nil
            }
        }.value
    }

    private func status(_ message: String, error: Bool = false) {
        statusMessage = message
        statusIsError = error
    }

    private func repositorySetErrorMessage(_ error: MatrixRoomRepositorySetError) -> String {
        switch error {
        case .attachmentLimitExceeded: "This room already has the maximum 42 repositories."
        case .duplicateAttachmentID: "A repository attachment with that identifier already exists."
        case .invalidRepository: "Enter a valid remote repository URL."
        case .invalidName: "Enter a repository name without control characters."
        case .invalidRequestedRef: "Enter a valid branch, tag, or commit reference."
        case .encodedStateTooLarge: "The repository collection is too large for safe Matrix room state."
        default: "The repository attachment is invalid."
        }
    }

    private func githubAccessErrorMessage(_ error: HyphaGitHubRepositoryAccessError) -> String {
        switch error {
        case .invalidRemote: "Enter a valid github.com repository URL."
        case .invalidToken: "Connect GitHub before verifying private access."
        case .authenticationFailed: "GitHub did not accept the saved connection."
        case .repositoryUnavailable: "The repository was not found or this account cannot read it."
        case .serviceUnavailable: "GitHub access could not be checked right now."
        case .invalidResponse: "GitHub returned an invalid repository response."
        }
    }
}
#endif
