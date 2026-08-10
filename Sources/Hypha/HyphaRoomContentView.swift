#if os(macOS)
import HyphaCore
import SwiftUI

struct HyphaRoomContentView: View {
    @ObservedObject var model: MatrixAppModel
    let room: MatrixRoomSummary
    let openRepositorySettings: () -> Void

    @State private var attachment: MatrixRoomRepositoryAttachment?
    @State private var repositoryRoot: URL?
    @State private var buildCommand = ""
    @State private var pendingBuildCommand = ""
    @State private var artifacts: [HyphaArtifactSelection] = []
    @State private var selectedArtifactID: String?
    @State private var buildLog = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true
    @State private var isOpeningOutput = false
    @State private var showsBuildConfirmation = false
    @State private var scopedURL: URL?
    @State private var isAccessingSecurityScope = false

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()
    private let builder = HyphaRepositoryBuilder()
    private let resolver = HyphaArtifactOutputResolver()

    private var artifact: HyphaArtifactSelection? {
        guard let selectedArtifactID else { return artifacts.first }
        return artifacts.first { $0.id == selectedArtifactID } ?? artifacts.first
    }

    private var outputActionLabel: String {
        if isOpeningOutput { return "Working…" }
        return buildCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Open output"
            : "Build and open output"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    Text(room.name)
                        .font(ZenithDesign.Typography.technical(size: 28, weight: .semibold))
                    if let topic = room.topic, !topic.isEmpty {
                        Text(topic)
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    } else {
                        Text("Room dashboard")
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                }

                repositoryCard

                if let artifact {
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                        if artifacts.count > 1 {
                            Picker("Output asset", selection: $selectedArtifactID) {
                                ForEach(artifacts) { selection in
                                    Text(selection.title)
                                        .tag(Optional(selection.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("matrix.room.content.output-asset")
                        }
                        HStack {
                            Text(artifact.title)
                                .font(.headline)
                            Spacer()
                            Text(artifact.format.uppercased())
                                .font(.caption.monospaced())
                                .foregroundStyle(ZenithDesign.Palette.muted)
                        }
                        HyphaArtifactViewerView(selection: artifact)
                            .frame(minHeight: 420)
                    }
                    .padding(ZenithDesign.Space.x3)
                    .background(ZenithDesign.Palette.baseSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(ZenithDesign.Palette.border)
                    }
                    .accessibilityIdentifier("matrix.room.content.viewer")
                } else {
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                        Label("Content", systemImage: "doc.richtext")
                            .font(.headline)
                        Text("Open the repository output here. Repository settings only define the local checkout, build command, and output contract.")
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ZenithDesign.Space.x3)
                    .background(ZenithDesign.Palette.baseSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? ZenithDesign.Palette.error : ZenithDesign.Palette.muted)
                        .accessibilityIdentifier("matrix.room.content.status")
                }

                if !buildLog.isEmpty {
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                        Text("Build log")
                            .font(.headline)
                        Text(buildLog)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(ZenithDesign.Space.x3)
                    .background(ZenithDesign.Palette.baseSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: 1_080, alignment: .leading)
            .padding(ZenithDesign.Space.x4)
        }
        .background(ZenithDesign.Palette.base)
        .task(id: room.id) { await load() }
        .onDisappear { endSecurityScope() }
        .confirmationDialog(
            "Run this local build command?",
            isPresented: $showsBuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run build") { runBuild(command: pendingBuildCommand) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Build commands run with your user permissions from the repository root. Review the command before continuing:\n\n\(pendingBuildCommand)\n\nHypha will inspect only the out/ directory for content output.")
        }
        .accessibilityIdentifier("matrix.room.content")
    }

    @ViewBuilder
    private var repositoryCard: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
            HStack {
                Label("Repository output", systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                Button("Repository settings", action: openRepositorySettings)
                    .accessibilityIdentifier("matrix.room.content.repository-settings")
            }

            if isLoading {
                ProgressView("Loading room content…")
            } else if let attachment {
                LabeledContent("Repository", value: attachment.name)
                if let remote = attachment.repository {
                    LabeledContent("Remote", value: remote)
                }
                LabeledContent("Output contract", value: "\(attachment.outputDirectory)/\(attachment.manifestPath)")
                Button(outputActionLabel) {
                    prepareOutput()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isOpeningOutput || repositoryRoot == nil)
                .accessibilityIdentifier("matrix.room.content.open-output")
                if repositoryRoot == nil {
                    Text("Choose the local checkout in Repository settings on this Mac before opening output.")
                        .font(.caption)
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
            } else {
                Text("No repository is attached to this room.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Button("Configure repository", action: openRepositorySettings)
                    .accessibilityIdentifier("matrix.room.content.configure-repository")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZenithDesign.Space.x3)
        .background(ZenithDesign.Palette.baseSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ZenithDesign.Palette.border)
        }
    }

    private func load() async {
        isLoading = true
        artifacts = []
        selectedArtifactID = nil
        statusMessage = nil
        endSecurityScope()
        defer { isLoading = false }
        do {
            attachment = try await model.repositoryAttachment(for: room)
        } catch {
            attachment = nil
            status("Hypha could not read this room's repository state.", error: true)
        }
        do {
            if let binding = try bindingStore.load(roomID: room.id) {
                repositoryRoot = binding.repositoryRoot
                buildCommand = binding.buildCommand
                beginSecurityScope(for: binding.repositoryRoot)
            } else {
                repositoryRoot = nil
                buildCommand = ""
            }
        } catch {
            repositoryRoot = nil
            buildCommand = ""
            status("The local repository permission is unavailable. Open Repository settings and choose it again.", error: true)
        }
    }

    private func prepareOutput() {
        guard let repositoryRoot else { return }
        let explicitCommand = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitCommand.isEmpty {
            pendingBuildCommand = explicitCommand
            showsBuildConfirmation = true
            return
        }

        let out = repositoryRoot.appendingPathComponent("out", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: out.path),
               let manifestCommand = try resolver.buildCommand(outDirectory: out) {
                pendingBuildCommand = manifestCommand
                showsBuildConfirmation = true
            } else {
                runBuild(command: "")
            }
        } catch let error as HyphaArtifactOutputError {
            status("Hypha could not read out/out.json: \(artifactErrorMessage(error))", error: true)
        } catch {
            status("Hypha could not inspect this repository's output contract.", error: true)
        }
    }

    private func runBuild(command: String) {
        guard let repositoryRoot else { return }
        isOpeningOutput = true
        artifacts = []
        selectedArtifactID = nil
        buildLog = ""
        statusMessage = nil
        Task {
            defer { isOpeningOutput = false }
            do {
                let result = try await builder.build(repositoryRoot: repositoryRoot, command: command)
                buildLog = result.log
                guard result.exitCode == 0 else {
                    status("Build failed with exit code \(result.exitCode). Review the build log.", error: true)
                    return
                }
                guard let selection = result.artifacts.first else {
                    let prefix = result.didRunCommand ? "Build succeeded" : "No build command was provided"
                    status("\(prefix), but out/ contains no supported output.", error: true)
                    return
                }
                artifacts = result.artifacts
                selectedArtifactID = selection.id
                let suffix = result.artifacts.count == 1
                    ? ""
                    : " and found \(result.artifacts.count - 1) additional output assets"
                status("Opened \(selection.url.lastPathComponent)\(suffix) from this room's content view.")
            } catch let error as HyphaArtifactOutputError {
                status("out/out.json is invalid: \(artifactErrorMessage(error))", error: true)
            } catch let error as HyphaRepositoryBuildError {
                status(buildErrorMessage(error), error: true)
            } catch {
                status("The build or output inspection failed without producing usable content.", error: true)
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

    private func status(_ message: String, error: Bool = false) {
        statusMessage = message
        statusIsError = error
    }

    private func buildErrorMessage(_ error: HyphaRepositoryBuildError) -> String {
        switch error {
        case .unavailableOnPlatform: "Local repository builds are available on macOS only."
        case .invalidRepository: "Choose a valid Git repository root."
        case .launchFailed: "Hypha could not launch the local build shell."
        case .timedOut: "The build exceeded the 15-minute limit and was terminated."
        }
    }

    private func artifactErrorMessage(_ error: HyphaArtifactOutputError) -> String {
        switch error {
        case .outputDirectoryUnavailable: "the out directory is unavailable."
        case .invalidManifest: "the file is not valid JSON for the output manifest."
        case .emptyManifest: "define at least one of build, viewer, path, or format."
        case .pathEscapesOutputDirectory: "path must remain inside out/."
        case .selectedFileUnavailable: "the selected file is missing or ambiguous."
        case let .unsupportedFormat(format): "format \(format) is not supported."
        case .viewerFormatMismatch: "viewer does not match the supported-type map."
        case .ambiguousManifestSelection: "more than one file matches; add path."
        case let .unsupportedManifestVersion(version): "manifest version \(version) is not supported."
        case let .viewerValueNotAllowed(viewer): "viewer \(viewer.rawValue) is not allowed in this manifest position."
        case .invalidArtifactDefinition: "a declared artifact has invalid id, path, title, format, media type, or viewer metadata."
        case let .duplicateArtifactID(id): "artifact id \(id) is declared more than once."
        case .primaryArtifactUnavailable: "primary must identify one declared artifact."
        case .legacyPrimaryMismatch: "the legacy path, format, and viewer must mirror the declared primary artifact."
        case .bundleRootUnavailable: "bundle_root must name an existing directory inside out/."
        case .bundleRootDoesNotContainArtifact: "bundle_root must contain the HTML entry point."
        }
    }
}
#endif
