import Foundation
import XCTest
@testable import HyphaCore

final class HyphaRemoteRepositoryMaterializerTests: XCTestCase {
    func testMaterializerFetchesValidatedOutputAndFallsBackToSameCommitCache() async throws {
        let commit = String(repeating: "a", count: 40)
        let transport = FixtureMaterializationTransport(
            tree: [
                ("out", "tree", "tree", nil),
                ("out/out.json", "blob", "manifest", 38),
                ("out/slides/deck.pptx", "blob", "deck", 12),
            ],
            blobs: [
                "manifest": Data(#"{"path":"slides/deck.pptx","format":"pptx"}"#.utf8),
                "deck": Data([0x50, 0x4b, 0x03, 0x04]) + Data("[Content_Types].xml\0ppt/presentation.xml".utf8),
            ]
        )
        let materializer = HyphaGitHubRepositoryMaterializer(transport: transport)
        let attachment = try MatrixRoomRepositoryDescriptor(
            id: "investor-deck",
            repository: "https://github.com/ZenithResearch/InvestorDeck",
            name: "InvestorDeck",
            resolvedCommit: commit
        )
        let cache = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        let remote = try await materializer.materialize(
            attachment: attachment,
            token: "github-test-token",
            cacheRoot: cache
        )

        XCTAssertEqual(remote.sourceKind, .remote)
        XCTAssertEqual(remote.attachment.resolvedCommit, commit)
        XCTAssertEqual(
            try HyphaArtifactOutputResolver().resolveAll(outDirectory: remote.outputRoot)
                .map(\.url.lastPathComponent),
            ["deck.pptx"]
        )
        let receipt = try String(
            contentsOf: remote.outputRoot.deletingLastPathComponent()
                .appendingPathComponent("materialization.json"),
            encoding: .utf8
        )
        XCTAssertTrue(receipt.contains(commit))
        XCTAssertFalse(receipt.contains("github-test-token"))

        await transport.setUnavailable(true)
        let cached = try await materializer.materialize(
            attachment: attachment,
            token: "github-test-token",
            cacheRoot: cache
        )
        XCTAssertEqual(cached.sourceKind, .cached)
        XCTAssertEqual(cached.outputRoot, remote.outputRoot)
    }

    func testMaterializerRejectsTraversalBeforeFetchingBlobs() async throws {
        let transport = FixtureMaterializationTransport(
            tree: [("out/../escape.pdf", "blob", "escape", 3)],
            blobs: ["escape": Data("pdf".utf8)]
        )
        let attachment = try MatrixRoomRepositoryDescriptor(
            id: "unsafe",
            repository: "https://github.com/ZenithResearch/Unsafe",
            name: "Unsafe",
            resolvedCommit: String(repeating: "b", count: 40)
        )
        let cache = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        do {
            _ = try await HyphaGitHubRepositoryMaterializer(transport: transport).materialize(
                attachment: attachment,
                token: "github-test-token",
                cacheRoot: cache
            )
            XCTFail("Expected path rejection")
        } catch {
            XCTAssertEqual(
                error as? HyphaRemoteRepositoryMaterializationError,
                .outputLimitExceeded
            )
        }
        let blobRequests = await transport.blobRequestCount()
        XCTAssertEqual(blobRequests, 0)
    }

    func testMaterializerRejectsContentThatDoesNotMatchItsDeclaredRendererType() async throws {
        let transport = FixtureMaterializationTransport(
            tree: [
                ("out/out.json", "blob", "manifest", 35),
                ("out/report.pdf", "blob", "report", 18),
            ],
            blobs: [
                "manifest": Data(#"{"path":"report.pdf","format":"pdf"}"#.utf8),
                "report": Data("not actually a PDF".utf8),
            ]
        )
        let attachment = try MatrixRoomRepositoryDescriptor(
            id: "spoofed",
            repository: "https://github.com/ZenithResearch/Spoofed",
            name: "Spoofed",
            resolvedCommit: String(repeating: "c", count: 40)
        )
        let cache = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: cache) }

        do {
            _ = try await HyphaGitHubRepositoryMaterializer(transport: transport).materialize(
                attachment: attachment,
                token: "github-test-token",
                cacheRoot: cache
            )
            XCTFail("Expected byte classification rejection")
        } catch {
            XCTAssertEqual(error as? HyphaRemoteRepositoryMaterializationError, .invalidOutput)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-materializer-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor FixtureMaterializationTransport: HyphaGitHubRepositoryAccessTransport {
    private let tree: [(path: String, type: String, sha: String, size: Int?)]
    private let blobs: [String: Data]
    private var unavailable = false
    private var blobRequests = 0

    init(
        tree: [(path: String, type: String, sha: String, size: Int?)],
        blobs: [String: Data]
    ) {
        self.tree = tree
        self.blobs = blobs
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if unavailable { throw URLError(.notConnectedToInternet) }
        let url = try XCTUnwrap(request.url)
        let data: Data
        if url.path.contains("/git/trees/") {
            data = try JSONSerialization.data(withJSONObject: [
                "truncated": false,
                "tree": tree.map { entry in
                    var value: [String: Any] = [
                        "path": entry.path,
                        "type": entry.type,
                        "sha": entry.sha,
                    ]
                    if let size = entry.size { value["size"] = size }
                    return value
                },
            ])
        } else if url.path.contains("/git/blobs/") {
            blobRequests += 1
            let sha = url.lastPathComponent
            let blob = try XCTUnwrap(blobs[sha])
            data = try JSONSerialization.data(withJSONObject: [
                "content": blob.base64EncodedString(),
                "encoding": "base64",
                "size": blob.count,
            ])
        } else {
            throw URLError(.badURL)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func setUnavailable(_ value: Bool) {
        unavailable = value
    }

    func blobRequestCount() -> Int { blobRequests }
}
