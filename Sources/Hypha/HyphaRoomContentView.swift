#if os(macOS)
import AppKit
import HyphaCore
import SwiftUI

struct HyphaRoomContentView: View {
    @ObservedObject var model: MatrixAppModel
    @ObservedObject var githubConnection: HyphaGitHubConnectionModel
    let room: MatrixRoomSummary
    let openRepositorySettings: () -> Void

    @State private var repositoryState = MatrixRoomRepositoryState.empty
    @State private var contentMode = HyphaRoomContentMode.assets
    @State private var canvasPackage: HyphaRoomTemplatePackage?
    @State private var canvasError: String?
    @State private var canvasSelection = HyphaCanvasSelection.automatic
    @State private var snapshots: [HyphaRoomAssetSnapshot] = []
    @State private var bindings: [String: HyphaRoomRepositoryLocalBinding] = [:]
    @State private var selectedAssetID: String?
    @State private var pendingRebuildRepository: MatrixRoomRepositoryDescriptor?
    @State private var pendingBuildCommand = ""
    @State private var buildLog = ""
    @State private var buildLogRepositoryName = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var rebuildingAttachmentID: String?
    @State private var rebuildTask: Task<Void, Never>?
    @State private var showsBuildConfirmation = false
    @State private var bindingScopedURLs: [URL] = []
    @State private var canvasScopedURL: URL?

    private let bindingStore = HyphaRoomRepositoryLocalBindingStore()
    private let builder = HyphaRepositoryBuilder()
    private let resolver = HyphaArtifactOutputResolver()
    private let indexer = HyphaRoomAssetIndexer()
    private let materializer = HyphaGitHubRepositoryMaterializer()

    private var repositorySet: MatrixRoomRepositorySet { repositoryState.repositorySet }
    private var graph: HyphaRoomAssetGraph {
        HyphaRoomAssetGraph(repositorySet: repositorySet, snapshots: snapshots)
    }
    private var selectedAsset: HyphaRoomAsset? {
        guard let selectedAssetID else { return graph.assets.first }
        return graph.assets.first { $0.id == selectedAssetID } ?? graph.assets.first
    }

    private var selectedPublishableCanvasAsset: HyphaRoomAsset? {
        guard let asset = selectedAsset,
              asset.source.kind == .remote,
              asset.selection.url.lastPathComponent == HyphaRoomTemplateValidator.manifestName,
              asset.source.resolvedCommit != nil else { return nil }
        return asset
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x4) {
                header
                contentModePicker
                selectedContentMode
            }
            .frame(maxWidth: 1_140, alignment: .leading)
            .padding(ZenithDesign.Space.x4)
        }
        .background(ZenithDesign.Palette.base)
        .task(id: room.id) { await loadAssets(refreshReferences: false) }
        .onDisappear {
            rebuildTask?.cancel()
            endSecurityScopes()
        }
        .confirmationDialog(
            "Run this local build command?",
            isPresented: $showsBuildConfirmation,
            titleVisibility: .visible
        ) {
            Button("Rebuild output") {
                if let repository = pendingRebuildRepository {
                    runRebuild(repository: repository, command: pendingBuildCommand)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Build commands run with your user permissions from the selected repository root. Review the command before continuing:\n\n\(pendingBuildCommand)\n\nHypha preserves the previous output if this rebuild fails.")
        }
        .accessibilityIdentifier("matrix.room.content")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
            Text(room.name)
                .font(ZenithDesign.Typography.technical(size: 28, weight: .semibold))
            Text(room.topic?.isEmpty == false ? room.topic! : "Room dashboard")
                .foregroundStyle(ZenithDesign.Palette.muted)
        }
    }

    private var contentModePicker: some View {
        Picker("Room content", selection: $contentMode) {
            ForEach(HyphaRoomContentMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("matrix.room.content.mode")
    }

    @ViewBuilder
    private var selectedContentMode: some View {
        switch contentMode {
        case .canvas:
            canvasSection
        case .assets:
            repositorySummary
            assetsSection
            viewerSection
        case .repositories:
            repositorySummary
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Text("Repository membership, primary selection, refs, and device-local checkout bindings are managed separately from Assets.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Button("Open Repository manager", action: openRepositorySettings)
                    .buttonStyle(HyphaButtonStyle(.primary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ZenithDesign.Space.x3)
            .background(ZenithDesign.Palette.baseSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        statusSection
    }

    @ViewBuilder
    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
            HStack {
                Label("Canvas", systemImage: "square.on.square").font(.headline)
                Spacer()
                Menu("Canvas actions") {
                    if canvasPackage != nil {
                        Button("Open standard room") {
                            endCanvasSecurityScope()
                            canvasSelection = .standard
                            canvasPackage = nil
                            canvasError = nil
                        }
                    }
                    Button("Copy Hermes design brief", action: copyHermesDesignBrief)
                    Button("Preview local template…", action: chooseLocalCanvasPackage)
                    if let asset = selectedPublishableCanvasAsset {
                        Button("Publish selected Canvas Asset") {
                            Task { await publishCanvas(asset: asset) }
                        }
                    }
                }
                .accessibilityIdentifier("matrix.room.canvas.actions")
            }
            if let canvasPackage {
                HStack {
                    Text(canvasSelection == .personal ? "LOCAL PREVIEW" : "SHARED CANVAS")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(ZenithDesign.Palette.brand)
                    Text("SDK \(canvasPackage.manifest.sdkVersion) • \(canvasPackage.manifest.capabilities.count) capabilities • \(canvasPackage.digest.prefix(10))")
                        .font(.caption.monospaced())
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                HyphaRoomCanvasView(package: canvasPackage, room: room, repositorySet: repositorySet, assets: graph.assets) { asset in
                    selectedAssetID = asset.id
                    contentMode = .assets
                }
                .frame(minHeight: 560)
            } else {
                VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                    Text(room.name).font(.title2.weight(.semibold))
                    Text("The standard native room is active. A Hermes-authored HTML/WASM template can be previewed here only after its manifest, digest, paths, capabilities, and offline policy validate.")
                        .foregroundStyle(ZenithDesign.Palette.muted)
                    Text("Native Assets and chat remain available even when a custom Canvas is missing or invalid.")
                        .font(.caption).foregroundStyle(ZenithDesign.Palette.muted)
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
                .padding(ZenithDesign.Space.x4)
                .background(ZenithDesign.Palette.baseRaised.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if let canvasError { Text(canvasError).font(.caption).foregroundStyle(ZenithDesign.Palette.error) }
        }
        .padding(ZenithDesign.Space.x3)
        .background(ZenithDesign.Palette.baseSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ZenithDesign.Palette.border) }
    }

    private var repositorySummary: some View {
        VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
            HStack {
                Label("Repositories", systemImage: "shippingbox").font(.headline)
                Text("\(repositorySet.repositories.count) / \(MatrixRoomRepositorySet.maximumAttachmentCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Spacer()
                Button(isRefreshing ? "Refreshing…" : "Refresh Assets") {
                    Task { await loadAssets(refreshReferences: true) }
                }
                .disabled(isLoading || isRefreshing || repositorySet.repositories.isEmpty)
                .accessibilityIdentifier("matrix.room.content.refresh-assets")
                Button("Repository settings", action: openRepositorySettings)
                    .accessibilityIdentifier("matrix.room.content.repository-settings")
            }
            if isLoading && repositorySet.repositories.isEmpty {
                ProgressView("Reading room repositories…")
            } else if repositorySet.repositories.isEmpty {
                Text("No repositories are attached to this room.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
                Button("Attach a repository", action: openRepositorySettings)
                    .accessibilityIdentifier("matrix.room.content.configure-repository")
            } else {
                ForEach(repositorySet.repositories) { repository in
                    repositoryStatusRow(repository)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ZenithDesign.Space.x3)
        .background(ZenithDesign.Palette.baseSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(ZenithDesign.Palette.border) }
    }

    @ViewBuilder
    private func repositoryStatusRow(_ repository: MatrixRoomRepositoryDescriptor) -> some View {
        let snapshot = graph.snapshot(attachmentID: repository.id)
        HStack(alignment: .top, spacing: ZenithDesign.Space.x2) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: ZenithDesign.Space.x1) {
                    Text(repository.name).font(.callout.weight(.semibold))
                    if repository.id == repositorySet.primaryID {
                        Text("PRIMARY")
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(ZenithDesign.Palette.brand)
                    }
                }
                Text(repository.repository)
                    .font(.caption.monospaced())
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(snapshotDescription(snapshot))
                    .font(.caption)
                    .foregroundStyle(snapshotColor(snapshot))
            }
            Spacer()
            if bindings[repository.id] != nil {
                if rebuildingAttachmentID == repository.id {
                    Button("Cancel Rebuild", role: .cancel) { cancelRebuild() }
                        .buttonStyle(HyphaButtonStyle(.secondary))
                        .accessibilityIdentifier("matrix.room.content.cancel-rebuild.\(repository.id)")
                } else {
                    Button("Rebuild") { prepareRebuild(repository) }
                        .buttonStyle(HyphaButtonStyle(.secondary))
                        .disabled(rebuildingAttachmentID != nil)
                        .accessibilityIdentifier("matrix.room.content.rebuild.\(repository.id)")
                }
            }
        }
        .padding(.vertical, ZenithDesign.Space.x1)
    }

    @ViewBuilder
    private var assetsSection: some View {
        if !graph.assets.isEmpty {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x3) {
                HStack {
                    Label("Assets", systemImage: "rectangle.grid.1x2").font(.headline)
                    Spacer()
                    Text("\(graph.assets.count)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                ForEach(graph.snapshots) { snapshot in
                    if !snapshot.assets.isEmpty {
                        VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                            HStack {
                                Text(snapshot.attachment.name).font(.callout.weight(.semibold))
                                Spacer()
                                Text(snapshot.attachment.outputDirectory + "/")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(ZenithDesign.Palette.muted)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: ZenithDesign.Space.x3) {
                                    ForEach(snapshot.assets) { asset in
                                        HyphaArtifactGalleryCard(
                                            asset: asset,
                                            isSelected: asset.id == selectedAsset?.id
                                        ) { selectedAssetID = asset.id }
                                    }
                                }
                                .padding(.vertical, ZenithDesign.Space.x1)
                            }
                        }
                    }
                }
            }
            .padding(ZenithDesign.Space.x3)
            .background(ZenithDesign.Palette.baseSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ZenithDesign.Palette.border) }
            .accessibilityIdentifier("matrix.room.content.output-gallery")
        } else if !isLoading {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                Label("Assets", systemImage: "doc.richtext").font(.headline)
                Text("No usable output assets are available. Existing remote output is loaded without building; configure a local checkout only for fallback or an explicit Rebuild.")
                    .foregroundStyle(ZenithDesign.Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ZenithDesign.Space.x3)
            .background(ZenithDesign.Palette.baseSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var viewerSection: some View {
        if let selectedAsset {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedAsset.title).font(.headline)
                        Text(selectedAsset.repositoryName + " / " + selectedAsset.path)
                            .font(.caption.monospaced())
                            .foregroundStyle(ZenithDesign.Palette.muted)
                    }
                    Spacer()
                    Text(selectedAsset.format.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                HyphaArtifactViewerView(selection: selectedAsset.selection)
                    .frame(minHeight: 420)
            }
            .padding(ZenithDesign.Space.x3)
            .background(ZenithDesign.Palette.baseSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(ZenithDesign.Palette.border) }
            .accessibilityIdentifier("matrix.room.content.viewer")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(statusIsError ? ZenithDesign.Palette.error : ZenithDesign.Palette.muted)
                .accessibilityIdentifier("matrix.room.content.status")
        }
        if !buildLog.isEmpty {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x1) {
                Text("Rebuild log — \(buildLogRepositoryName)").font(.headline)
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

    private func loadAssets(refreshReferences: Bool) async {
        if refreshReferences { isRefreshing = true } else { isLoading = true }
        statusMessage = nil
        defer { isLoading = false; isRefreshing = false }
        let previous = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.attachment.id, $0) })
        do {
            repositoryState = try await model.repositoryState(for: room)
        } catch {
            snapshots = snapshots.map {
                $0.preservingAssetsAsStale(reason: "Room repository state is temporarily unavailable.")
            }
            status("Hypha could not read the room repository collection. The last successful Assets remain visible as stale.", error: true)
            return
        }

        loadBindings()
        let token = githubConnection.credential()?.token
        var loaded: [HyphaRoomAssetSnapshot] = []
        var resolvedSet = repositorySet
        var resolvedSetChanged = false
        for repository in repositorySet.repositories {
            let requestedRepository = refreshReferences
                ? ((try? repository.requestingCurrentResolution()) ?? repository)
                : repository
            let snapshot = await loadSnapshot(
                repository: requestedRepository,
                token: token,
                binding: bindings[repository.id],
                previous: previous[repository.id]
            )
            loaded.append(snapshot)
            if snapshot.attachment.resolvedCommit != repository.resolvedCommit,
               snapshot.attachment.resolvedCommit != nil,
               let updated = try? resolvedSet.replacing(snapshot.attachment) {
                resolvedSet = updated
                resolvedSetChanged = true
            }
            snapshots = loaded + repositorySet.repositories.dropFirst(loaded.count).compactMap { previous[$0.id] }
            selectFirstAvailableAssetIfNeeded()
        }
        snapshots = loaded
        selectFirstAvailableAssetIfNeeded()

        if resolvedSetChanged {
            do {
                let result = try await model.setRepositorySet(resolvedSet, for: room)
                repositoryState = MatrixRoomRepositoryState(
                    repositorySet: resolvedSet,
                    source: .collection,
                    mirrorStatus: result == .applied ? .current : .missing
                )
                if result == .appliedWithStaleMirror {
                    status("Assets loaded and immutable commits were recorded. The legacy repository mirror still needs repair.", error: true)
                }
            } catch {
                status("Assets loaded, but Matrix did not record the newly resolved immutable commit. Refresh will safely resolve it again.", error: true)
            }
        }
        await loadSharedCanvasIfNeeded()
    }

    private func loadSnapshot(
        repository: MatrixRoomRepositoryDescriptor,
        token: String?,
        binding: HyphaRoomRepositoryLocalBinding?,
        previous: HyphaRoomAssetSnapshot?
    ) async -> HyphaRoomAssetSnapshot {
        if let token {
            do {
                let materialization = try await materializer.materialize(
                    attachment: repository,
                    token: token
                )
                let selections = try resolver.resolveAll(outDirectory: materialization.outputRoot)
                let source = HyphaRoomAssetSource(
                    kind: materialization.sourceKind,
                    resolvedCommit: materialization.attachment.resolvedCommit,
                    isStale: materialization.sourceKind == .cached
                )
                let snapshot = try indexer.snapshot(
                    roomID: room.id,
                    attachment: materialization.attachment,
                    outputRoot: materialization.outputRoot,
                    selections: selections,
                    source: source
                )
                if materialization.sourceKind == .cached {
                    return snapshot.preservingAssetsAsStale(reason: "GitHub is unavailable; showing the last verified commit cache.")
                }
                return snapshot
            } catch {
                // A device-local checkout is the lower-priority fallback below.
            }
        }
        if let binding {
            do {
                let outputRoot = binding.repositoryRoot.appendingPathComponent(
                    repository.outputDirectory,
                    isDirectory: true
                )
                let selections = try resolver.resolveAll(outDirectory: outputRoot)
                return try indexer.snapshot(
                    roomID: room.id,
                    attachment: repository,
                    outputRoot: outputRoot,
                    selections: selections,
                    source: HyphaRoomAssetSource(
                        kind: .localFallback,
                        resolvedCommit: repository.resolvedCommit
                    )
                )
            } catch {
                // Preserve the last known-good snapshot below.
            }
        }
        if let previous, !previous.assets.isEmpty {
            return previous.preservingAssetsAsStale(
                reason: token == nil
                    ? "Connect GitHub or restore this repository's local checkout to refresh."
                    : "The remote output and local fallback are temporarily unavailable."
            )
        }
        return HyphaRoomAssetSnapshot(
            attachment: repository,
            assets: [],
            state: .unavailable(
                reason: token == nil
                    ? "Connect GitHub in Settings, or add a local checkout in Repository settings."
                    : "No valid output is available remotely or from a local fallback."
            )
        )
    }

    private func loadBindings() {
        endBindingSecurityScopes()
        bindings = [:]
        for repository in repositorySet.repositories {
            guard let binding = try? bindingStore.load(
                roomID: room.id,
                attachmentID: repository.id
            ) else { continue }
            bindings[repository.id] = binding
            if binding.repositoryRoot.startAccessingSecurityScopedResource() {
                bindingScopedURLs.append(binding.repositoryRoot)
            }
        }
    }

    private func endSecurityScopes() {
        endBindingSecurityScopes()
        endCanvasSecurityScope()
    }

    private func endBindingSecurityScopes() {
        bindingScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        bindingScopedURLs = []
    }

    private func endCanvasSecurityScope() {
        canvasScopedURL?.stopAccessingSecurityScopedResource()
        canvasScopedURL = nil
    }

    private func selectFirstAvailableAssetIfNeeded() {
        if let selectedAssetID, graph.assets.contains(where: { $0.id == selectedAssetID }) { return }
        selectedAssetID = graph.assets.first?.id
    }

    private func chooseLocalCanvasPackage() {
        let panel = NSOpenPanel()
        panel.title = "Choose a validated Hypha room template package"
        panel.prompt = "Preview Template"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let root = panel.url else { return }
        let accessed = root.startAccessingSecurityScopedResource()
        do {
            let package = try HyphaRoomTemplateValidator().validate(packageRoot: root)
            endCanvasSecurityScope()
            if accessed { canvasScopedURL = root }
            canvasPackage = package
            canvasError = nil
            canvasSelection = .personal
        } catch {
            if accessed { root.stopAccessingSecurityScopedResource() }
            canvasError = "This package failed Hypha\u{27}s template manifest, integrity, path, type, size, or offline-content validation. The current room view remains active."
        }
    }

    private func copyHermesDesignBrief() {
        let packet: [String: Any] = [
            "contract": "hypha.hermes-room-design.v1",
            "profile": "hypha-room-designer",
            "sdk_version": "1",
            "secrets_included": false,
            "room": ["id": room.id, "name": room.name, "topic": room.topic ?? ""],
            "repositories": repositorySet.repositories.map { repository in
                [
                    "id": repository.id,
                    "name": repository.name,
                    "requested_ref": repository.requestedRef,
                    "resolved_commit": repository.resolvedCommit ?? "",
                    "primary": repository.id == repositorySet.primaryID,
                ] as [String: Any]
            },
            "assets": graph.assets.map { asset in
                [
                    "id": asset.id,
                    "repository_id": asset.attachmentID,
                    "path": asset.path,
                    "title": asset.title,
                    "format": asset.format,
                    "viewer": asset.viewer.rawValue,
                ]
            },
            "allowed_capabilities": HyphaCanvasCapability.allCases.map(\.rawValue),
        ]
        guard JSONSerialization.isValidJSONObject(packet),
              let data = try? JSONSerialization.data(withJSONObject: packet, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            status("Hypha could not create the Hermes design brief.", error: true)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        status("Copied a credential-free Hermes design brief with room, repository, Asset, SDK, and capability metadata.")
    }

    private func publishCanvas(asset: HyphaRoomAsset) async {
        do {
            guard asset.source.kind == .remote,
                  let commit = asset.source.resolvedCommit,
                  let repository = repositorySet.repositories.first(where: {
                      $0.id == asset.attachmentID && $0.resolvedCommit == commit
                  }) else {
                status("Only a validated remote Canvas Asset at the room\u{27}s immutable commit can be published.", error: true)
                return
            }
            let package = try HyphaRoomTemplateValidator().validate(
                packageRoot: asset.selection.url.deletingLastPathComponent()
            )
            let source = HyphaRoomTemplateReference.Source(
                repositoryID: repository.id,
                path: asset.path,
                resolvedCommit: commit,
                sha256: package.digest
            )
            let reference = try HyphaRoomTemplateReference(source: source)
            try await model.setTemplateReference(reference, for: room)
            endCanvasSecurityScope()
            canvasSelection = .automatic
            canvasPackage = package
            canvasError = nil
            status("Published the validated Canvas reference to this room. No markup, credential, or local path was written to Matrix.")
        } catch {
            status("Hypha could not publish the selected Canvas. Verify its manifest, package digest, remote source, and room authority.", error: true)
        }
    }

    private func loadSharedCanvasIfNeeded() async {
        guard canvasSelection == .automatic else { return }
        do {
            guard let reference = try await model.templateReference(for: room) else {
                canvasPackage = nil
                canvasError = nil
                return
            }
            guard let repository = repositorySet.repositories.first(where: {
                $0.id == reference.source.repositoryID
                    && $0.resolvedCommit == reference.source.resolvedCommit
            }),
            let asset = graph.assets.first(where: {
                $0.attachmentID == repository.id && $0.path == reference.source.path
            }) else {
                canvasPackage = nil
                canvasError = "The shared Canvas references an unavailable repository commit or Asset. The standard room remains active."
                return
            }
            let package = try HyphaRoomTemplateValidator().validate(
                packageRoot: asset.selection.url.deletingLastPathComponent()
            )
            guard package.digest.caseInsensitiveCompare(reference.source.sha256) == .orderedSame else {
                canvasPackage = nil
                canvasError = "The shared Canvas package digest does not match room state. The standard room remains active."
                return
            }
            canvasPackage = package
            canvasError = nil
        } catch {
            canvasPackage = nil
            canvasError = "Hypha could not validate the shared Canvas reference. The standard room remains active."
        }
    }

    private func prepareRebuild(_ repository: MatrixRoomRepositoryDescriptor) {
        guard let binding = bindings[repository.id] else {
            status("Add a local checkout for \(repository.name) in Repository settings before rebuilding.", error: true)
            return
        }
        let explicitCommand = binding.buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitCommand.isEmpty {
            pendingRebuildRepository = repository
            pendingBuildCommand = explicitCommand
            showsBuildConfirmation = true
            return
        }
        let outputRoot = binding.repositoryRoot.appendingPathComponent(repository.outputDirectory, isDirectory: true)
        do {
            guard FileManager.default.fileExists(atPath: outputRoot.path),
                  let command = try resolver.buildCommand(outDirectory: outputRoot) else {
                status("No rebuild command is configured for \(repository.name). Add one in Repository settings or its output manifest.", error: true)
                return
            }
            pendingRebuildRepository = repository
            pendingBuildCommand = command
            showsBuildConfirmation = true
        } catch let error as HyphaArtifactOutputError {
            status("Hypha could not read \(repository.name)'s output manifest: \(artifactErrorMessage(error))", error: true)
        } catch {
            status("Hypha could not inspect \(repository.name)'s output contract.", error: true)
        }
    }

    private func runRebuild(repository: MatrixRoomRepositoryDescriptor, command: String) {
        guard let binding = bindings[repository.id] else { return }
        rebuildingAttachmentID = repository.id
        buildLog = ""
        buildLogRepositoryName = repository.name
        statusMessage = nil
        rebuildTask = Task {
            defer {
                rebuildingAttachmentID = nil
                rebuildTask = nil
            }
            do {
                let result = try await builder.build(
                    repositoryRoot: binding.repositoryRoot,
                    command: command,
                    outputDirectory: repository.outputDirectory
                )
                buildLog = result.log
                guard result.exitCode == 0 else {
                    status("Rebuild failed with exit code \(result.exitCode). The previous Assets remain available.", error: true)
                    return
                }
                guard !result.artifacts.isEmpty else {
                    status("Rebuild succeeded, but produced no recognized Assets. The previous Assets remain available.", error: true)
                    return
                }
                let outputRoot = binding.repositoryRoot.appendingPathComponent(repository.outputDirectory, isDirectory: true)
                let snapshot = try indexer.snapshot(
                    roomID: room.id,
                    attachment: repository,
                    outputRoot: outputRoot,
                    selections: result.artifacts,
                    source: HyphaRoomAssetSource(
                        kind: .rebuiltLocal,
                        resolvedCommit: repository.resolvedCommit
                    )
                )
                replaceSnapshot(snapshot)
                selectedAssetID = snapshot.assets.first?.id
                status("Rebuilt \(repository.name) with \(snapshot.assets.count) available Asset\(snapshot.assets.count == 1 ? "" : "s").")
            } catch is CancellationError {
                status("Rebuild cancelled. The previous Assets were restored.")
            } catch let error as HyphaArtifactOutputError {
                status("The rebuilt output manifest is invalid: \(artifactErrorMessage(error))", error: true)
            } catch let error as HyphaRepositoryBuildError {
                status(buildErrorMessage(error), error: true)
            } catch {
                status("The rebuild failed without replacing the previous Assets.", error: true)
            }
        }
    }

    private func cancelRebuild() {
        rebuildTask?.cancel()
        status("Cancelling rebuild and restoring the previous Assets…")
    }

    private func replaceSnapshot(_ replacement: HyphaRoomAssetSnapshot) {
        var byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        byID[replacement.id] = replacement
        snapshots = repositorySet.repositories.compactMap { byID[$0.id] }
    }

    private func snapshotDescription(_ snapshot: HyphaRoomAssetSnapshot?) -> String {
        guard let snapshot else { return "Waiting for output…" }
        switch snapshot.state {
        case .available:
            return "\(snapshot.assets.count) Asset\(snapshot.assets.count == 1 ? "" : "s") • \(sourceLabel(snapshot.assets.first?.source.kind))"
        case let .stale(reason):
            return "\(snapshot.assets.count) stale Asset\(snapshot.assets.count == 1 ? "" : "s") • \(reason)"
        case let .unavailable(reason):
            return reason
        }
    }

    private func snapshotColor(_ snapshot: HyphaRoomAssetSnapshot?) -> Color {
        guard let snapshot else { return ZenithDesign.Palette.muted }
        switch snapshot.state {
        case .available: return ZenithDesign.Palette.muted
        case .stale: return ZenithDesign.Palette.warning
        case .unavailable: return ZenithDesign.Palette.error
        }
    }

    private func sourceLabel(_ source: HyphaRoomAssetSourceKind?) -> String {
        switch source {
        case .remote: "Remote"
        case .cached: "Cached"
        case .localFallback: "Local fallback"
        case .rebuiltLocal: "Rebuilt locally"
        case nil: "Unavailable"
        }
    }

    private func status(_ message: String, error: Bool = false) {
        statusMessage = message
        statusIsError = error
    }

    private func buildErrorMessage(_ error: HyphaRepositoryBuildError) -> String {
        switch error {
        case .unavailableOnPlatform: "Local repository builds are available on macOS only."
        case .invalidRepository: "Choose a valid Git repository root and output directory."
        case .launchFailed: "Hypha could not launch the local build shell."
        case .timedOut: "The build exceeded the 15-minute limit and was terminated."
        case .outputRollbackFailed: "Hypha could not preserve or restore the previous output safely."
        }
    }

    private func artifactErrorMessage(_ error: HyphaArtifactOutputError) -> String {
        switch error {
        case .outputDirectoryUnavailable: "the output directory is unavailable."
        case .invalidManifest: "the file is not valid JSON for the output manifest."
        case .emptyManifest: "define at least one output Asset."
        case .pathEscapesOutputDirectory: "paths must remain inside the configured output root."
        case .selectedFileUnavailable: "the selected file is missing or ambiguous."
        case let .unsupportedFormat(format): "format \(format) is not supported."
        case .viewerFormatMismatch: "viewer does not match the supported-type map."
        case .ambiguousManifestSelection: "more than one file matches; add a path."
        case let .unsupportedManifestVersion(version): "manifest version \(version) is not supported."
        case let .viewerValueNotAllowed(viewer): "viewer \(viewer.rawValue) is not allowed here."
        case .invalidArtifactDefinition: "an Asset has invalid id, path, title, format, media type, or viewer metadata."
        case let .duplicateArtifactID(id): "Asset id \(id) is declared more than once."
        case .primaryArtifactUnavailable: "primary must identify one declared Asset."
        case .legacyPrimaryMismatch: "the legacy path, format, and viewer must mirror the primary Asset."
        case .bundleRootUnavailable: "bundle_root must name an existing directory inside the output root."
        case .bundleRootDoesNotContainArtifact: "bundle_root must contain the HTML entry point."
        case let .unsupportedAssetDiscoveryMode(mode): "asset discovery mode \(mode) is not supported."
        }
    }
}

private enum HyphaRoomContentMode: String, CaseIterable, Identifiable {
    case canvas
    case assets
    case repositories

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var systemImage: String {
        switch self {
        case .canvas: "square.on.square"
        case .assets: "rectangle.grid.1x2"
        case .repositories: "shippingbox"
        }
    }
}

private enum HyphaCanvasSelection {
    case automatic
    case standard
    case personal
}

private struct HyphaArtifactGalleryCard: View {
    let asset: HyphaRoomAsset
    let isSelected: Bool
    let action: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    @State private var isCursorPushed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ZenithDesign.Space.x2) {
                HStack {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(isSelected ? ZenithDesign.Palette.brand : ZenithDesign.Palette.content)
                    Spacer()
                    Text(asset.format.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(ZenithDesign.Palette.muted)
                }
                Text(asset.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ZenithDesign.Palette.content)
                    .lineLimit(2)
                Text(asset.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(ZenithDesign.Palette.muted)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    Text(viewerLabel)
                    Spacer()
                    Text(sourceLabel)
                }
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(isSelected ? ZenithDesign.Palette.brand : ZenithDesign.Palette.muted)
            }
            .frame(width: 230, alignment: .leading)
            .frame(minHeight: 132, alignment: .leading)
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
        .accessibilityLabel("\(asset.title), \(asset.format.uppercased()) Asset")
        .accessibilityValue(isSelected ? "Selected" : sourceLabel)
        .accessibilityHint("Opens with the \(viewerLabel.lowercased()) viewer")
        .accessibilityIdentifier("matrix.room.content.output-card.\(asset.id)")
    }

    private var cardBorder: Color {
        if isFocused || isSelected { return ZenithDesign.Palette.brand }
        return isHovered ? ZenithDesign.Palette.borderStrong : ZenithDesign.Palette.border
    }

    private var iconName: String {
        switch asset.viewer {
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
        switch asset.viewer {
        case .slideshow: "Slideshow"
        case .pdf: "PDF"
        case .web: "Web"
        case .image: "Image"
        case .markdown: "Markdown"
        case .text: "Text"
        case .quickLook: "Quick Look"
        }
    }

    private var sourceLabel: String {
        switch asset.source.kind {
        case .remote: "Remote"
        case .cached: "Cached"
        case .localFallback: "Local"
        case .rebuiltLocal: "Rebuilt"
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
