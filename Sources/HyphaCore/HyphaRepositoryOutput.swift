import Foundation

public enum HyphaArtifactViewer: String, Codable, Equatable, Sendable {
    case quickLook
    case web
    case image
    case markdown
    case text
}

public enum HyphaArtifactViewerRegistry {
    public static let viewersByFormat: [String: HyphaArtifactViewer] = [
        "pptx": .quickLook,
        "ppt": .quickLook,
        "ppsx": .quickLook,
        "pdf": .quickLook,
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

    public static func normalize(_ format: String) -> String {
        format.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
    }
}

public enum HyphaArtifactSelectionSource: Equatable, Sendable {
    case manifest
    case discovery
}

public struct HyphaArtifactSelection: Equatable, Sendable {
    public let url: URL
    public let format: String
    public let viewer: HyphaArtifactViewer
    public let source: HyphaArtifactSelectionSource

    public init(url: URL, format: String, viewer: HyphaArtifactViewer, source: HyphaArtifactSelectionSource) {
        self.url = url
        self.format = format
        self.viewer = viewer
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
}

private struct HyphaArtifactOutputManifest: Decodable {
    let viewer: HyphaArtifactViewer?
    let path: String?
    let format: String?
    let build: String?
}

public struct HyphaArtifactOutputResolver: Sendable {
    public init() {}

    public func resolve(outDirectory: URL) throws -> HyphaArtifactSelection? {
        let fileManager = FileManager.default
        let root = outDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw HyphaArtifactOutputError.outputDirectoryUnavailable
        }

        let manifestURL = root.appendingPathComponent("out.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return try resolveManifest(at: manifestURL, root: root)
        }
        return try supportedFiles(in: root).first.map {
            HyphaArtifactSelection(
                url: $0.url,
                format: $0.format,
                viewer: $0.viewer,
                source: .discovery
            )
        }
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

    private func resolveManifest(at manifestURL: URL, root: URL) throws -> HyphaArtifactSelection? {
        let fileManager = FileManager.default
        let manifest = try decodeManifest(at: manifestURL)
        guard manifest.path != nil || manifest.format != nil || manifest.viewer != nil || manifest.build != nil else {
            throw HyphaArtifactOutputError.emptyManifest
        }

        if manifest.path == nil, manifest.format == nil, manifest.viewer == nil {
            return try supportedFiles(in: root).first.map {
                HyphaArtifactSelection(url: $0.url, format: $0.format, viewer: $0.viewer, source: .manifest)
            }
        }

        let selected: (url: URL, format: String, viewer: HyphaArtifactViewer)
        if let path = manifest.path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
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
            guard let mappedViewer = HyphaArtifactViewerRegistry.viewer(forFormat: format) else {
                throw HyphaArtifactOutputError.unsupportedFormat(format)
            }
            if let viewer = manifest.viewer, viewer != mappedViewer {
                throw HyphaArtifactOutputError.viewerFormatMismatch
            }
            selected = (candidate, format, manifest.viewer ?? mappedViewer)
        } else {
            let requestedFormat = manifest.format.map(HyphaArtifactViewerRegistry.normalize)
            let matches = try supportedFiles(in: root).filter { candidate in
                (requestedFormat == nil || candidate.format == requestedFormat)
                    && (manifest.viewer == nil || candidate.viewer == manifest.viewer)
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
            selected = matches[0]
        }

        return HyphaArtifactSelection(
            url: selected.url,
            format: selected.format,
            viewer: selected.viewer,
            source: .manifest
        )
    }

    private func decodeManifest(at manifestURL: URL) throws -> HyphaArtifactOutputManifest {
        do {
            let data = try Data(contentsOf: manifestURL)
            return try JSONDecoder().decode(HyphaArtifactOutputManifest.self, from: data)
        } catch {
            throw HyphaArtifactOutputError.invalidManifest
        }
    }

    private func supportedFiles(in root: URL) throws -> [(url: URL, format: String, viewer: HyphaArtifactViewer)] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HyphaArtifactOutputError.outputDirectoryUnavailable
        }
        var matches: [(url: URL, format: String, viewer: HyphaArtifactViewer)] = []
        for case let candidate as URL in enumerator {
            guard candidate.lastPathComponent != "out.json" else { continue }
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard isContained(resolved, by: root) else { continue }
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let format = HyphaArtifactViewerRegistry.normalize(resolved.pathExtension)
            guard let viewer = HyphaArtifactViewerRegistry.viewer(forFormat: format) else { continue }
            matches.append((resolved, format, viewer))
        }
        return matches.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
    }

    private func isContained(_ candidate: URL, by root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }
}

public enum HyphaRepositoryBuildError: Error, Equatable, Sendable {
    case unavailableOnPlatform
    case invalidRepository
    case launchFailed
    case timedOut
}

public struct HyphaRepositoryBuildResult: Equatable, Sendable {
    public let exitCode: Int32
    public let log: String
    public let artifact: HyphaArtifactSelection?
    public let didRunCommand: Bool

    public init(exitCode: Int32, log: String, artifact: HyphaArtifactSelection?, didRunCommand: Bool) {
        self.exitCode = exitCode
        self.log = log
        self.artifact = artifact
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
            let artifact = FileManager.default.fileExists(atPath: out.path)
                ? try resolver.resolve(outDirectory: out)
                : nil
            return HyphaRepositoryBuildResult(
                exitCode: 0,
                log: "",
                artifact: artifact,
                didRunCommand: false
            )
        }

        let timeoutSeconds = Self.seconds(from: timeout)
        let processResult: (Int32, String) = try await Task.detached(priority: .userInitiated) {
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("hypha-build-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: temporary.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let handle = try? FileHandle(forWritingTo: temporary) else {
                throw HyphaRepositoryBuildError.launchFailed
            }
            defer { try? handle.close() }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", cleanCommand]
            process.currentDirectoryURL = root
            process.standardOutput = handle
            process.standardError = handle
            do {
                try process.run()
            } catch {
                throw HyphaRepositoryBuildError.launchFailed
            }

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning, Date() < deadline {
                try await Task<Never, Never>.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw HyphaRepositoryBuildError.timedOut
            }
            process.waitUntilExit()
            try? handle.synchronize()
            let data = (try? Data(contentsOf: temporary, options: [.mappedIfSafe])) ?? Data()
            let capped = data.prefix(256 * 1_024)
            return (process.terminationStatus, String(decoding: capped, as: UTF8.self))
        }.value

        let artifact: HyphaArtifactSelection?
        if processResult.0 == 0 {
            if FileManager.default.fileExists(atPath: out.path) {
                artifact = try resolver.resolve(outDirectory: out)
            } else {
                artifact = nil
            }
        } else {
            artifact = nil
        }
        return HyphaRepositoryBuildResult(
            exitCode: processResult.0,
            log: processResult.1,
            artifact: artifact,
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
}

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
