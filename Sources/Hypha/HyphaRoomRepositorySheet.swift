#if os(macOS)
import AppKit
import HyphaCore
import SwiftUI

struct HyphaRoomRepositorySheet: View {
    @ObservedObject var model: MatrixAppModel
    @ObservedObject var githubConnection: HyphaGitHubConnectionModel
    let room: MatrixRoomSummary
    @Binding var isPresented: Bool

    @State private var repositoryPath = ""
    @State private var repositoryRoot: URL?
    @State private var remoteRepositoryURL = ""
    @State private var githubAccessMessage: String?
    @State private var githubAccessIsError = false
    @State private var isVerifyingGitHubAccess = false
    @State private var buildCommand = ""
    @State private var serverAttachment: MatrixRoomRepositoryAttachment?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true
    @State private var isAttaching = false
    @State private var scopedURL: URL?
    @State private var isAccessingSecurityScope = false

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()

    private var canAttach: Bool {
        !isAttaching
            && repositoryRoot != nil
            && !remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Matrix room attachment") {
                    if let serverAttachment {
                        LabeledContent("Repository", value: serverAttachment.name)
                        if let repository = serverAttachment.repository {
                            LabeledContent("Remote repository", value: repository)
                        }
                        LabeledContent("Output", value: "\(serverAttachment.outputDirectory)/")
                        LabeledContent("Manifest", value: serverAttachment.manifestPath)
                    } else if isLoading {
                        ProgressView("Reading room state…")
                    } else {
                        Text("No repository is attached to this Matrix room.")
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                }

                Section("Local repository") {
                    HStack {
                        TextField("/path/to/repository", text: $repositoryPath)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { useTypedPath() }
                            .accessibilityIdentifier("matrix.room.repository.path")
                        Button("Choose…", action: chooseRepository)
                            .accessibilityIdentifier("matrix.room.repository.choose")
                    }

                    Text("Remote repository URL")
                        .font(.headline)
                    TextField("https://github.com/owner/repository", text: $remoteRepositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("matrix.room.repository.remote")
                        .onChange(of: remoteRepositoryURL) { _, _ in
                            githubAccessMessage = nil
                        }
                    Text("The remote URL and repository name are shared with the Matrix room. The local path and build command stay on this Mac.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)

                    HStack {
                        Button(isVerifyingGitHubAccess ? "Verifying…" : "Verify private access") {
                            verifyGitHubAccess()
                        }
                        .disabled(
                            isVerifyingGitHubAccess
                                || !githubConnection.isConnected
                                || remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                        .accessibilityIdentifier("matrix.room.repository.github-verify")
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
                    Text(
                        githubConnection.isConnected
                            ? "Private access uses the global GitHub connection managed in Settings. No GitHub credential is stored in this room."
                            : "Connect GitHub in Settings to verify access to a private remote. Public and existing local repositories do not require a GitHub connection."
                    )
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)

                    Text("Build command (optional)")
                        .font(.headline)
                    TextEditor(text: $buildCommand)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72, maxHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ZenithDesign.Palette.border))
                        .accessibilityIdentifier("matrix.room.repository.command")
                    Text("Leave this empty to load an existing output. A command may also be provided as build in out/out.json. Commands run from the repository root and must write output to <repo>/out. Use viewer, path, or format in out.json to select the output.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }

                if let statusMessage {
                    Section("Status") {
                        Text(statusMessage)
                            .foregroundStyle(statusIsError ? ZenithDesign.Palette.error : ZenithDesign.Palette.muted)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("matrix.room.repository.status")
                    }
                }

            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            Divider()
            HStack {
                Button("Close") { isPresented = false }
                Spacer()
                Button(isAttaching ? "Attaching…" : "Attach to room") {
                    attach()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAttach)
                .accessibilityIdentifier("matrix.room.repository.attach")
            }
            .padding()
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 560, idealHeight: 720)
        .task { await load() }
        .onDisappear {
            endSecurityScope()
        }

    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            serverAttachment = try await model.repositoryAttachment(for: room)
            remoteRepositoryURL = serverAttachment?.repository ?? ""
        } catch {
            status("Hypha could not read the room's repository state from Matrix.", error: true)
        }
        do {
            if let binding = try bindingStore.load(roomID: room.id) {
                repositoryRoot = binding.repositoryRoot
                repositoryPath = binding.repositoryRoot.path
                buildCommand = binding.buildCommand
                beginSecurityScope(for: binding.repositoryRoot)
            }
        } catch {
            status("The saved local repository permission is no longer available. Choose the repository again.", error: true)
        }
    }

    private func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Choose repository for \(room.name)"
        panel.prompt = "Choose Repository"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectRepository(url)
    }

    private func useTypedPath() {
        let expanded = NSString(string: repositoryPath).expandingTildeInPath
        selectRepository(URL(fileURLWithPath: expanded, isDirectory: true))
    }

    private func selectRepository(_ url: URL) {
        endSecurityScope()
        repositoryRoot = url.standardizedFileURL
        repositoryPath = url.standardizedFileURL.path
        beginSecurityScope(for: url)
        statusMessage = nil
        if remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                let origin = await gitOrigin(at: url)
                guard repositoryRoot == url.standardizedFileURL,
                      remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                remoteRepositoryURL = origin ?? ""
            }
        }
    }

    private func beginSecurityScope(for url: URL) {
        scopedURL = url
        isAccessingSecurityScope = url.startAccessingSecurityScopedResource()
    }

    private func endSecurityScope() {
        if isAccessingSecurityScope { scopedURL?.stopAccessingSecurityScopedResource() }
        isAccessingSecurityScope = false
        scopedURL = nil
    }

    private func verifyGitHubAccess() {
        let remote = remoteRepositoryURL
        githubAccessMessage = nil
        isVerifyingGitHubAccess = true
        Task {
            defer { isVerifyingGitHubAccess = false }
            do {
                let access = try await githubConnection.verify(remote: remote)
                let visibility = access.isPrivate ? "private" : "public"
                githubAccessMessage = "Access confirmed for \(access.fullName) (\(visibility))."
                githubAccessIsError = false
            } catch let error as HyphaGitHubRepositoryAccessError {
                githubAccessMessage = githubAccessErrorMessage(error)
                githubAccessIsError = true
            } catch {
                githubAccessMessage = "GitHub access could not be verified."
                githubAccessIsError = true
            }
        }
    }

    private func attach() {
        guard let repositoryRoot else { return }
        isAttaching = true
        statusMessage = nil
        Task {
            defer { isAttaching = false }
            guard FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent(".git").path
            ) else {
                status("Choose a Git repository root containing .git.", error: true)
                return
            }
            let attachment = MatrixRoomRepositoryAttachment(
                repository: remoteRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines),
                name: repositoryRoot.lastPathComponent
            )
            do {
                try await model.attachRepository(attachment, to: room)
                try bindingStore.save(
                    roomID: room.id,
                    repositoryRoot: repositoryRoot,
                    buildCommand: buildCommand
                )
                serverAttachment = attachment
                status("Repository attached. The local path and build command remain on this Mac.")
            } catch {
                status("Matrix did not accept the repository attachment. No local binding was saved.", error: true)
            }
        }
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
                let value = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
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


    private func githubAccessErrorMessage(_ error: HyphaGitHubRepositoryAccessError) -> String {
        switch error {
        case .invalidRemote:
            "Enter a valid github.com repository URL."
        case .invalidToken:
            "Connect GitHub in Settings before verifying private access."
        case .authenticationFailed:
            "GitHub did not accept this token for repository access."
        case .repositoryUnavailable:
            "The repository was not found or this token cannot read it."
        case .serviceUnavailable:
            "GitHub access could not be checked right now."
        case .invalidResponse:
            "GitHub returned an invalid repository response."
        }
    }

}
#endif
