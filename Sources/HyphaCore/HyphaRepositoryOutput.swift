import Foundation
#if os(macOS)
import Darwin
#endif

public enum HyphaArtifactViewer: String, Codable, Equatable, Sendable {
    case quickLook
    case pdf
    case web
    case image
    case markdown
    case text
    case slideshow

    public var isLegacyManifestValue: Bool {
        self != .slideshow
    }

    public var isOldClientSafeMirrorValue: Bool {
        switch self {
        case .quickLook, .web, .image, .text:
            true
        case .pdf, .markdown, .slideshow:
            false
        }
    }
}

public enum HyphaArtifactViewerRegistry {
    public static let viewersByFormat: [String: HyphaArtifactViewer] = [
        "pptx": .slideshow,
        "ppt": .quickLook,
        "ppsx": .slideshow,
        "pdf": .pdf,
        "html": .web,
        "htm": .web,
        "png": .image,
        "jpg": .image,
        "jpeg": .image,
        "gif": .image,
        "heic": .image,
        "txt": .text,
        "md": .markdown,
        "markdown": .markdown,
        "json": .text,
        "log": .text,
    ]

    public static func viewer(forFormat format: String) -> HyphaArtifactViewer? {
        viewersByFormat[normalize(format)]
    }

    public static func isCompatible(viewer: HyphaArtifactViewer, forFormat format: String) -> Bool {
        let normalizedFormat = normalize(format)
        if ["pptx", "ppsx", "pdf"].contains(normalizedFormat), viewer == .quickLook {
            return true
        }
        return viewer == self.viewer(forFormat: normalizedFormat)
    }

    public static func normalizedViewer(
        forFormat format: String,
        declaredViewer: HyphaArtifactViewer? = nil
    ) -> HyphaArtifactViewer? {
        let normalizedFormat = normalize(format)
        guard let defaultViewer = viewer(forFormat: normalizedFormat) else { return nil }
        if ["pptx", "ppsx"].contains(normalizedFormat) {
            return .slideshow
        }
        return declaredViewer ?? defaultViewer
    }

    public static func oldClientSafeMirror(forFormat format: String) -> HyphaArtifactViewer? {
        switch normalize(format) {
        case "ppt", "pptx", "ppsx", "pdf":
            .quickLook
        case "html", "htm":
            .web
        case "png", "jpg", "jpeg", "gif", "heic":
            .image
        case "md", "markdown", "txt", "json", "log":
            .text
        default:
            nil
        }
    }

    public static func normalize(_ format: String) -> String {
        format.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
    }
}

public enum HyphaArtifactSelectionSource: Equatable, Sendable {
    case manifest
    case discovery
}

public struct HyphaArtifactSelection: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let format: String
    public let mediaType: String?
    public let viewer: HyphaArtifactViewer
    public let bundleRoot: URL?
    public let source: HyphaArtifactSelectionSource

    public init(
        id: String? = nil,
        title: String? = nil,
        url: URL,
        format: String,
        mediaType: String? = nil,
        viewer: HyphaArtifactViewer,
        bundleRoot: URL? = nil,
        source: HyphaArtifactSelectionSource
    ) {
        self.id = id ?? url.lastPathComponent
        self.title = title ?? url.lastPathComponent
        self.url = url
        self.format = format
        self.mediaType = mediaType
        self.viewer = viewer
        self.bundleRoot = bundleRoot
        self.source = source
    }
}

public enum HyphaArtifactOutputError: Error, Equatable, Sendable {
    case outputDirectoryUnavailable
    case invalidManifest
    case emptyManifest
    case pathEscapesOutputDirectory
    case selectedFileUnavailable
    case unsupportedFormat(String)
    case viewerFormatMismatch
    case ambiguousManifestSelection
    case unsupportedManifestVersion(Int)
    case viewerValueNotAllowed(HyphaArtifactViewer)
    case invalidArtifactDefinition
    case duplicateArtifactID(String)
    case primaryArtifactUnavailable
    case legacyPrimaryMismatch
    case bundleRootUnavailable
    case bundleRootDoesNotContainArtifact
}

private struct HyphaArtifactOutputManifestEntry: Decodable {
    let id: String?
    let title: String?
    let path: String?
    let format: String?
    let mediaType: String?
    let viewer: HyphaArtifactViewer?
    let bundleRoot: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case path
        case format
        case mediaType = "media_type"
        case viewer
        case bundleRoot = "bundle_root"
    }
}

private struct HyphaArtifactOutputManifest: Decodable {
    let version: Int?
    let primary: String?
    let artifacts: [HyphaArtifactOutputManifestEntry]?
    let viewer: HyphaArtifactViewer?
    let path: String?
    let format: String?
    let build: String?
}

public struct HyphaArtifactOutputResolver: Sendable {
    public init() {}

    public func resolve(outDirectory: URL) throws -> HyphaArtifactSelection? {
        try resolveAll(outDirectory: outDirectory).first
    }

    public func resolveAll(outDirectory: URL) throws -> [HyphaArtifactSelection] {
        let fileManager = FileManager.default
        let root = outDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HyphaArtifactOutputError.outputDirectoryUnavailable
        }

        let manifestURL = root.appendingPathComponent("out.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return try discoveredSelections(in: root)
        }
        let manifest = try decodeManifest(at: manifestURL)
        if let version = manifest.version, version != 1, version != 2 {
            throw HyphaArtifactOutputError.unsupportedManifestVersion(version)
        }
        if manifest.version == 2 || manifest.artifacts != nil {
            guard manifest.version == 2 else {
                throw HyphaArtifactOutputError.invalidArtifactDefinition
            }
            if let viewer = manifest.viewer, !viewer.isOldClientSafeMirrorValue {
                throw HyphaArtifactOutputError.viewerValueNotAllowed(viewer)
            }
            return try resolveDeclaredArtifacts(manifest, root: root)
        }
        if let viewer = manifest.viewer, !viewer.isLegacyManifestValue {
            throw HyphaArtifactOutputError.viewerValueNotAllowed(viewer)
        }
        let discovered = try discoveredSelections(in: root)
        guard let primary = try resolveLegacyManifest(
            manifest,
            root: root,
            discovered: discovered
        ) else { return [] }
        return [primary] + discovered.filter { $0.url != primary.url }
    }

    public func buildCommand(outDirectory: URL) throws -> String? {
        let fileManager = FileManager.default
        let root = outDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HyphaArtifactOutputError.outputDirectoryUnavailable
        }
        let manifestURL = root.appendingPathComponent("out.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let command = try decodeManifest(at: manifestURL).build?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return command?.isEmpty == false ? command : nil
    }

    private func resolveLegacyManifest(
        _ manifest: HyphaArtifactOutputManifest,
        root: URL,
        discovered: [HyphaArtifactSelection]
    ) throws -> HyphaArtifactSelection? {
        let fileManager = FileManager.default
        guard manifest.path != nil || manifest.format != nil || manifest.viewer != nil || manifest.build != nil else {
            throw HyphaArtifactOutputError.emptyManifest
        }

        if manifest.path == nil, manifest.format == nil, manifest.viewer == nil {
            return discovered.first.map {
                HyphaArtifactSelection(
                    id: $0.id,
                    title: $0.title,
                    url: $0.url,
                    format: $0.format,
                    viewer: $0.viewer,
                    source: .manifest
                )
            }
        }

        let selected: (url: URL, format: String, viewer: HyphaArtifactViewer)
        if let path = manifest.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            guard isValidRelativePath(path, strict: false) else {
                throw HyphaArtifactOutputError.pathEscapesOutputDirectory
            }
            let candidate = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
            guard isContained(candidate, by: root) else {
                throw HyphaArtifactOutputError.pathEscapesOutputDirectory
            }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                throw HyphaArtifactOutputError.selectedFileUnavailable
            }
            let format = HyphaArtifactViewerRegistry.normalize(
                manifest.format ?? candidate.pathExtension
            )
            guard isValidFormat(format) else {
                throw HyphaArtifactOutputError.unsupportedFormat(format)
            }
            guard let mappedViewer = HyphaArtifactViewerRegistry.viewer(forFormat: format) else {
                throw HyphaArtifactOutputError.unsupportedFormat(format)
            }
            if let viewer = manifest.viewer,
               !HyphaArtifactViewerRegistry.isCompatible(viewer: viewer, forFormat: format) {
                throw HyphaArtifactOutputError.viewerFormatMismatch
            }
            selected = (
                candidate,
                format,
                HyphaArtifactViewerRegistry.normalizedViewer(
                    forFormat: format,
                    declaredViewer: manifest.viewer
                ) ?? mappedViewer
            )
        } else {
            let requestedFormat = manifest.format.map(HyphaArtifactViewerRegistry.normalize)
            if let requestedFormat, !isValidFormat(requestedFormat) {
                throw HyphaArtifactOutputError.unsupportedFormat(requestedFormat)
            }
            let matches = discovered.filter { candidate in
                (requestedFormat == nil || candidate.format == requestedFormat)
                    && (manifest.viewer == nil
                        || HyphaArtifactViewerRegistry.isCompatible(
                            viewer: manifest.viewer!,
                            forFormat: candidate.format
                        ))
            }
            guard !matches.isEmpty else {
                if let requestedFormat {
                    guard HyphaArtifactViewerRegistry.viewer(forFormat: requestedFormat) != nil else {
                        throw HyphaArtifactOutputError.unsupportedFormat(requestedFormat)
                    }
                }
                throw HyphaArtifactOutputError.selectedFileUnavailable
            }
            guard matches.count == 1 else {
                throw HyphaArtifactOutputError.ambiguousManifestSelection
            }
            let match = matches[0]
            selected = (
                match.url,
                match.format,
                HyphaArtifactViewerRegistry.normalizedViewer(
                    forFormat: match.format,
                    declaredViewer: manifest.viewer
                ) ?? match.viewer
            )
        }

        return HyphaArtifactSelection(
            id: relativePath(for: selected.url, root: root),
            url: selected.url,
            format: selected.format,
            viewer: selected.viewer,
            source: .manifest
        )
    }

    private func resolveDeclaredArtifacts(
        _ manifest: HyphaArtifactOutputManifest,
        root: URL
    ) throws -> [HyphaArtifactSelection] {
        guard let entries = manifest.artifacts, !entries.isEmpty else {
            throw HyphaArtifactOutputError.emptyManifest
        }
        guard entries.count <= 64 else {
            throw HyphaArtifactOutputError.invalidArtifactDefinition
        }

        var identifiers = Set<String>()
        var selections: [HyphaArtifactSelection] = []
        selections.reserveCapacity(entries.count)
        for entry in entries {
            let selection = try resolveDeclaredArtifact(entry, root: root)
            guard identifiers.insert(selection.id).inserted else {
                throw HyphaArtifactOutputError.duplicateArtifactID(selection.id)
            }
            selections.append(selection)
        }

        let primaryID: String
        if let rawPrimary = manifest.primary {
            let requestedPrimary = rawPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard requestedPrimary == rawPrimary, isValidArtifactID(requestedPrimary) else {
                throw HyphaArtifactOutputError.primaryArtifactUnavailable
            }
            primaryID = requestedPrimary
        } else if selections.count == 1 {
            primaryID = selections[0].id
        } else {
            throw HyphaArtifactOutputError.primaryArtifactUnavailable
        }
        guard let primaryIndex = selections.firstIndex(where: { $0.id == primaryID }) else {
            throw HyphaArtifactOutputError.primaryArtifactUnavailable
        }

        let primary = selections[primaryIndex]
        try validateLegacyPrimaryMirror(manifest, primary: primary, root: root)
        selections.remove(at: primaryIndex)
        return [primary] + selections
    }

    private func resolveDeclaredArtifact(
        _ entry: HyphaArtifactOutputManifestEntry,
        root: URL
    ) throws -> HyphaArtifactSelection {
        let fileManager = FileManager.default
        guard let rawID = entry.id, let rawPath = entry.path else {
            throw HyphaArtifactOutputError.invalidArtifactDefinition
        }
        let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id == rawID, path == rawPath,
              isValidArtifactID(id), isValidRelativePath(path, strict: true) else {
            throw HyphaArtifactOutputError.invalidArtifactDefinition
        }

        let candidate = root.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isContained(candidate, by: root) else {
            throw HyphaArtifactOutputError.pathEscapesOutputDirectory
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw HyphaArtifactOutputError.selectedFileUnavailable
        }

        if let declaredFormat = entry.format, !isValidDeclaredFormat(declaredFormat) {
            throw HyphaArtifactOutputError.invalidArtifactDefinition
        }
        let format = HyphaArtifactViewerRegistry.normalize(entry.format ?? candidate.pathExtension)
        guard isValidFormat(format),
              let mappedViewer = HyphaArtifactViewerRegistry.viewer(forFormat: format) else {
            throw HyphaArtifactOutputError.unsupportedFormat(format)
        }
        if let viewer = entry.viewer,
           !HyphaArtifactViewerRegistry.isCompatible(viewer: viewer, forFormat: format) {
            throw HyphaArtifactOutputError.viewerFormatMismatch
        }
        let viewer = HyphaArtifactViewerRegistry.normalizedViewer(
            forFormat: format,
            declaredViewer: entry.viewer
        ) ?? mappedViewer

        let title: String
        if let declaredTitle = entry.title {
            let cleanTitle = declaredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanTitle == declaredTitle, !cleanTitle.isEmpty, cleanTitle.count <= 120 else {
                throw HyphaArtifactOutputError.invalidArtifactDefinition
            }
            title = cleanTitle
        } else {
            title = candidate.deletingPathExtension().lastPathComponent
        }

        let mediaType: String?
        if let declaredMediaType = entry.mediaType {
            let cleanMediaType = declaredMediaType.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleanMediaType == declaredMediaType, isValidMediaType(cleanMediaType) else {
                throw HyphaArtifactOutputError.invalidArtifactDefinition
            }
            mediaType = cleanMediaType.lowercased()
        } else {
            mediaType = nil
        }

        let bundleRoot: URL?
        if let declaredBundleRoot = entry.bundleRoot {
            guard viewer == .web else {
                throw HyphaArtifactOutputError.invalidArtifactDefinition
            }
            guard isValidRelativePath(declaredBundleRoot, strict: true) else {
                throw HyphaArtifactOutputError.bundleRootUnavailable
            }
            let resolvedBundleRoot = root.appendingPathComponent(declaredBundleRoot)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard isContained(resolvedBundleRoot, by: root) else {
                throw HyphaArtifactOutputError.pathEscapesOutputDirectory
            }
            var isBundleDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: resolvedBundleRoot.path,
                isDirectory: &isBundleDirectory
            ), isBundleDirectory.boolValue else {
                throw HyphaArtifactOutputError.bundleRootUnavailable
            }
            guard isContained(candidate, by: resolvedBundleRoot) else {
                throw HyphaArtifactOutputError.bundleRootDoesNotContainArtifact
            }
            bundleRoot = resolvedBundleRoot
        } else {
            bundleRoot = viewer == .web ? candidate.deletingLastPathComponent() : nil
        }

        return HyphaArtifactSelection(
            id: id,
            title: title,
            url: candidate,
            format: format,
            mediaType: mediaType,
            viewer: viewer,
            bundleRoot: bundleRoot,
            source: .manifest
        )
    }

    private func validateLegacyPrimaryMirror(
        _ manifest: HyphaArtifactOutputManifest,
        primary: HyphaArtifactSelection,
        root: URL
    ) throws {
        guard let legacyPath = manifest.path, isValidRelativePath(legacyPath, strict: true) else {
            throw HyphaArtifactOutputError.legacyPrimaryMismatch
        }
        let legacyURL = root.appendingPathComponent(legacyPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isContained(legacyURL, by: root), legacyURL == primary.url else {
            throw HyphaArtifactOutputError.legacyPrimaryMismatch
        }
        if let legacyFormat = manifest.format {
            guard isValidDeclaredFormat(legacyFormat) else {
                throw HyphaArtifactOutputError.legacyPrimaryMismatch
            }
            let normalizedFormat = HyphaArtifactViewerRegistry.normalize(legacyFormat)
            guard isValidFormat(normalizedFormat), normalizedFormat == primary.format else {
                throw HyphaArtifactOutputError.legacyPrimaryMismatch
            }
        }
        if let legacyViewer = manifest.viewer {
            guard legacyViewer == HyphaArtifactViewerRegistry.oldClientSafeMirror(
                forFormat: primary.format
            ) else {
                throw HyphaArtifactOutputError.legacyPrimaryMismatch
            }
        }
    }

    private func decodeManifest(at manifestURL: URL) throws -> HyphaArtifactOutputManifest {
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(HyphaArtifactOutputManifest.self, from: data)
        } catch {
            throw HyphaArtifactOutputError.invalidManifest
        }
    }

    private func supportedFiles(
        in root: URL
    ) throws -> [(id: String, url: URL, format: String, viewer: HyphaArtifactViewer)] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HyphaArtifactOutputError.outputDirectoryUnavailable
        }
        var matches: [(id: String, url: URL, format: String, viewer: HyphaArtifactViewer)] = []
        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent != "out.json" else { continue }
            let id = relativePath(for: candidate.standardizedFileURL, root: root)
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard isContained(resolved, by: root) else { continue }
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let format = HyphaArtifactViewerRegistry.normalize(resolved.pathExtension)
            guard let viewer = HyphaArtifactViewerRegistry.viewer(forFormat: format) else { continue }
            matches.append((id, resolved, format, viewer))
        }
        return matches.sorted { $0.id < $1.id }
    }

    private func discoveredSelections(in root: URL) throws -> [HyphaArtifactSelection] {
        try supportedFiles(in: root).map {
            HyphaArtifactSelection(
                id: $0.id,
                url: $0.url,
                format: $0.format,
                viewer: $0.viewer,
                source: .discovery
            )
        }
    }

    private func isContained(_ candidate: URL, by root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }

    private func relativePath(for candidate: URL, root: URL) -> String {
        String(candidate.path.dropFirst(root.path.count + 1))
    }

    private func isValidArtifactID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64, let first = id.first,
              first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return id.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    private func isValidRelativePath(_ path: String, strict: Bool) -> Bool {
        guard !path.isEmpty, path.count <= 1_024, !path.hasPrefix("/"),
              !path.contains("\0"), !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else { return false }
        if strict {
            guard path == path.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            let hasDrivePrefix = path.count >= 2
                && path.first?.isASCII == true
                && path.first?.isLetter == true
                && path[path.index(after: path.startIndex)] == ":"
            return !path.contains("\\")
                && !hasDrivePrefix
                && components.allSatisfy { !$0.isEmpty && $0 != "." }
        }
        return true
    }

    private func isValidFormat(_ format: String) -> Bool {
        guard !format.isEmpty, format.count <= 32, let first = format.first,
              first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.+_-")
        return format.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    private func isValidDeclaredFormat(_ format: String) -> Bool {
        guard !format.isEmpty, format.count <= 32, !format.hasPrefix("."),
              format == format.trimmingCharacters(in: .whitespacesAndNewlines),
              let first = format.first, first.isASCII, first.isLetter || first.isNumber else {
            return false
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.+_-")
        return format.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    private func isValidMediaType(_ mediaType: String) -> Bool {
        guard mediaType.count <= 127 else { return false }
        let parts = mediaType.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$&^_.+-")
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && allowed.contains($0) }
        }
    }
}

public enum HyphaRepositoryBuildError: Error, Equatable, Sendable {
    case unavailableOnPlatform
    case invalidRepository
    case launchFailed
    case timedOut
    case outputRollbackFailed
}

public struct HyphaRepositoryBuildResult: Equatable, Sendable {
    public let exitCode: Int32
    public let log: String
    public let artifacts: [HyphaArtifactSelection]
    public let didRunCommand: Bool

    public var artifact: HyphaArtifactSelection? { artifacts.first }

    public init(exitCode: Int32, log: String, artifacts: [HyphaArtifactSelection], didRunCommand: Bool) {
        self.exitCode = exitCode
        self.log = log
        self.artifacts = artifacts
        self.didRunCommand = didRunCommand
    }
}

public struct HyphaRoomRepositoryLocalBinding: Equatable, Sendable {
    public let repositoryRoot: URL
    public let buildCommand: String

    public init(repositoryRoot: URL, buildCommand: String) {
        self.repositoryRoot = repositoryRoot
        self.buildCommand = buildCommand
    }
}

public enum HyphaRoomRepositoryLocalBindingError: Error, Equatable, Sendable {
    case unavailableOnPlatform
    case emptyRoomID
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case persistenceFailed
}

public final class HyphaRoomRepositoryLocalBindingStore {
    private struct Record: Codable {
        let bookmark: Data
        let buildCommand: String
    }

    private static let defaultsKey = "ca.zenithresearch.hypha.room-repository-bindings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(roomID: String, repositoryRoot: URL, buildCommand: String) throws {
#if os(macOS)
        let cleanRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommand = buildCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRoomID.isEmpty else { throw HyphaRoomRepositoryLocalBindingError.emptyRoomID }
        let bookmark: Data
        do {
            bookmark = try repositoryRoot.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw HyphaRoomRepositoryLocalBindingError.bookmarkCreationFailed
        }
        var records = try loadRecords()
        records[cleanRoomID] = Record(bookmark: bookmark, buildCommand: cleanCommand)
        do {
            defaults.set(try JSONEncoder().encode(records), forKey: Self.defaultsKey)
        } catch {
            throw HyphaRoomRepositoryLocalBindingError.persistenceFailed
        }
#else
        throw HyphaRoomRepositoryLocalBindingError.unavailableOnPlatform
#endif
    }

    public func load(roomID: String) throws -> HyphaRoomRepositoryLocalBinding? {
#if os(macOS)
        let cleanRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRoomID.isEmpty else { throw HyphaRoomRepositoryLocalBindingError.emptyRoomID }
        guard let record = try loadRecords()[cleanRoomID] else { return nil }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: record.bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw HyphaRoomRepositoryLocalBindingError.bookmarkResolutionFailed
        }
        if isStale {
            try save(roomID: cleanRoomID, repositoryRoot: url, buildCommand: record.buildCommand)
        }
        return HyphaRoomRepositoryLocalBinding(repositoryRoot: url, buildCommand: record.buildCommand)
#else
        throw HyphaRoomRepositoryLocalBindingError.unavailableOnPlatform
#endif
    }

    public func remove(roomID: String) throws {
        var records = try loadRecords()
        records.removeValue(forKey: roomID)
        defaults.set(try JSONEncoder().encode(records), forKey: Self.defaultsKey)
    }

    private func loadRecords() throws -> [String: Record] {
        guard let data = defaults.data(forKey: Self.defaultsKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: Record].self, from: data)
        } catch {
            throw HyphaRoomRepositoryLocalBindingError.persistenceFailed
        }
    }
}

public struct HyphaRepositoryBuilder: Sendable {
    private let resolver: HyphaArtifactOutputResolver

    public init(resolver: HyphaArtifactOutputResolver = HyphaArtifactOutputResolver()) {
        self.resolver = resolver
    }

    public func build(
        repositoryRoot: URL,
        command: String,
        timeout: Duration = .seconds(900)
    ) async throws -> HyphaRepositoryBuildResult {
#if os(macOS)
        let root = repositoryRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) else {
            throw HyphaRepositoryBuildError.invalidRepository
        }
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = root.appendingPathComponent("out", isDirectory: true)
        if cleanCommand.isEmpty {
            let artifacts = FileManager.default.fileExists(atPath: out.path)
                ? try resolver.resolveAll(outDirectory: out)
                : []
            return HyphaRepositoryBuildResult(
                exitCode: 0,
                log: "",
                artifacts: artifacts,
                didRunCommand: false
            )
        }

        let snapshot: HyphaRepositoryOutputSnapshot
        do {
            snapshot = try HyphaRepositoryOutputSnapshot.capture(outputURL: out)
        } catch {
            throw HyphaRepositoryBuildError.outputRollbackFailed
        }
        defer { snapshot.discard() }

        let timeoutSeconds = Self.seconds(from: timeout)
        let processResult: (Int32, String)
        do {
            processResult = try await Task.detached(priority: .userInitiated) {
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent("hypha-build-\(UUID().uuidString).log")
                FileManager.default.createFile(atPath: temporary.path, contents: nil)
                defer { try? FileManager.default.removeItem(at: temporary) }
                guard let handle = try? FileHandle(forWritingTo: temporary) else {
                    throw HyphaRepositoryBuildError.launchFailed
                }
                defer { try? handle.close() }

                let terminationStatus = try await Self.runProcessGroup(
                    command: cleanCommand,
                    currentDirectoryURL: root,
                    standardOutputFileDescriptor: handle.fileDescriptor,
                    timeoutSeconds: timeoutSeconds
                )
                try? handle.synchronize()
                let data = (try? Data(contentsOf: temporary, options: [.mappedIfSafe])) ?? Data()
                let capped = data.prefix(256 * 1_024)
                return (terminationStatus, String(decoding: capped, as: UTF8.self))
            }.value
        } catch {
            try Self.restore(snapshot)
            throw error
        }

        if processResult.0 != 0 {
            try Self.restore(snapshot)
        }

        let artifacts: [HyphaArtifactSelection]
        if processResult.0 == 0 {
            do {
                if FileManager.default.fileExists(atPath: out.path) {
                    artifacts = try resolver.resolveAll(outDirectory: out)
                } else {
                    artifacts = []
                }
            } catch {
                try Self.restore(snapshot)
                throw error
            }
        } else {
            artifacts = []
        }
        if processResult.0 == 0, artifacts.isEmpty, snapshot.hadOutput {
            try Self.restore(snapshot)
        }
        return HyphaRepositoryBuildResult(
            exitCode: processResult.0,
            log: processResult.1,
            artifacts: artifacts,
            didRunCommand: true
        )
#else
        throw HyphaRepositoryBuildError.unavailableOnPlatform
#endif
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

#if os(macOS)
    private static func restore(_ snapshot: HyphaRepositoryOutputSnapshot) throws {
        do {
            try snapshot.restore()
        } catch {
            throw HyphaRepositoryBuildError.outputRollbackFailed
        }
    }

    private static func runProcessGroup(
        command: String,
        currentDirectoryURL: URL,
        standardOutputFileDescriptor: Int32,
        timeoutSeconds: TimeInterval
    ) async throws -> Int32 {
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw HyphaRepositoryBuildError.launchFailed
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            standardOutputFileDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            standardOutputFileDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawn_file_actions_addchdir(&fileActions, currentDirectoryURL.path) == 0 else {
            throw HyphaRepositoryBuildError.launchFailed
        }

        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else {
            throw HyphaRepositoryBuildError.launchFailed
        }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else {
            throw HyphaRepositoryBuildError.launchFailed
        }

        let arguments = ["/bin/zsh", "-lc", command]
        let mutableArguments = arguments.map { strdup($0) }
        defer { mutableArguments.forEach { free($0) } }
        var argumentVector = mutableArguments + [nil]
        var processID: pid_t = 0
        let spawnResult = posix_spawn(
            &processID,
            "/bin/zsh",
            &fileActions,
            &attributes,
            &argumentVector,
            environ
        )
        guard spawnResult == 0 else {
            throw HyphaRepositoryBuildError.launchFailed
        }

        var waitStatus: Int32 = 0
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let waitResult = waitpid(processID, &waitStatus, WNOHANG)
            if waitResult == processID {
                return exitStatus(from: waitStatus)
            }
            if waitResult == -1 {
                _ = kill(-processID, SIGKILL)
                throw HyphaRepositoryBuildError.launchFailed
            }
            try? await Task<Never, Never>.sleep(for: .milliseconds(50))
            if Task.isCancelled {
                _ = kill(-processID, SIGTERM)
                try? await Task<Never, Never>.sleep(for: .milliseconds(200))
                _ = kill(-processID, SIGKILL)
                while waitpid(processID, &waitStatus, 0) == -1, errno == EINTR {}
                throw CancellationError()
            }
        }

        _ = kill(-processID, SIGTERM)
        try? await Task<Never, Never>.sleep(for: .milliseconds(200))
        _ = kill(-processID, SIGKILL)
        while waitpid(processID, &waitStatus, 0) == -1, errno == EINTR {}
        throw HyphaRepositoryBuildError.timedOut
    }

    private static func exitStatus(from waitStatus: Int32) -> Int32 {
        let terminationSignal = waitStatus & 0x7f
        if terminationSignal == 0 {
            return (waitStatus >> 8) & 0xff
        }
        return 128 + terminationSignal
    }
#endif
}

#if os(macOS)
private struct HyphaRepositoryOutputSnapshot: @unchecked Sendable {
    let outputURL: URL
    let snapshotRoot: URL
    let hadOutput: Bool

    static func capture(outputURL: URL) throws -> Self {
        let fileManager = FileManager.default
        let snapshotRoot = fileManager.temporaryDirectory
            .appendingPathComponent("hypha-output-snapshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)
            let hadOutput = fileManager.fileExists(atPath: outputURL.path)
            if hadOutput {
                try fileManager.copyItem(at: outputURL, to: snapshotRoot.appendingPathComponent("out"))
            }
            return Self(outputURL: outputURL, snapshotRoot: snapshotRoot, hadOutput: hadOutput)
        } catch {
            try? fileManager.removeItem(at: snapshotRoot)
            throw error
        }
    }

    func restore() throws {
        let fileManager = FileManager.default
        if hadOutput {
            let restoreCandidate = outputURL.deletingLastPathComponent()
                .appendingPathComponent(".hypha-output-restore-\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: restoreCandidate) }
            try fileManager.copyItem(at: snapshotRoot.appendingPathComponent("out"), to: restoreCandidate)
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
            try fileManager.moveItem(at: restoreCandidate, to: outputURL)
        } else if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
    }

    func discard() {
        try? FileManager.default.removeItem(at: snapshotRoot)
    }
}
#endif

public struct MatrixRoomRepositoryAttachment: Codable, Equatable, Sendable {
    public static let eventType = "ca.zenithresearch.hypha.repository"
    public static let stateKey = "primary"

    public let version: Int
    public let repository: String?
    public let name: String
    public let outputDirectory: String
    public let manifestPath: String

    public init(
        repository: String? = nil,
        name: String,
        version: Int = 1,
        outputDirectory: String = "out",
        manifestPath: String = "out.json"
    ) {
        self.version = version
        self.repository = repository
        self.name = name
        self.outputDirectory = outputDirectory
        self.manifestPath = manifestPath
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case repository
        case name
        case outputDirectory = "output_directory"
        case manifestPath = "manifest"
    }

    public func encodedContent() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decodeStateEvent(_ data: Data) throws -> MatrixRoomRepositoryAttachment {
        struct Envelope: Decodable { let content: MatrixRoomRepositoryAttachment }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.content
        }
        return try JSONDecoder().decode(MatrixRoomRepositoryAttachment.self, from: data)
    }
}
