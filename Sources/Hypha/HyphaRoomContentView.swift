#if os(macOS)
import AppKit
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
    @State private var isRebuilding = false
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

                if !artifacts.isEmpty {
                    VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                        HStack {
                            Label("Available outputs", systemImage: "rectangle.grid.1x2")
                                .font(.headline)
                            Spacer()
                            Text("\(artifacts.count)")
                                .font(ZenithDesign.Typography.technical(.caption, weight: .semibold))
                                .foregroundStyle(ZenithDesign.Palette.muted)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: ZenithDesign.Space.x3) {
                                ForEach(artifacts) { selection in
                                    HyphaArtifactGalleryCard(
                                        selection: selection,
                                        isSelected: selection.id == artifact?.id
                                    ) {
                                        selectedArtifactID = selection.id
                                    }
                                }
                            }
                            .padding(.vertical, ZenithDesign.Space.x1)
                        }
                        .accessibilityIdentifier("matrix.room.content.output-gallery")

                        if let artifact {
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
                        Text("No available outputs were found in out/. Add an output asset, or use Rebuild after configuring a build command in Repository settings.")
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
                        Text("Rebuild log")
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
            Button("Rebuild output") { runRebuild(command: pendingBuildCommand) }
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
                Button(isRebuilding ? "Rebuilding…" : "Rebuild") {
                    prepareRebuild()
                }
                .buttonStyle(HyphaButtonStyle(.secondary))
                .disabled(isRebuilding || repositoryRoot == nil)
                .accessibilityIdentifier("matrix.room.content.rebuild")
                if repositoryRoot == nil {
                    Text("Choose the local checkout in Repository settings on this Mac to load or rebuild output.")
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
                loadAvailableOutputs()
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

    private func loadAvailableOutputs() {
        guard let repositoryRoot else { return }
        let out = repositoryRoot.appendingPathComponent("out", isDirectory: true)
        guard FileManager.default.fileExists(atPath: out.path) else { return }
        do {
            let availableArtifacts = try resolver.resolveAll(outDirectory: out)
            artifacts = availableArtifacts
            if let selectedArtifactID,
               availableArtifacts.contains(where: { $0.id == selectedArtifactID }) {
                return
            }
            selectedArtifactID = availableArtifacts.first?.id
        } catch let error as HyphaArtifactOutputError {
            status("Hypha could not read out/out.json: \(artifactErrorMessage(error))", error: true)
        } catch {
            status("Hypha could not inspect this repository's available output.", error: true)
        }
    }

    private func prepareRebuild() {
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
                status("No rebuild command is configured. Add one in Repository settings or out/out.json.", error: true)
            }
        } catch let error as HyphaArtifactOutputError {
            status("Hypha could not read out/out.json: \(artifactErrorMessage(error))", error: true)
        } catch {
            status("Hypha could not inspect this repository's output contract.", error: true)
        }
    }

    private func runRebuild(command: String) {
        guard let repositoryRoot else { return }
        isRebuilding = true
        buildLog = ""
        statusMessage = nil
        Task {
            defer { isRebuilding = false }
            do {
                let result = try await builder.build(repositoryRoot: repositoryRoot, command: command)
                buildLog = result.log
                guard result.exitCode == 0 else {
                    status("Rebuild failed with exit code \(result.exitCode). Review the rebuild log. The previous output remains available.", error: true)
                    return
                }
                guard let selection = result.artifacts.first else {
                    status("Rebuild succeeded, but out/ contains no supported output. The previous output remains selected.", error: true)
                    return
                }
                artifacts = result.artifacts
                selectedArtifactID = selection.id
                let suffix = result.artifacts.count == 1
                    ? ""
                    : " with \(result.artifacts.count - 1) additional output assets"
                status("Rebuilt \(selection.url.lastPathComponent)\(suffix).")
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
        case .outputRollbackFailed: "Hypha could not preserve or restore the previous output safely."
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

private struct HyphaArtifactGalleryCard: View {
    let selection: HyphaArtifactSelection
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isCursorPushed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
                HStack {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(isSelected ? ZenithDesign.Palette.brand : ZenithDesign.Palette.content)
                    Spacer()
                    Text(selection.format.uppercased())
                        .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }

                VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                    Text(selection.title)
                        .font(ZenithDesign.Typography.corporate(.callout, weight: .semibold))
                        .foregroundStyle(ZenithDesign.Palette.content)
                        .lineLimit(2)
                    Text(selection.url.lastPathComponent)
                        .font(ZenithDesign.Typography.technical(.caption2))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(viewerLabel)
                    .font(ZenithDesign.Typography.technical(.caption2, weight: .semibold))
                    .foregroundStyle(isSelected ? ZenithDesign.Palette.brand : ZenithDesign.Palette.muted)
            }
            .frame(width: 212, alignment: .leading)
            .frame(minHeight: 116, alignment: .leading)
            .padding(ZenithDesign.Space.x3)
            .background(isSelected ? ZenithDesign.Palette.brand.opacity(0.08) : ZenithDesign.Palette.baseRaised.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous)
                    .stroke(cardBorder, lineWidth: isFocused || isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: ZenithDesign.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { hovering in
            isHovered = hovering
            updateCursor(hovering: hovering)
        }
        .onDisappear { releaseCursorIfNeeded() }
        .accessibilityLabel("\(selection.title), \(selection.format.uppercased()) output")
        .accessibilityValue(isSelected ? "Selected" : "Available")
        .accessibilityHint("Opens with the \(viewerLabel.lowercased()) viewer")
        .accessibilityIdentifier("matrix.room.content.output-card.\(selection.id)")
    }

    private var cardBorder: Color {
        if isFocused || isSelected { return ZenithDesign.Palette.brand }
        return isHovered ? ZenithDesign.Palette.borderStrong : ZenithDesign.Palette.border
    }

    private var iconName: String {
        switch selection.viewer {
        case .slideshow: "rectangle.on.rectangle.angled"
        case .pdf: "doc.richtext"
        case .web: "globe"
        case .image: "photo"
        case .markdown: "text.document"
        case .text: "doc.plaintext"
        case .quickLook: "doc"
        }
    }

    private var viewerLabel: String {
        switch selection.viewer {
        case .slideshow: "Slideshow"
        case .pdf: "PDF"
        case .web: "Web"
        case .image: "Image"
        case .markdown: "Markdown"
        case .text: "Text"
        case .quickLook: "Quick Look"
        }
    }

    private func updateCursor(hovering: Bool) {
        if hovering {
            guard !isCursorPushed else { return }
            NSCursor.pointingHand.push()
            isCursorPushed = true
        } else {
            releaseCursorIfNeeded()
        }
    }

    private func releaseCursorIfNeeded() {
        guard isCursorPushed else { return }
        NSCursor.pop()
        isCursorPushed = false
    }
}
#endif
