import CryptoKit
import Foundation

public enum HyphaCanvasCapability: String, Codable, CaseIterable, Equatable, Sendable {
    case roomRead = "room.read"
    case repositoriesList = "repositories.list"
    case assetsList = "assets.list"
    case assetsRead = "assets.read"
    case viewerOpen = "viewer.open"
    case layoutStateRead = "layout_state.read"
    case layoutStateWrite = "layout_state.write"
}

public struct HyphaRoomTemplateManifest: Codable, Equatable, Sendable {
    public struct Integrity: Codable, Equatable, Sendable {
        public let algorithm: String
        public let digest: String

        public init(algorithm: String = "sha256", digest: String) {
            self.algorithm = algorithm
            self.digest = digest
        }
    }

    public let schema: String
    public let entry: String
    public let sdkVersion: String
    public let capabilities: [HyphaCanvasCapability]
    public let integrity: Integrity

    public init(
        schema: String = "hypha.room-template.v1",
        entry: String,
        sdkVersion: String = "1",
        capabilities: [HyphaCanvasCapability],
        integrity: Integrity
    ) {
        self.schema = schema
        self.entry = entry
        self.sdkVersion = sdkVersion
        self.capabilities = capabilities
        self.integrity = integrity
    }

    enum CodingKeys: String, CodingKey {
        case schema, entry, capabilities, integrity
        case sdkVersion = "sdk_version"
    }
}

public struct HyphaRoomTemplatePackage: Equatable, Sendable {
    public let root: URL
    public let entry: URL
    public let manifest: HyphaRoomTemplateManifest
    public let digest: String

    public init(
        root: URL,
        entry: URL,
        manifest: HyphaRoomTemplateManifest,
        digest: String
    ) {
        self.root = root
        self.entry = entry
        self.manifest = manifest
        self.digest = digest
    }
}

public enum HyphaRoomTemplateValidationError: Error, Equatable, Sendable {
    case packageUnavailable
    case manifestUnavailable
    case manifestTooLarge
    case invalidManifest
    case unsupportedSchema
    case unsupportedSDK
    case invalidCapability
    case invalidPath
    case unsupportedFileType(String)
    case symbolicLinkForbidden
    case packageLimitExceeded
    case forbiddenContent
    case integrityMismatch
}

public struct HyphaRoomTemplateValidator: Sendable {
    public static let manifestName = "hypha-room-template.json"
    public static let maximumManifestBytes = 64 * 1_024
    public static let maximumFileCount = 512
    public static let maximumFileBytes = 16 * 1_024 * 1_024
    public static let maximumPackageBytes = 64 * 1_024 * 1_024

    private static let allowedExtensions = Set([
        "html", "css", "js", "mjs", "json", "wasm", "png", "jpg", "jpeg",
        "gif", "svg", "webp", "woff", "woff2", "txt",
    ])
    private static let textualExtensions = Set(["html", "css", "js", "mjs", "json", "svg", "txt"])
    private static let forbiddenText = [
        "http://", "https://", "ws://", "wss://", "<base", "<iframe", "<object",
        "<embed", "eval(", "new Function(", "import(", "file://",
    ]

    public init() {}

    public func validate(packageRoot: URL) throws -> HyphaRoomTemplatePackage {
        let root = packageRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw HyphaRoomTemplateValidationError.packageUnavailable
        }
        let manifestURL = root.appendingPathComponent(Self.manifestName)
        guard let manifestData = try? Data(contentsOf: manifestURL, options: [.mappedIfSafe]) else {
            throw HyphaRoomTemplateValidationError.manifestUnavailable
        }
        guard manifestData.count <= Self.maximumManifestBytes else {
            throw HyphaRoomTemplateValidationError.manifestTooLarge
        }
        let manifest: HyphaRoomTemplateManifest
        do {
            manifest = try JSONDecoder().decode(HyphaRoomTemplateManifest.self, from: manifestData)
        } catch {
            throw HyphaRoomTemplateValidationError.invalidManifest
        }
        guard manifest.schema == "hypha.room-template.v1" else {
            throw HyphaRoomTemplateValidationError.unsupportedSchema
        }
        guard manifest.sdkVersion == "1" else {
            throw HyphaRoomTemplateValidationError.unsupportedSDK
        }
        guard Set(manifest.capabilities).count == manifest.capabilities.count else {
            throw HyphaRoomTemplateValidationError.invalidCapability
        }
        guard Self.validRelativePath(manifest.entry), manifest.entry.hasSuffix(".html") else {
            throw HyphaRoomTemplateValidationError.invalidPath
        }
        guard manifest.integrity.algorithm == "sha256",
              manifest.integrity.digest.count == 64,
              manifest.integrity.digest.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw HyphaRoomTemplateValidationError.invalidManifest
        }

        let files = try packageFiles(root: root)
        let relativeFiles = Set(files.map { Self.relativePath($0, root: root) })
        guard relativeFiles.contains(manifest.entry) else {
            throw HyphaRoomTemplateValidationError.invalidPath
        }
        let digest = try Self.packageDigest(files: files, root: root)
        guard digest.caseInsensitiveCompare(manifest.integrity.digest) == .orderedSame else {
            throw HyphaRoomTemplateValidationError.integrityMismatch
        }
        return HyphaRoomTemplatePackage(
            root: root,
            entry: root.appendingPathComponent(manifest.entry),
            manifest: manifest,
            digest: digest
        )
    }

    private func packageFiles(root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw HyphaRoomTemplateValidationError.packageUnavailable
        }
        var files: [URL] = []
        var totalBytes = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true {
                throw HyphaRoomTemplateValidationError.symbolicLinkForbidden
            }
            guard values.isRegularFile == true else { continue }
            let path = Self.relativePath(file, root: root)
            guard Self.validRelativePath(path) else {
                throw HyphaRoomTemplateValidationError.invalidPath
            }
            let ext = file.pathExtension.lowercased()
            guard Self.allowedExtensions.contains(ext) else {
                throw HyphaRoomTemplateValidationError.unsupportedFileType(ext)
            }
            let size = values.fileSize ?? 0
            guard size <= Self.maximumFileBytes else {
                throw HyphaRoomTemplateValidationError.packageLimitExceeded
            }
            totalBytes += size
            guard totalBytes <= Self.maximumPackageBytes,
                  files.count < Self.maximumFileCount else {
                throw HyphaRoomTemplateValidationError.packageLimitExceeded
            }
            if Self.textualExtensions.contains(ext), file.lastPathComponent != Self.manifestName {
                guard let text = String(data: try Data(contentsOf: file), encoding: .utf8),
                      !Self.forbiddenText.contains(where: { text.localizedCaseInsensitiveContains($0) }) else {
                    throw HyphaRoomTemplateValidationError.forbiddenContent
                }
            }
            files.append(file)
        }
        return files.sorted { Self.relativePath($0, root: root) < Self.relativePath($1, root: root) }
    }

    public static func packageDigest(files: [URL], root: URL) throws -> String {
        var hasher = SHA256()
        let ordered = files.sorted { relativePath($0, root: root) < relativePath($1, root: root) }
        for file in ordered where file.lastPathComponent != manifestName {
            let path = relativePath(file, root: root)
            let data = try Data(contentsOf: file, options: [.mappedIfSafe])
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(_ file: URL, root: URL) -> String {
        String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private static func validRelativePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return value.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public struct HyphaRoomTemplateReference: Codable, Equatable, Sendable {
    public static let eventType = "ca.zenithresearch.hypha.room_template"
    public static let stateKey = "active"

    public struct Source: Codable, Equatable, Sendable {
        public let kind: String
        public let repositoryID: String
        public let path: String
        public let resolvedCommit: String
        public let sha256: String

        public init(repositoryID: String, path: String, resolvedCommit: String, sha256: String) {
            self.kind = "repository_asset"
            self.repositoryID = repositoryID
            self.path = path
            self.resolvedCommit = resolvedCommit
            self.sha256 = sha256
        }

        enum CodingKeys: String, CodingKey {
            case kind, path, sha256
            case repositoryID = "repository_id"
            case resolvedCommit = "resolved_commit"
        }
    }

    public let version: Int
    public let source: Source

    public init(source: Source, version: Int = 1) throws {
        guard version == 1,
              source.kind == "repository_asset",
              !source.repositoryID.isEmpty,
              !source.repositoryID.contains("/"),
              !source.repositoryID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !source.path.isEmpty,
              !source.path.hasPrefix("/"),
              !source.path.contains("\\"),
              !source.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              source.path.split(separator: "/", omittingEmptySubsequences: false)
                .allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              [40, 64].contains(source.resolvedCommit.count),
              source.resolvedCommit.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              source.sha256.count == 64,
              source.sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw HyphaRoomTemplateValidationError.invalidManifest
        }
        self.version = version
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case version = "v", source }
}

public indirect enum HyphaCanvasJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: HyphaCanvasJSONValue])
    case array([HyphaCanvasJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: HyphaCanvasJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([HyphaCanvasJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum HyphaCanvasBridgeMethod: String, Codable, CaseIterable, Sendable {
    case roomGetMetadata = "room.get_metadata"
    case repositoriesList = "repositories.list"
    case assetsList = "assets.list"
    case assetsGetMetadata = "assets.get_metadata"
    case assetsGetURL = "assets.get_url"
    case viewerOpen = "viewer.open"
    case layoutStateGet = "layout_state.get"
    case layoutStateSet = "layout_state.set"

    public var capability: HyphaCanvasCapability {
        switch self {
        case .roomGetMetadata: .roomRead
        case .repositoriesList: .repositoriesList
        case .assetsList: .assetsList
        case .assetsGetMetadata, .assetsGetURL: .assetsRead
        case .viewerOpen: .viewerOpen
        case .layoutStateGet: .layoutStateRead
        case .layoutStateSet: .layoutStateWrite
        }
    }
}

public struct HyphaCanvasBridgeRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let method: HyphaCanvasBridgeMethod
    public let params: [String: HyphaCanvasJSONValue]

    public init(version: Int = 1, id: String, method: HyphaCanvasBridgeMethod, params: [String: HyphaCanvasJSONValue] = [:]) {
        self.version = version
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case version = "v", id, method, params }
}

public enum HyphaCanvasBridgeErrorCode: String, Codable, Sendable {
    case invalidRequest = "invalid_request"
    case unsupportedVersion = "unsupported_version"
    case capabilityDenied = "capability_denied"
    case notFound = "not_found"
    case rateLimited = "rate_limited"
    case userGestureRequired = "user_gesture_required"
    case stateTooLarge = "state_too_large"
}

public struct HyphaCanvasBridgeError: Codable, Equatable, Sendable {
    public let code: HyphaCanvasBridgeErrorCode
    public let message: String
}

public struct HyphaCanvasBridgeResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let id: String
    public let ok: Bool
    public let result: HyphaCanvasJSONValue?
    public let error: HyphaCanvasBridgeError?

    public static func success(id: String, result: HyphaCanvasJSONValue) -> Self {
        Self(version: 1, id: id, ok: true, result: result, error: nil)
    }

    public static func failure(id: String, code: HyphaCanvasBridgeErrorCode, message: String) -> Self {
        Self(version: 1, id: id, ok: false, result: nil, error: HyphaCanvasBridgeError(code: code, message: message))
    }
}
