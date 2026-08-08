import Foundation
import XCTest
@testable import HyphaCore

final class HyphaRepositoryOutputTests: XCTestCase {
    func testViewerRegistryMapsPowerPointToQuickLook() {
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "pptx"), .quickLook)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: ".PPTX"), .quickLook)
    }

    func testOutManifestSelectsAnExplicitPresentation() throws {
        let output = try temporaryDirectory()
        let deck = output.appendingPathComponent("slides/deck.pptx")
        try FileManager.default.createDirectory(at: deck.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("presentation".utf8).write(to: deck)
        try Data(#"{"viewer":"quickLook","path":"slides/deck.pptx","format":"pptx"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.url.standardizedFileURL, deck.standardizedFileURL)
        XCTAssertEqual(selection.format, "pptx")
        XCTAssertEqual(selection.viewer, .quickLook)
        XCTAssertEqual(selection.source, .manifest)
    }

    func testOutManifestCanResolveByFormatWhenPathIsOmitted() throws {
        let output = try temporaryDirectory()
        let deck = output.appendingPathComponent("deck.pptx")
        try Data("presentation".utf8).write(to: deck)
        try Data(#"{"format":"pptx"}"#.utf8).write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.url.lastPathComponent, "deck.pptx")
        XCTAssertEqual(selection.viewer, .quickLook)
        XCTAssertEqual(selection.source, .manifest)
    }

    func testOutManifestRejectsTraversalOutsideOutDirectory() throws {
        let parent = try temporaryDirectory()
        let output = parent.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: parent.appendingPathComponent("private.txt"))
        try Data(#"{"path":"../private.txt","format":"txt"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolve(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .pathEscapesOutputDirectory)
        }
    }

    func testDiscoveryUsesSupportedTypeMapWhenManifestIsAbsent() throws {
        let output = try temporaryDirectory()
        try Data("ignore".utf8).write(to: output.appendingPathComponent("archive.bin"))
        try Data("presentation".utf8).write(to: output.appendingPathComponent("deck.pptx"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.url.lastPathComponent, "deck.pptx")
        XCTAssertEqual(selection.viewer, .quickLook)
        XCTAssertEqual(selection.source, .discovery)
    }

    func testDiscoveryReturnsNoOutputForUnsupportedFiles() throws {
        let output = try temporaryDirectory()
        try Data("ignore".utf8).write(to: output.appendingPathComponent("archive.bin"))

        XCTAssertNil(try HyphaArtifactOutputResolver().resolve(outDirectory: output))
    }

    func testBuildRunsFromRepositoryRootAndResolvesOutManifest() async throws {
        let repository = try temporaryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let command = #"mkdir -p out && pwd > out/root.txt && printf presentation > out/deck.pptx && printf '{"path":"deck.pptx","format":"pptx"}' > out/out.json"#

        let result = try await HyphaRepositoryBuilder().build(
            repositoryRoot: repository,
            command: command,
            timeout: .seconds(5)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.artifact?.url.lastPathComponent, "deck.pptx")
        let reportedRoot = try String(
            contentsOf: repository.appendingPathComponent("out/root.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: reportedRoot).lastPathComponent, repository.lastPathComponent)
    }

    func testBuildRejectsEmptyCommandsWithoutLaunchingShell() async throws {
        let repository = try temporaryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )

        do {
            _ = try await HyphaRepositoryBuilder().build(
                repositoryRoot: repository,
                command: "   ",
                timeout: .seconds(1)
            )
            XCTFail("Expected empty command rejection")
        } catch {
            XCTAssertEqual(error as? HyphaRepositoryBuildError, .emptyCommand)
        }
    }

    func testMatrixRoomAttachmentContentNeverCarriesLocalPathOrBuildCommand() throws {
        let attachment = MatrixRoomRepositoryAttachment(
            repository: "git@github.com:ZenithResearch/Hypha.git",
            name: "Hypha"
        )

        let content = try attachment.encodedContent()
        let encoded = try XCTUnwrap(String(data: content, encoding: .utf8))
        let decoded = try MatrixRoomRepositoryAttachment.decodeStateEvent(
            Data(#"{"content":{"v":1,"repository":"git@github.com:ZenithResearch/Hypha.git","name":"Hypha","output_directory":"out","manifest":"out.json"}}"#.utf8)
        )

        XCTAssertEqual(decoded, attachment)
        XCTAssertFalse(encoded.contains("/Users/"))
        XCTAssertFalse(encoded.contains("build_command"))
        XCTAssertFalse(encoded.contains("local_path"))
    }

    func testLocalBindingStoreRoundTripsSecurityScopedRepositoryAndBuildCommand() throws {
        let repository = try temporaryDirectory()
        let suiteName = "hypha-repository-binding-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HyphaRoomRepositoryLocalBindingStore(defaults: defaults)

        try store.save(
            roomID: "!room:example.org",
            repositoryRoot: repository,
            buildCommand: "swift build"
        )
        let binding = try XCTUnwrap(store.load(roomID: "!room:example.org"))

        XCTAssertEqual(binding.repositoryRoot.standardizedFileURL, repository.standardizedFileURL)
        XCTAssertEqual(binding.buildCommand, "swift build")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-output-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
