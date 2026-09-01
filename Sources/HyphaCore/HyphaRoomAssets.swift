import CryptoKit
import Foundation

public enum HyphaRoomAssetSourceKind: String, Codable, Equatable, Sendable {
    case remote
    case cached
    case localFallback
    case rebuiltLocal
}

public struct HyphaRoomAssetSource: Equatable, Sendable {
    public let kind: HyphaRoomAssetSourceKind
    public let resolvedCommit: String?
    public let isStale: Bool

    public init(
        kind: HyphaRoomAssetSourceKind,
        resolvedCommit: String? = nil,
        isStale: Bool = false
    ) {
        self.kind = kind
        self.resolvedCommit = resolvedCommit
        self.isStale = isStale
    }
}

public struct HyphaRoomAsset: Equatable, Identifiable, Sendable {
    public let id: String
    public let roomID: String
    public let attachmentID: String
    public let repositoryName: String
    public let path: String
    public let title: String
    public let format: String
    public let mediaType: String?
    public let viewer: HyphaArtifactViewer
    public let contentDigest: String
    public let source: HyphaRoomAssetSource
    public let selection: HyphaArtifactSelection

    public init(
        roomID: String,
        attachment: MatrixRoomRepositoryDescriptor,
        path: String,
        contentDigest: String,
        source: HyphaRoomAssetSource,
        selection: HyphaArtifactSelection
    ) {
        var identityHasher = SHA256()
        for component in [roomID, attachment.id, path, contentDigest] {
            identityHasher.update(data: Data(component.utf8))
            identityHasher.update(data: Data([0]))
        }
        self.id = "asset:" + identityHasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        self.roomID = roomID
        self.attachmentID = attachment.id
        self.repositoryName = attachment.name
        self.path = path
        self.title = selection.title
        self.format = selection.format
        self.mediaType = selection.mediaType
        self.viewer = selection.viewer
        self.contentDigest = contentDigest
        self.source = source
        self.selection = selection
    }
}

public enum HyphaRoomAssetSnapshotState: Equatable, Sendable {
    case available
    case stale(reason: String)
    case unavailable(reason: String)
}

public struct HyphaRoomAssetSnapshot: Equatable, Identifiable, Sendable {
    public var id: String { attachment.id }
    public let attachment: MatrixRoomRepositoryDescriptor
    public let assets: [HyphaRoomAsset]
    public let state: HyphaRoomAssetSnapshotState

    public init(
        attachment: MatrixRoomRepositoryDescriptor,
        assets: [HyphaRoomAsset],
        state: HyphaRoomAssetSnapshotState
    ) {
        self.attachment = attachment
        self.assets = assets
        self.state = state
    }

    public func preservingAssetsAsStale(reason: String) -> Self {
        Self(attachment: attachment, assets: assets, state: .stale(reason: reason))
    }
}

public struct HyphaRoomAssetGraph: Equatable, Sendable {
    public let snapshots: [HyphaRoomAssetSnapshot]

    public init(repositorySet: MatrixRoomRepositorySet, snapshots: [HyphaRoomAssetSnapshot]) {
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.attachment.id, $0) })
        self.snapshots = repositorySet.repositories.compactMap { byID[$0.id] }
    }

    public var assets: [HyphaRoomAsset] {
        snapshots.flatMap(\.assets)
    }

    public var isPartial: Bool {
        snapshots.contains { snapshot in
            switch snapshot.state {
            case .available: false
            case .stale, .unavailable: true
            }
        }
    }

    public func snapshot(attachmentID: String) -> HyphaRoomAssetSnapshot? {
        snapshots.first { $0.attachment.id == attachmentID }
    }
}

public enum HyphaRoomAssetIndexError: Error, Equatable, Sendable {
    case outputRootUnavailable
    case pathEscapesOutputRoot
    case duplicateAssetID(String)
    case digestUnavailable
    case fileTooLarge
}

public struct HyphaRoomAssetIndexer: Sendable {
    public static let maximumDigestBytes: Int64 = 512 * 1_024 * 1_024

    public init() {}

    public func snapshot(
        roomID: String,
        attachment: MatrixRoomRepositoryDescriptor,
        outputRoot: URL,
        selections: [HyphaArtifactSelection],
        source: HyphaRoomAssetSource
    ) throws -> HyphaRoomAssetSnapshot {
        let root = outputRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw HyphaRoomAssetIndexError.outputRootUnavailable
        }

        var identifiers = Set<String>()
        let assets = try selections.map { selection in
            let candidate = selection.url.standardizedFileURL.resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(root.path + "/") else {
                throw HyphaRoomAssetIndexError.pathEscapesOutputRoot
            }
            let path = String(candidate.path.dropFirst(root.path.count + 1))
            let id = "\(attachment.id):\(path)"
            guard identifiers.insert(id).inserted else {
                throw HyphaRoomAssetIndexError.duplicateAssetID(id)
            }
            return HyphaRoomAsset(
                roomID: roomID,
                attachment: attachment,
                path: path,
                contentDigest: try Self.sha256(candidate),
                source: source,
                selection: selection
            )
        }
        return HyphaRoomAssetSnapshot(attachment: attachment, assets: assets, state: .available)
    }

    private static func sha256(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw HyphaRoomAssetIndexError.digestUnavailable }
        guard Int64(values.fileSize ?? 0) <= maximumDigestBytes else {
            throw HyphaRoomAssetIndexError.fileTooLarge
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw HyphaRoomAssetIndexError.digestUnavailable
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while true {
                let data = try handle.read(upToCount: 256 * 1_024) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
            }
        } catch {
            throw HyphaRoomAssetIndexError.digestUnavailable
        }
        return "sha256:" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
