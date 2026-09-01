import Foundation

public enum MatrixRoomRepositorySetError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case invalidAttachmentID(String)
    case duplicateAttachmentID(String)
    case invalidRepository(String)
    case invalidName
    case invalidOutputCoordinates
    case invalidRequestedRef
    case invalidResolvedCommit
    case missingPrimary
    case primaryUnavailable(String)
    case attachmentLimitExceeded(Int)
    case encodedStateTooLarge(Int)
    case invalidState
}

public struct MatrixRoomRepositoryDescriptor: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let repository: String
    public let name: String
    public let outputDirectory: String
    public let manifestPath: String
    public let requestedRef: String
    public let resolvedCommit: String?

    public init(
        id: String,
        repository: String,
        name: String,
        outputDirectory: String = "out",
        manifestPath: String = "out.json",
        requestedRef: String = "main",
        resolvedCommit: String? = nil
    ) throws {
        self.id = id
        self.repository = repository
        self.name = name
        self.outputDirectory = outputDirectory
        self.manifestPath = manifestPath
        self.requestedRef = requestedRef
        self.resolvedCommit = resolvedCommit
        try validate()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case repository
        case name
        case outputDirectory = "output_directory"
        case manifestPath = "manifest"
        case requestedRef = "requested_ref"
        case resolvedCommit = "resolved_commit"
    }

    fileprivate func validate() throws {
        guard Self.validID(id) else {
            throw MatrixRoomRepositorySetError.invalidAttachmentID(id)
        }
        guard Self.validBoundedText(repository, maximumUTF8Count: 2_048) else {
            throw MatrixRoomRepositorySetError.invalidRepository(repository)
        }
        guard Self.validBoundedText(name, maximumUTF8Count: 120) else {
            throw MatrixRoomRepositorySetError.invalidName
        }
        guard Self.validRelativePath(outputDirectory), Self.validRelativePath(manifestPath) else {
            throw MatrixRoomRepositorySetError.invalidOutputCoordinates
        }
        guard Self.validBoundedText(requestedRef, maximumUTF8Count: 255),
              requestedRef != ".", requestedRef != "..",
              !requestedRef.hasPrefix("-"),
              !requestedRef.contains(".."),
              !requestedRef.contains("@{") else {
            throw MatrixRoomRepositorySetError.invalidRequestedRef
        }
        if let resolvedCommit {
            let allowedLengths = [40, 64]
            guard allowedLengths.contains(resolvedCommit.count),
                  resolvedCommit.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
                throw MatrixRoomRepositorySetError.invalidResolvedCommit
            }
        }
    }

    public func resolving(commit: String) throws -> Self {
        try Self(
            id: id,
            repository: repository,
            name: name,
            outputDirectory: outputDirectory,
            manifestPath: manifestPath,
            requestedRef: requestedRef,
            resolvedCommit: commit
        )
    }

    public func requestingCurrentResolution() throws -> Self {
        try Self(
            id: id,
            repository: repository,
            name: name,
            outputDirectory: outputDirectory,
            manifestPath: manifestPath,
            requestedRef: requestedRef,
            resolvedCommit: nil
        )
    }

    private static func validID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 64, let first = value.first,
              first.isASCII, first.isLetter || first.isNumber else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.allSatisfy { $0.isASCII && allowed.contains($0) }
    }

    private static func validBoundedText(_ value: String, maximumUTF8Count: Int) -> Bool {
        value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.isEmpty
            && value.utf8.count <= maximumUTF8Count
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func validRelativePath(_ value: String) -> Bool {
        guard validBoundedText(value, maximumUTF8Count: 1_024),
              !value.hasPrefix("/"),
              !value.contains("\\") else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}

public struct MatrixRoomRepositorySet: Codable, Equatable, Sendable {
    public static let eventType = "ca.zenithresearch.hypha.repositories"
    public static let stateKey = "room"
    public static let maximumAttachmentCount = 42
    public static let maximumEncodedBytes = 48 * 1_024

    public let version: Int
    public let primaryID: String?
    public let repositories: [MatrixRoomRepositoryDescriptor]

    public init(
        repositories: [MatrixRoomRepositoryDescriptor],
        primaryID: String? = nil,
        version: Int = 2
    ) throws {
        self.version = version
        self.primaryID = primaryID
        self.repositories = repositories
        try validate()
    }

    private init(
        validatedRepositories repositories: [MatrixRoomRepositoryDescriptor],
        primaryID: String?,
        version: Int
    ) {
        self.version = version
        self.primaryID = primaryID
        self.repositories = repositories
    }

    public static var empty: Self {
        Self(validatedRepositories: [], primaryID: nil, version: 2)
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case primaryID = "primary"
        case repositories
    }

    public var primary: MatrixRoomRepositoryDescriptor? {
        guard let primaryID else { return nil }
        return repositories.first { $0.id == primaryID }
    }

    public var legacyMirror: MatrixRoomRepositoryAttachment? {
        primary.map(MatrixRoomRepositoryAttachment.init(descriptor:))
    }

    public func encodedContent() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumEncodedBytes else {
            throw MatrixRoomRepositorySetError.encodedStateTooLarge(data.count)
        }
        return data
    }

    public static func decodeStateEvent(_ data: Data) throws -> MatrixRoomRepositorySet {
        struct Envelope: Decodable { let content: MatrixRoomRepositorySet }
        let value: MatrixRoomRepositorySet
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            value = envelope.content
        } else {
            do {
                value = try JSONDecoder().decode(MatrixRoomRepositorySet.self, from: data)
            } catch {
                throw MatrixRoomRepositorySetError.invalidState
            }
        }
        try value.validate()
        guard data.count <= Self.maximumEncodedBytes + 1_024 else {
            throw MatrixRoomRepositorySetError.encodedStateTooLarge(data.count)
        }
        return value
    }

    public static func migrating(_ attachment: MatrixRoomRepositoryAttachment) throws -> Self {
        let descriptor = try MatrixRoomRepositoryDescriptor(
            id: Self.attachmentID(name: attachment.name),
            repository: attachment.repository ?? "",
            name: attachment.name,
            outputDirectory: attachment.outputDirectory,
            manifestPath: attachment.manifestPath
        )
        return try Self(repositories: [descriptor], primaryID: descriptor.id)
    }

    public func replacingPrimary(with id: String) throws -> Self {
        try Self(repositories: repositories, primaryID: id)
    }

    public func appending(_ repository: MatrixRoomRepositoryDescriptor) throws -> Self {
        try Self(
            repositories: repositories + [repository],
            primaryID: primaryID ?? repository.id
        )
    }

    public func removing(id: String) throws -> Self {
        let remaining = repositories.filter { $0.id != id }
        let nextPrimary = primaryID == id ? remaining.first?.id : primaryID
        return try Self(repositories: remaining, primaryID: nextPrimary)
    }

    public func replacing(_ repository: MatrixRoomRepositoryDescriptor) throws -> Self {
        guard repositories.contains(where: { $0.id == repository.id }) else {
            throw MatrixRoomRepositorySetError.invalidAttachmentID(repository.id)
        }
        return try Self(
            repositories: repositories.map { $0.id == repository.id ? repository : $0 },
            primaryID: primaryID
        )
    }

    public static func attachmentID(name: String) -> String {
        let lowered = name.lowercased()
        var output = ""
        var previousWasSeparator = false
        for scalar in lowered.unicodeScalars {
            let character = Character(scalar)
            if character.isASCII, character.isLetter || character.isNumber || character == "." || character == "_" {
                output.append(character)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                output.append("-")
                previousWasSeparator = true
            }
        }
        output = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if output.isEmpty || output.first?.isLetter == false && output.first?.isNumber == false {
            output = "repository"
        }
        return String(output.prefix(64))
    }

    private func validate() throws {
        guard version == 2 else {
            throw MatrixRoomRepositorySetError.unsupportedVersion(version)
        }
        guard repositories.count <= Self.maximumAttachmentCount else {
            throw MatrixRoomRepositorySetError.attachmentLimitExceeded(repositories.count)
        }
        var identifiers = Set<String>()
        for repository in repositories {
            try repository.validate()
            guard identifiers.insert(repository.id).inserted else {
                throw MatrixRoomRepositorySetError.duplicateAttachmentID(repository.id)
            }
        }
        if repositories.isEmpty {
            guard primaryID == nil else { throw MatrixRoomRepositorySetError.missingPrimary }
        } else {
            guard let primaryID else { throw MatrixRoomRepositorySetError.missingPrimary }
            guard identifiers.contains(primaryID) else {
                throw MatrixRoomRepositorySetError.primaryUnavailable(primaryID)
            }
        }
    }
}

public enum MatrixRoomRepositoryStateSource: String, Equatable, Sendable {
    case none
    case legacy
    case collection
}

public enum MatrixRoomRepositoryMirrorStatus: String, Equatable, Sendable {
    case notApplicable
    case current
    case missing
    case divergent
}

public struct MatrixRoomRepositoryState: Equatable, Sendable {
    public let repositorySet: MatrixRoomRepositorySet
    public let source: MatrixRoomRepositoryStateSource
    public let mirrorStatus: MatrixRoomRepositoryMirrorStatus

    public init(
        repositorySet: MatrixRoomRepositorySet,
        source: MatrixRoomRepositoryStateSource,
        mirrorStatus: MatrixRoomRepositoryMirrorStatus
    ) {
        self.repositorySet = repositorySet
        self.source = source
        self.mirrorStatus = mirrorStatus
    }

    public static var empty: Self {
        Self(
            repositorySet: .empty,
            source: .none,
            mirrorStatus: .notApplicable
        )
    }
}

public enum MatrixRoomRepositorySetWriteResult: Equatable, Sendable {
    case applied
    case appliedWithStaleMirror
}

public extension MatrixRoomRepositoryAttachment {
    init(descriptor: MatrixRoomRepositoryDescriptor) {
        self.init(
            repository: descriptor.repository,
            name: descriptor.name,
            outputDirectory: descriptor.outputDirectory,
            manifestPath: descriptor.manifestPath
        )
    }

    func matches(_ descriptor: MatrixRoomRepositoryDescriptor) -> Bool {
        version == 1
            && repository == descriptor.repository
            && name == descriptor.name
            && outputDirectory == descriptor.outputDirectory
            && manifestPath == descriptor.manifestPath
    }
}
