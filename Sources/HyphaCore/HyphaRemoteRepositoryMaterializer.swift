import CryptoKit
import Foundation

public enum HyphaRemoteRepositoryMaterializationError: Error, Equatable, Sendable {
    case unsupportedRepository
    case invalidReference
    case invalidCommit
    case providerUnavailable
    case invalidProviderResponse
    case outputUnavailable
    case outputLimitExceeded
    case invalidOutput
    case cacheUnavailable
}

public struct HyphaRepositoryMaterialization: Equatable, Sendable {
    public let attachment: MatrixRoomRepositoryDescriptor
    public let outputRoot: URL
    public let sourceKind: HyphaRoomAssetSourceKind

    public init(
        attachment: MatrixRoomRepositoryDescriptor,
        outputRoot: URL,
        sourceKind: HyphaRoomAssetSourceKind
    ) {
        self.attachment = attachment
        self.outputRoot = outputRoot
        self.sourceKind = sourceKind
    }
}

public struct HyphaGitHubRepositoryMaterializer: Sendable {
    public static let maximumFileCount = 2_048
    public static let maximumFileBytes = 25 * 1_024 * 1_024
    public static let maximumTotalBytes = 256 * 1_024 * 1_024
    private static let maximumResponseBytes = 36 * 1_024 * 1_024

    private struct CommitResponse: Decodable {
        let sha: String
    }

    private struct TreeResponse: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
            let sha: String
            let size: Int?
        }

        let tree: [Entry]
        let truncated: Bool
    }

    private struct BlobResponse: Decodable {
        let content: String
        let encoding: String
        let size: Int
    }

    private struct CacheReceipt: Codable {
        let repository: String
        let resolvedCommit: String
        let outputDirectory: String
        let manifestPath: String
    }

    private let transport: any HyphaGitHubRepositoryAccessTransport
    private let resolver: HyphaArtifactOutputResolver
    private let classifier = HyphaArtifactContentClassifier()

    public init(
        transport: any HyphaGitHubRepositoryAccessTransport = HyphaGitHubURLSessionTransport(),
        resolver: HyphaArtifactOutputResolver = HyphaArtifactOutputResolver()
    ) {
        self.transport = transport
        self.resolver = resolver
    }

    public func materialize(
        attachment: MatrixRoomRepositoryDescriptor,
        token: String,
        cacheRoot: URL? = nil
    ) async throws -> HyphaRepositoryMaterialization {
        let reference: (owner: String, repository: String)
        do {
            reference = try HyphaGitHubRepositoryAccessClient.repositoryReference(attachment.repository)
        } catch {
            throw HyphaRemoteRepositoryMaterializationError.unsupportedRepository
        }
        let root = try cacheRoot ?? Self.defaultCacheRoot()
        let commit: String
        if let resolved = attachment.resolvedCommit {
            commit = resolved
        } else {
            commit = try await resolveCommit(
                reference: reference,
                requestedRef: attachment.requestedRef,
                token: token
            )
        }
        let resolvedAttachment: MatrixRoomRepositoryDescriptor
        do {
            resolvedAttachment = try attachment.resolving(commit: commit)
        } catch {
            throw HyphaRemoteRepositoryMaterializationError.invalidCommit
        }
        let cacheDirectory = root.appendingPathComponent(
            Self.cacheKey(for: resolvedAttachment),
            isDirectory: true
        )
        let cachedOutput = cacheDirectory.appendingPathComponent(
            resolvedAttachment.outputDirectory,
            isDirectory: true
        )

        do {
            return try await fetchAndPromote(
                attachment: resolvedAttachment,
                reference: reference,
                token: token,
                cacheRoot: root,
                finalDirectory: cacheDirectory
            )
        } catch {
            if Self.validCache(
                directory: cacheDirectory,
                outputRoot: cachedOutput,
                attachment: resolvedAttachment,
                resolver: resolver
            ) {
                return HyphaRepositoryMaterialization(
                    attachment: resolvedAttachment,
                    outputRoot: cachedOutput,
                    sourceKind: .cached
                )
            }
            throw error
        }
    }

    private func resolveCommit(
        reference: (owner: String, repository: String),
        requestedRef: String,
        token: String
    ) async throws -> String {
        let encodedRef = requestedRef.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(
                CharacterSet(charactersIn: "._-")
            )
        )
        guard let encodedRef,
              let url = URL(
                string: "https://api.github.com/repos/\(reference.owner)/\(reference.repository)/commits/\(encodedRef)"
              ) else {
            throw HyphaRemoteRepositoryMaterializationError.invalidReference
        }
        let data = try await responseData(url: url, token: token)
        guard let response = try? JSONDecoder().decode(CommitResponse.self, from: data),
              [40, 64].contains(response.sha.count),
              response.sha.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw HyphaRemoteRepositoryMaterializationError.invalidProviderResponse
        }
        return response.sha
    }

    private func fetchAndPromote(
        attachment: MatrixRoomRepositoryDescriptor,
        reference: (owner: String, repository: String),
        token: String,
        cacheRoot: URL,
        finalDirectory: URL
    ) async throws -> HyphaRepositoryMaterialization {
        guard let commit = attachment.resolvedCommit,
              let treeURL = URL(
                string: "https://api.github.com/repos/\(reference.owner)/\(reference.repository)/git/trees/\(commit)?recursive=1"
              ) else {
            throw HyphaRemoteRepositoryMaterializationError.invalidCommit
        }
        let treeData = try await responseData(url: treeURL, token: token)
        guard let tree = try? JSONDecoder().decode(TreeResponse.self, from: treeData),
              !tree.truncated else {
            throw HyphaRemoteRepositoryMaterializationError.invalidProviderResponse
        }
        let prefix = attachment.outputDirectory + "/"
        let entries = tree.tree.filter { $0.path.hasPrefix(prefix) && $0.type == "blob" }
        guard !entries.isEmpty else {
            throw HyphaRemoteRepositoryMaterializationError.outputUnavailable
        }
        guard entries.count <= Self.maximumFileCount,
              entries.allSatisfy({ Self.validRepositoryPath($0.path) }) else {
            throw HyphaRemoteRepositoryMaterializationError.outputLimitExceeded
        }
        let declaredTotal = entries.reduce(0) { $0 + ($1.size ?? 0) }
        guard entries.allSatisfy({ ($0.size ?? 0) <= Self.maximumFileBytes }),
              declaredTotal <= Self.maximumTotalBytes else {
            throw HyphaRemoteRepositoryMaterializationError.outputLimitExceeded
        }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        } catch {
            throw HyphaRemoteRepositoryMaterializationError.cacheUnavailable
        }
        let staging = cacheRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            var actualTotal = 0
            for entry in entries {
                let data = try await fetchBlob(
                    reference: reference,
                    sha: entry.sha,
                    token: token
                )
                guard data.count <= Self.maximumFileBytes else {
                    throw HyphaRemoteRepositoryMaterializationError.outputLimitExceeded
                }
                actualTotal += data.count
                guard actualTotal <= Self.maximumTotalBytes else {
                    throw HyphaRemoteRepositoryMaterializationError.outputLimitExceeded
                }
                let destination = staging.appendingPathComponent(entry.path).standardizedFileURL
                guard destination.path.hasPrefix(staging.path + "/") else {
                    throw HyphaRemoteRepositoryMaterializationError.invalidOutput
                }
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: destination, options: [.atomic])
            }
            let outputRoot = staging.appendingPathComponent(attachment.outputDirectory, isDirectory: true)
            let selections = try resolver.resolveAll(outDirectory: outputRoot)
            guard !selections.isEmpty else {
                throw HyphaRemoteRepositoryMaterializationError.invalidOutput
            }
            try classifier.validate(selections)
            let receipt = CacheReceipt(
                repository: attachment.repository,
                resolvedCommit: commit,
                outputDirectory: attachment.outputDirectory,
                manifestPath: attachment.manifestPath
            )
            try JSONEncoder().encode(receipt).write(
                to: staging.appendingPathComponent("materialization.json"),
                options: [.atomic]
            )
            if fileManager.fileExists(atPath: finalDirectory.path) {
                let existingOutput = finalDirectory.appendingPathComponent(
                    attachment.outputDirectory,
                    isDirectory: true
                )
                if Self.validCache(
                    directory: finalDirectory,
                    outputRoot: existingOutput,
                    attachment: attachment,
                    resolver: resolver
                ) {
                    try fileManager.removeItem(at: staging)
                    return HyphaRepositoryMaterialization(
                        attachment: attachment,
                        outputRoot: existingOutput,
                        sourceKind: .remote
                    )
                }
                try fileManager.removeItem(at: finalDirectory)
            }
            try fileManager.moveItem(at: staging, to: finalDirectory)
        } catch let error as HyphaRemoteRepositoryMaterializationError {
            try? fileManager.removeItem(at: staging)
            throw error
        } catch is HyphaArtifactOutputError {
            try? fileManager.removeItem(at: staging)
            throw HyphaRemoteRepositoryMaterializationError.invalidOutput
        } catch is HyphaArtifactContentClassificationError {
            try? fileManager.removeItem(at: staging)
            throw HyphaRemoteRepositoryMaterializationError.invalidOutput
        } catch {
            try? fileManager.removeItem(at: staging)
            throw HyphaRemoteRepositoryMaterializationError.cacheUnavailable
        }
        return HyphaRepositoryMaterialization(
            attachment: attachment,
            outputRoot: finalDirectory.appendingPathComponent(
                attachment.outputDirectory,
                isDirectory: true
            ),
            sourceKind: .remote
        )
    }

    private func fetchBlob(
        reference: (owner: String, repository: String),
        sha: String,
        token: String
    ) async throws -> Data {
        guard let url = URL(
            string: "https://api.github.com/repos/\(reference.owner)/\(reference.repository)/git/blobs/\(sha)"
        ) else {
            throw HyphaRemoteRepositoryMaterializationError.invalidProviderResponse
        }
        let data = try await responseData(url: url, token: token)
        guard let blob = try? JSONDecoder().decode(BlobResponse.self, from: data),
              blob.encoding == "base64",
              blob.size <= Self.maximumFileBytes,
              let decoded = Data(
                base64Encoded: blob.content,
                options: [.ignoreUnknownCharacters]
              ),
              decoded.count == blob.size else {
            throw HyphaRemoteRepositoryMaterializationError.invalidProviderResponse
        }
        return decoded
    }

    private func responseData(url: URL, token: String) async throws -> Data {
        let request = HyphaGitHubRepositoryAccessClient.authorizedRequest(url: url, token: token)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw HyphaRemoteRepositoryMaterializationError.providerUnavailable
        }
        guard response.statusCode == 200 else {
            throw HyphaRemoteRepositoryMaterializationError.providerUnavailable
        }
        guard data.count <= Self.maximumResponseBytes else {
            throw HyphaRemoteRepositoryMaterializationError.outputLimitExceeded
        }
        return data
    }

    private static func cacheKey(for attachment: MatrixRoomRepositoryDescriptor) -> String {
        let value = [
            attachment.repository,
            attachment.resolvedCommit ?? "",
            attachment.outputDirectory,
            attachment.manifestPath,
        ].joined(separator: "\n")
        return SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func validCache(
        directory: URL,
        outputRoot: URL,
        attachment: MatrixRoomRepositoryDescriptor,
        resolver: HyphaArtifactOutputResolver
    ) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("materialization.json")),
              let receipt = try? JSONDecoder().decode(CacheReceipt.self, from: data),
              receipt.repository == attachment.repository,
              receipt.resolvedCommit == attachment.resolvedCommit,
              receipt.outputDirectory == attachment.outputDirectory,
              receipt.manifestPath == attachment.manifestPath,
              let artifacts = try? resolver.resolveAll(outDirectory: outputRoot),
              (try? HyphaArtifactContentClassifier().validate(artifacts)) != nil,
              !artifacts.isEmpty else { return false }
        return true
    }

    private static func validRepositoryPath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func defaultCacheRoot() throws -> URL {
        guard let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw HyphaRemoteRepositoryMaterializationError.cacheUnavailable
        }
        return base.appendingPathComponent(
            "ca.zenithresearch.hypha/repository-output-v1",
            isDirectory: true
        )
    }
}
