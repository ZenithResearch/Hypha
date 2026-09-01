import Foundation
import XCTest
@testable import HyphaCore

final class HyphaRoomCanvasTests: XCTestCase {
    func testValidatorAcceptsAnOfflineDigestMatchedPackage() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = root.appendingPathComponent("index.html")
        try Data("<!doctype html><html><body><hypha-room-header></hypha-room-header><script type=\"module\" src=\"app.js\"></script></body></html>".utf8).write(to: entry)
        let script = root.appendingPathComponent("app.js")
        try Data("document.body.dataset.ready = 'true';".utf8).write(to: script)
        let digest = try HyphaRoomTemplateValidator.packageDigest(files: [entry, script], root: root)
        try writeManifest(root: root, digest: digest)

        let package = try HyphaRoomTemplateValidator().validate(packageRoot: root)

        XCTAssertEqual(package.entry, entry)
        XCTAssertEqual(package.digest, digest)
        XCTAssertEqual(Set(package.manifest.capabilities), [.roomRead, .assetsList])
    }

    func testValidatorRejectsRemoteDependenciesEvenWithMatchingDigest() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = root.appendingPathComponent("index.html")
        try Data("<!doctype html><script src=\"https://example.com/app.js\"></script>".utf8).write(to: entry)
        let digest = try HyphaRoomTemplateValidator.packageDigest(files: [entry], root: root)
        try writeManifest(root: root, digest: digest)

        XCTAssertThrowsError(try HyphaRoomTemplateValidator().validate(packageRoot: root)) {
            XCTAssertEqual($0 as? HyphaRoomTemplateValidationError, .forbiddenContent)
        }
    }

    func testValidatorRejectsDigestMismatchAndSymlinks() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let entry = root.appendingPathComponent("index.html")
        try Data("<!doctype html><p>Room</p>".utf8).write(to: entry)
        try writeManifest(root: root, digest: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try HyphaRoomTemplateValidator().validate(packageRoot: root)) {
            XCTAssertEqual($0 as? HyphaRoomTemplateValidationError, .integrityMismatch)
        }

        let digest = try HyphaRoomTemplateValidator.packageDigest(files: [entry], root: root)
        try writeManifest(root: root, digest: digest)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.js"),
            withDestinationURL: entry
        )
        XCTAssertThrowsError(try HyphaRoomTemplateValidator().validate(packageRoot: root)) {
            XCTAssertEqual($0 as? HyphaRoomTemplateValidationError, .symbolicLinkForbidden)
        }
    }

    func testTemplateReferenceContainsOnlyImmutableRepositoryCoordinates() throws {
        let reference = try HyphaRoomTemplateReference(
            source: .init(
                repositoryID: "room-layout",
                path: "templates/room/hypha-room-template.json",
                resolvedCommit: String(repeating: "a", count: 40),
                sha256: String(repeating: "b", count: 64)
            )
        )
        let json = try String(decoding: JSONEncoder().encode(reference), as: UTF8.self)

        XCTAssertTrue(json.contains("repository_asset"))
        XCTAssertTrue(json.contains("resolved_commit"))
        XCTAssertFalse(json.contains("html"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertFalse(json.contains("/" + "Users/"))
    }

    func testTemplateReferenceRejectsTraversalAndMutableCoordinates() throws {
        XCTAssertThrowsError(try HyphaRoomTemplateReference(
            source: .init(
                repositoryID: "layout",
                path: "templates/../escape.json",
                resolvedCommit: String(repeating: "a", count: 40),
                sha256: String(repeating: "b", count: 64)
            )
        ))
        XCTAssertThrowsError(try HyphaRoomTemplateReference(
            source: .init(
                repositoryID: "layout",
                path: "template/hypha-room-template.json",
                resolvedCommit: "main",
                sha256: String(repeating: "b", count: 64)
            )
        ))
    }

    func testBridgeMethodsMapToTheLockedCapabilities() throws {
        XCTAssertEqual(HyphaCanvasBridgeMethod.roomGetMetadata.capability, .roomRead)
        XCTAssertEqual(HyphaCanvasBridgeMethod.repositoriesList.capability, .repositoriesList)
        XCTAssertEqual(HyphaCanvasBridgeMethod.assetsList.capability, .assetsList)
        XCTAssertEqual(HyphaCanvasBridgeMethod.assetsGetURL.capability, .assetsRead)
        XCTAssertEqual(HyphaCanvasBridgeMethod.viewerOpen.capability, .viewerOpen)
        XCTAssertEqual(HyphaCanvasBridgeMethod.layoutStateSet.capability, .layoutStateWrite)

        let request = HyphaCanvasBridgeRequest(
            id: "request-id",
            method: .assetsList,
            params: ["prefix": .string("slides/")]
        )
        let roundTrip = try JSONDecoder().decode(
            HyphaCanvasBridgeRequest.self,
            from: JSONEncoder().encode(request)
        )
        XCTAssertEqual(roundTrip, request)
    }

    func testCanvasHostIsSeparateFromTheNonScriptableArtifactViewer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let canvas = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomCanvasView.swift"),
            encoding: .utf8
        )
        let artifact = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaArtifactViewerView.swift"),
            encoding: .utf8
        )
        for marker in [
            "websiteDataStore = .nonPersistent()",
            "allowsContentJavaScript = true",
            "hypha-template",
            "hypha-asset",
            "Content-Security-Policy",
            "Content-Type",
            "URLComponents(url: url",
            "JSON.parse(atob",
            "connect-src 'none'",
            "navigationAction.navigationType == .linkActivated",
            "removeScriptMessageHandler",
        ] {
            XCTAssertTrue(canvas.contains(marker), "Missing Canvas security boundary: \(marker)")
        }
        XCTAssertTrue(artifact.contains("allowsContentJavaScript = false"))
        XCTAssertFalse(artifact.contains("hyphaBridge"))
        XCTAssertFalse(canvas.contains("loadFileURL"))
    }

    private func writeManifest(root: URL, digest: String) throws {
        let manifest = HyphaRoomTemplateManifest(
            entry: "index.html",
            capabilities: [.roomRead, .assetsList],
            integrity: .init(digest: digest)
        )
        try JSONEncoder().encode(manifest).write(
            to: root.appendingPathComponent(HyphaRoomTemplateValidator.manifestName)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-canvas-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
