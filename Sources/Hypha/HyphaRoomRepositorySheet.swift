#if os(macOS)
import AppKit
import HyphaCore
import SwiftUI

struct HyphaRoomRepositorySheet: View {
    @ObservedObject var model: MatrixAppModel
    let room: MatrixRoomSummary
    @Binding var isPresented: Bool

    @State private var repositoryPath = ""
    @State private var repositoryRoot: URL?
    @State private var buildCommand = ""
    @State private var serverAttachment: MatrixRoomRepositoryAttachment?
    @State private var artifact: HyphaArtifactSelection?
    @State private var buildLog = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true
    @State private var isAttaching = false
    @State private var isBuilding = false
    @State private var showsBuildConfirmation = false
    @State private var scopedURL: URL?
    @State private var isAccessingSecurityScope = false

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()
    private let builder = HyphaRepositoryBuilder()

    private var canAttach: Bool {
        !isAttaching
            && !isBuilding
            && repositoryRoot != nil
            && !buildCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canBuild: Bool {
        !isAttaching
            && !isBuilding
            && serverAttachment != nil
            && repositoryRoot != nil
            && !buildCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Matrix room attachment") {
                    if let serverAttachment {
                        LabeledContent("Repository", value: serverAttachment.name)
                        if let repository = serverAttachment.repository {
                            LabeledContent("Origin", value: repository)
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
                    Text("The local path and build command stay on this Mac. Matrix receives only the repository name, optional Git origin, and the out/ output contract.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)

                    Text("Build command")
                        .font(.headline)
                    TextEditor(text: $buildCommand)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72, maxHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ZenithDesign.Palette.border))
                        .accessibilityIdentifier("matrix.room.repository.command")
                    Text("The command runs from the selected repository root. Its output must be written to <repo>/out. Add out/out.json with viewer, path, or format to make selection explicit and failures visible.")
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

                if !buildLog.isEmpty {
                    Section("Build log") {
                        ScrollView {
                            Text(buildLog)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: artifact == nil ? .infinity : 390)

            if let artifact {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(artifact.url.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Text(artifact.format.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    HyphaArtifactViewerView(selection: artifact)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Button("Close") { isPresented = false }
                Spacer()
                Button(isAttaching ? "Attaching…" : "Attach to room") {
                    attach()
                }
                .disabled(!canAttach)
                .accessibilityIdentifier("matrix.room.repository.attach")

                Button(isBuilding ? "Building…" : "Run build") {
                    showsBuildConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canBuild)
                .accessibilityIdentifier("matrix.room.repository.build")
            }
            .padding()
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 560, idealHeight: 720)
        .task { await load() }
        .onDisappear { endSecurityScope() }
        .confirmationDialog(
            "Run this local build command?",
            isPresented: $showsBuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run build") { runBuild() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Build commands run with your user permissions from the repository root. Review the command before continuing. Hypha will inspect only the out/ directory for viewer output.")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            serverAttachment = try await model.repositoryAttachment(for: room)
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
        artifact = nil
        beginSecurityScope(for: url)
        statusMessage = nil
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
                repository: await gitOrigin(at: repositoryRoot),
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

    private func runBuild() {
        guard let repositoryRoot else { return }
        isBuilding = true
        artifact = nil
        buildLog = ""
        statusMessage = nil
        Task {
            defer { isBuilding = false }
            do {
                let result = try await builder.build(
                    repositoryRoot: repositoryRoot,
                    command: buildCommand
                )
                buildLog = result.log
                guard result.exitCode == 0 else {
                    status("Build failed with exit code \(result.exitCode). Review the build log.", error: true)
                    return
                }
                artifact = result.artifact
                guard let artifact = result.artifact else {
                    status("Build succeeded, but out/ contains no supported output. Add out/out.json with viewer, path, or format to identify the intended output.", error: true)
                    return
                }
                if artifact.source == .discovery {
                    status("Build succeeded. Hypha inferred \(artifact.url.lastPathComponent); add out/out.json to make the viewer selection explicit.")
                } else {
                    status("Build succeeded and out/out.json selected \(artifact.url.lastPathComponent).")
                }
            } catch let error as HyphaArtifactOutputError {
                status("Build succeeded, but out/out.json is invalid: \(artifactErrorMessage(error))", error: true)
            } catch let error as HyphaRepositoryBuildError {
                status(buildErrorMessage(error), error: true)
            } catch {
                status("The build or output viewer failed without producing a usable artifact.", error: true)
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

    private func buildErrorMessage(_ error: HyphaRepositoryBuildError) -> String {
        switch error {
        case .unavailableOnPlatform: "Local repository builds are available on macOS only."
        case .invalidRepository: "Choose a valid Git repository root."
        case .emptyCommand: "Enter a build command."
        case .launchFailed: "Hypha could not launch the local build shell."
        case .timedOut: "The build exceeded the 15-minute limit and was terminated."
        }
    }

    private func artifactErrorMessage(_ error: HyphaArtifactOutputError) -> String {
        switch error {
        case .outputDirectoryUnavailable: "the out directory is unavailable."
        case .invalidManifest: "the file is not valid JSON for the output manifest."
        case .emptyManifest: "define at least one of viewer, path, or format."
        case .pathEscapesOutputDirectory: "path must remain inside out/."
        case .selectedFileUnavailable: "the selected file is missing or ambiguous."
        case let .unsupportedFormat(format): "format \(format) is not supported."
        case .viewerFormatMismatch: "viewer does not match the supported-type map."
        case .ambiguousManifestSelection: "more than one file matches; add path."
        }
    }
}
#endif
