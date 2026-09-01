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
    @State private var pendingRemoval: MatrixRoomRepositoryDescriptor?

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()

    private var repositorySet: MatrixRoomRepositorySet {
        repositoryState.repositorySet
    }

    private var selectedAttachment: MatrixRoomRepositoryDescriptor? {
        guard let selectedAttachmentID else { return nil }
        return repositorySet.repositories.first { $0.id == selectedAttachmentID }
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
            Form {
                Section("Repositories \(repositorySet.repositories.count) / \(MatrixRoomRepositorySet.maximumAttachmentCount)") {
                    if isLoading {
                        ProgressView("Reading room repository state…")
                    } else if repositorySet.repositories.isEmpty {
                        Text("No repositories are attached to this room.")
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    } else {
                        ForEach(repositorySet.repositories) { repository in
                            repositoryRow(repository)
                        }
                    }

                    if repositoryState.mirrorStatus == .missing
                        || repositoryState.mirrorStatus == .divergent {
                        Label(
                            "The legacy single-repository mirror needs repair. The repository collection remains authoritative.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.warning)
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

                Section("Attach repository") {
                    TextField("Repository name", text: $repositoryName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("matrix.room.repositories.name")
                    TextField("https://github.com/owner/repository", text: $remoteRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("matrix.room.repositories.remote")
                        .onChange(of: remoteRepositoryURL) { _, value in
                            githubAccessMessage = nil
                            if repositoryName.isEmpty {
                                repositoryName = inferredRepositoryName(from: value)
                            }
                        }
                    TextField("Branch, tag, or commit", text: $requestedRef)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("matrix.room.repositories.ref")

                    HStack {
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

                    Text("Optional local checkout")
                        .font(.headline)
                    HStack {
                        TextField("Remote-only is supported", text: $attachRepositoryPath)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { useTypedAttachPath() }
                            .accessibilityIdentifier("matrix.room.repositories.attach-local.path")
                        Button("Choose…", action: chooseAttachRepository)
                            .accessibilityIdentifier("matrix.room.repositories.attach-local.choose")
                    }
                    TextEditor(text: $attachBuildCommand)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 52, maxHeight: 90)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ZenithDesign.Palette.border))
                        .accessibilityIdentifier("matrix.room.repositories.attach-local.command")
                    Text("Existing remote output is preferred. Choosing a local checkout enables fallback and the separate, explicitly confirmed Rebuild action; attaching never runs a build.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }

                if let statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .foregroundStyle(
                                statusIsError
                                    ? ZenithDesign.Palette.error
                                    : ZenithDesign.Palette.muted
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
            .padding()
        }
        .frame(minWidth: 760, idealWidth: 940, minHeight: 640, idealHeight: 780)
        .task { await load() }
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
        case .invalidToken: "Connect GitHub in Settings before verifying private access."
        case .authenticationFailed: "GitHub did not accept the saved connection."
        case .repositoryUnavailable: "The repository was not found or this account cannot read it."
        case .serviceUnavailable: "GitHub access could not be checked right now."
        case .invalidResponse: "GitHub returned an invalid repository response."
        }
    }
}
#endif
