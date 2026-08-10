import Foundation
import XCTest
@testable import HyphaCore

final class HyphaRepositoryOutputTests: XCTestCase {
    func testViewerRegistryNormalizesPowerPointOOXMLToSlideshowAndKeepsLegacyPPTFallback() {
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "pptx"), .slideshow)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: ".PPTX"), .slideshow)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "ppsx"), .slideshow)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "ppt"), .quickLook)
        XCTAssertEqual(HyphaArtifactViewerRegistry.oldClientSafeMirror(forFormat: "pptx"), .quickLook)
    }

    func testViewerRegistryMapsMarkdownToRenderedMarkdown() {
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "md"), .markdown)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: ".MARKDOWN"), .markdown)
        XCTAssertEqual(HyphaArtifactViewerRegistry.viewer(forFormat: "txt"), .text)
    }

    func testMarkdownParserPreservesDocumentBlockStructure() {
        let blocks = HyphaMarkdownParser.blocks(in: """
        # Output

        Generated **deck** files from `src/`.

        - Slides
        2. Notes

        > Local review only.

        ```json
        {"viewer":"quickLook"}
        ```
        """)

        XCTAssertEqual(blocks, [
            .heading(level: 1, text: "Output"),
            .paragraph("Generated **deck** files from `src/`."),
            .unorderedListItem("Slides"),
            .orderedListItem(number: 2, text: "Notes"),
            .quote("Local review only."),
            .codeBlock(language: "json", code: "{\"viewer\":\"quickLook\"}"),
        ])
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
        XCTAssertEqual(selection.viewer, .slideshow)
        XCTAssertEqual(selection.source, .manifest)
    }

    func testOutManifestCanResolveByFormatWhenPathIsOmitted() throws {
        let output = try temporaryDirectory()
        let deck = output.appendingPathComponent("deck.pptx")
        try Data("presentation".utf8).write(to: deck)
        try Data(#"{"format":"pptx"}"#.utf8).write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.url.lastPathComponent, "deck.pptx")
        XCTAssertEqual(selection.viewer, .slideshow)
        XCTAssertEqual(selection.source, .manifest)
    }

    func testExplicitVersionOnePowerPointQuickLookNormalizesToSlideshow() throws {
        let output = try temporaryDirectory()
        try Data("presentation".utf8).write(to: output.appendingPathComponent("deck.PPTX"))
        try Data(#"{"version":1,"viewer":"quickLook","path":"deck.PPTX","format":"PPTX"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.format, "pptx")
        XCTAssertEqual(selection.viewer, .slideshow)
    }

    func testVersionTwoCanonicalManifestResolvesDeclaredArtifactsAndMetadata() throws {
        let output = try canonicalVersionTwoOutput()
        try Data("undeclared".utf8).write(to: output.appendingPathComponent("README.md"))

        let selections = try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)

        XCTAssertEqual(selections.map(\.id), ["deck", "launch-brief", "product-map", "speaker-notes"])
        XCTAssertEqual(selections.map(\.viewer), [.slideshow, .pdf, .web, .markdown])
        XCTAssertEqual(selections.map(\.title), [
            "Quarterly deck",
            "Launch brief",
            "Interactive product map",
            "Speaker notes",
        ])
        XCTAssertEqual(
            selections.first?.mediaType,
            "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        )
        XCTAssertEqual(selections[2].bundleRoot?.lastPathComponent, "site")
        XCTAssertTrue(selections.allSatisfy { $0.source == .manifest })
        XCTAssertFalse(selections.contains { $0.url.lastPathComponent == "README.md" })
    }

    func testVersionTwoRetainsRelativeOrderAfterMovingPrimaryFirst() throws {
        let output = try temporaryDirectory()
        for name in ["one.txt", "two.txt", "three.txt"] {
            try Data(name.utf8).write(to: output.appendingPathComponent(name))
        }
        try Data(#"""
        {
          "version": 2,
          "primary": "two",
          "path": "two.txt",
          "format": "txt",
          "viewer": "text",
          "artifacts": [
            {"id":"one","path":"one.txt"},
            {"id":"two","path":"two.txt"},
            {"id":"three","path":"three.txt"}
          ]
        }
        """#.utf8).write(to: output.appendingPathComponent("out.json"))

        let selections = try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)

        XCTAssertEqual(selections.map(\.id), ["two", "one", "three"])
    }

    func testVersionTwoPDFUsesPDFKitRouteAndQuickLookCompatibilityMirror() throws {
        let output = try temporaryDirectory()
        try Data("pdf".utf8).write(to: output.appendingPathComponent("brief.pdf"))
        try Data(#"{"version":2,"primary":"brief","path":"brief.pdf","format":"pdf","viewer":"quickLook","artifacts":[{"id":"brief","path":"brief.pdf","viewer":"pdf"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.viewer, .pdf)
    }

    func testVersionTwoMarkdownUsesTextCompatibilityMirror() throws {
        let output = try temporaryDirectory()
        try Data("# Notes".utf8).write(to: output.appendingPathComponent("notes.md"))
        try Data(#"{"version":2,"primary":"notes","path":"notes.md","format":"md","viewer":"text","artifacts":[{"id":"notes","path":"notes.md","viewer":"markdown"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.viewer, .markdown)
    }

    func testVersionTwoAcceptsHiddenPathComponentsAndInfersHTMLBundleRoute() throws {
        let output = try temporaryDirectory()
        let assets = output.appendingPathComponent("site/.assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: assets.appendingPathComponent("index.html"))
        try Data(#"{"version":2,"primary":"site","path":"site/.assets/index.html","artifacts":[{"id":"site","path":"site/.assets/index.html","bundle_root":"site/.assets"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.viewer, .web)
        XCTAssertEqual(selection.format, "html")
        XCTAssertEqual(selection.bundleRoot?.lastPathComponent, ".assets")
    }

    func testLegacyPDFQuickLookManifestRemainsReadable() throws {
        let output = try temporaryDirectory()
        try Data("pdf".utf8).write(to: output.appendingPathComponent("document.pdf"))
        try Data(#"{"path":"document.pdf","format":"pdf","viewer":"quickLook"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.viewer, .quickLook)
    }

    func testViewerVocabularyRejectsSlideshowInVersionOne() throws {
        let output = try temporaryDirectory()
        try Data("deck".utf8).write(to: output.appendingPathComponent("deck.pptx"))
        try Data(#"{"viewer":"slideshow","path":"deck.pptx","format":"pptx"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .viewerValueNotAllowed(.slideshow))
        }
    }

    func testViewerVocabularyRejectsArtifactOnlyValuesInVersionTwoTopLevelMirror() throws {
        for viewer in [HyphaArtifactViewer.slideshow, .pdf, .markdown] {
            let output = try temporaryDirectory()
            try Data("deck".utf8).write(to: output.appendingPathComponent("deck.pptx"))
            let manifest = """
            {"version":2,"primary":"deck","path":"deck.pptx","format":"pptx","viewer":"\(viewer.rawValue)","artifacts":[{"id":"deck","path":"deck.pptx","viewer":"slideshow"}]}
            """
            try Data(manifest.utf8).write(to: output.appendingPathComponent("out.json"))

            XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
                XCTAssertEqual(error as? HyphaArtifactOutputError, .viewerValueNotAllowed(viewer))
            }
        }
    }

    func testVersionTwoRejectsCompatibilityMirrorThatDoesNotMatchPrimary() throws {
        let output = try temporaryDirectory()
        try Data("deck".utf8).write(to: output.appendingPathComponent("deck.pptx"))
        try Data(#"{"version":2,"primary":"deck","path":"deck.pptx","format":"pptx","viewer":"web","artifacts":[{"id":"deck","path":"deck.pptx","viewer":"slideshow"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .legacyPrimaryMismatch)
        }
    }

    func testVersionTwoRequiresPrimaryWhenSeveralArtifactsAreDeclared() throws {
        let output = try temporaryDirectory()
        try Data("one".utf8).write(to: output.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: output.appendingPathComponent("two.txt"))
        try Data(#"{"version":2,"path":"one.txt","artifacts":[{"id":"one","path":"one.txt"},{"id":"two","path":"two.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .primaryArtifactUnavailable)
        }
    }

    func testVersionTwoRejectsDuplicateArtifactIdentifiers() throws {
        let output = try temporaryDirectory()
        try Data("one".utf8).write(to: output.appendingPathComponent("one.txt"))
        try Data("two".utf8).write(to: output.appendingPathComponent("two.txt"))
        try Data(#"{"version":2,"primary":"duplicate","path":"one.txt","artifacts":[{"id":"duplicate","path":"one.txt"},{"id":"duplicate","path":"two.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .duplicateArtifactID("duplicate"))
        }
    }

    func testVersionTwoRejectsTraversalInDeclaredArtifact() throws {
        let parent = try temporaryDirectory()
        let output = parent.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: parent.appendingPathComponent("private.txt"))
        try Data(#"{"version":2,"primary":"private","path":"../private.txt","artifacts":[{"id":"private","path":"../private.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .invalidArtifactDefinition)
        }
    }

    func testVersionTwoRejectsWindowsAbsolutePathSyntax() throws {
        let output = try temporaryDirectory()
        try Data(#"{"version":2,"primary":"private","path":"C:/private.txt","viewer":"text","artifacts":[{"id":"private","path":"C:/private.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .invalidArtifactDefinition)
        }
    }

    func testVersionTwoRejectsDotAndWhitespaceBoundedStrictPaths() throws {
        for invalidPath in [".", "./artifact.txt", "artifact/.", " artifact.txt", "artifact.txt "] {
            let output = try temporaryDirectory()
            let manifest: [String: Any] = [
                "version": 2,
                "primary": "artifact",
                "path": invalidPath,
                "artifacts": [["id": "artifact", "path": invalidPath]],
            ]
            try JSONSerialization.data(withJSONObject: manifest)
                .write(to: output.appendingPathComponent("out.json"))

            XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
                XCTAssertEqual(error as? HyphaArtifactOutputError, .invalidArtifactDefinition)
            }
        }
    }

    func testVersionTwoRejectsHTMLBundleThatDoesNotContainEntryPoint() throws {
        let output = try temporaryDirectory()
        let site = output.appendingPathComponent("site", isDirectory: true)
        let other = output.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("<html></html>".utf8).write(to: other.appendingPathComponent("index.html"))
        try Data(#"{"version":2,"primary":"site","path":"other/index.html","format":"html","viewer":"web","artifacts":[{"id":"site","path":"other/index.html","viewer":"web","bundle_root":"site"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .bundleRootDoesNotContainArtifact)
        }
    }

    func testVersionTwoRejectsUnknownFutureVersion() throws {
        let output = try temporaryDirectory()
        try Data(#"{"version":3,"artifacts":[]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .unsupportedManifestVersion(3))
        }
    }

    func testVersionTwoRejectsMoreThanSixtyFourArtifactsBeforeFileResolution() throws {
        let output = try temporaryDirectory()
        let artifacts = (0 ... 64).map { index in
            ["id": "artifact-\(index)", "path": "artifact-\(index).txt"]
        }
        let manifest: [String: Any] = [
            "version": 2,
            "primary": "artifact-0",
            "path": "artifact-0.txt",
            "artifacts": artifacts,
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .invalidArtifactDefinition)
        }
    }

    func testVersionTwoRejectsInvalidIDsTitlesAndMediaTypes() throws {
        let invalidEntries: [[String: Any]] = [
            ["id": "bad id", "path": "artifact.txt"],
            ["id": "artifact", "path": "artifact.txt", "title": "   "],
            ["id": "artifact", "path": "artifact.txt", "media_type": "text/plain; charset=utf-8"],
            ["id": "artifact", "path": "artifact.txt", "format": ".txt"],
        ]

        for entry in invalidEntries {
            let output = try temporaryDirectory()
            try Data("artifact".utf8).write(to: output.appendingPathComponent("artifact.txt"))
            let manifest: [String: Any] = [
                "version": 2,
                "primary": entry["id"] as? String ?? "artifact",
                "path": "artifact.txt",
                "viewer": "text",
                "artifacts": [entry],
            ]
            try JSONSerialization.data(withJSONObject: manifest)
                .write(to: output.appendingPathComponent("out.json"))

            XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
                XCTAssertEqual(error as? HyphaArtifactOutputError, .invalidArtifactDefinition)
            }
        }
    }

    func testVersionTwoRejectsPrimaryIdentifierWithSurroundingWhitespace() throws {
        let output = try temporaryDirectory()
        try Data("artifact".utf8).write(to: output.appendingPathComponent("artifact.txt"))
        try Data(#"{"version":2,"primary":" artifact ","path":"artifact.txt","viewer":"text","artifacts":[{"id":"artifact","path":"artifact.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .primaryArtifactUnavailable)
        }
    }

    func testVersionTwoRejectsSymlinkEscape() throws {
        let parent = try temporaryDirectory()
        let output = parent.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let privateFile = parent.appendingPathComponent("private.txt")
        try Data("private".utf8).write(to: privateFile)
        try FileManager.default.createSymbolicLink(
            at: output.appendingPathComponent("linked.txt"),
            withDestinationURL: privateFile
        )
        try Data(#"{"version":2,"primary":"linked","path":"linked.txt","viewer":"text","artifacts":[{"id":"linked","path":"linked.txt"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .pathEscapesOutputDirectory)
        }
    }

    func testVersionTwoRejectsSlideshowPreferenceForNonPowerPointArtifact() throws {
        let output = try temporaryDirectory()
        try Data("notes".utf8).write(to: output.appendingPathComponent("notes.txt"))
        try Data(#"{"version":2,"primary":"notes","path":"notes.txt","viewer":"text","artifacts":[{"id":"notes","path":"notes.txt","viewer":"slideshow"}]}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        XCTAssertThrowsError(try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)) { error in
            XCTAssertEqual(error as? HyphaArtifactOutputError, .viewerFormatMismatch)
        }
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
        XCTAssertEqual(selection.viewer, .slideshow)
        XCTAssertEqual(selection.source, .discovery)
    }

    func testDiscoveryReturnsEveryViewerSupportedOutputAsset() throws {
        let output = try temporaryDirectory()
        let nested = output.appendingPathComponent("slides", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("read me".utf8).write(to: output.appendingPathComponent("README.md"))
        try Data("presentation".utf8).write(to: nested.appendingPathComponent("deck.pptx"))
        try Data("<html></html>".utf8).write(to: output.appendingPathComponent("index.html"))
        try Data("ignore".utf8).write(to: output.appendingPathComponent("archive.bin"))

        let selections = try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)

        XCTAssertEqual(
            selections.map(\.url.lastPathComponent),
            ["README.md", "index.html", "deck.pptx"]
        )
        XCTAssertEqual(selections.map(\.viewer), [.markdown, .web, .slideshow])
        XCTAssertTrue(selections.allSatisfy { $0.source == .discovery })
    }

    func testManifestSelectionRemainsDefaultWhileOtherSupportedAssetsStayAvailable() throws {
        let output = try temporaryDirectory()
        try Data("read me".utf8).write(to: output.appendingPathComponent("README.md"))
        try Data("presentation".utf8).write(to: output.appendingPathComponent("deck.pptx"))
        try Data("<html></html>".utf8).write(to: output.appendingPathComponent("index.html"))
        try Data(#"{"path":"deck.pptx","format":"pptx"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selections = try HyphaArtifactOutputResolver().resolveAll(outDirectory: output)

        XCTAssertEqual(selections.map(\.url.lastPathComponent), ["deck.pptx", "README.md", "index.html"])
        XCTAssertEqual(selections.first?.source, .manifest)
        XCTAssertTrue(selections.dropFirst().allSatisfy { $0.source == .discovery })
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
        XCTAssertEqual(result.artifacts.map(\.url.lastPathComponent), ["deck.pptx", "root.txt"])
        let reportedRoot = try String(
            contentsOf: repository.appendingPathComponent("out/root.txt"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: reportedRoot).lastPathComponent, repository.lastPathComponent)
    }

    func testEmptyBuildCommandResolvesExistingOutputWithoutLaunchingShell() async throws {
        let repository = try temporaryDirectory()
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let output = repository.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("presentation".utf8).write(to: output.appendingPathComponent("deck.pptx"))

        let result = try await HyphaRepositoryBuilder().build(
            repositoryRoot: repository,
            command: "   ",
            timeout: .seconds(1)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.didRunCommand)
        XCTAssertEqual(result.artifact?.url.lastPathComponent, "deck.pptx")
        XCTAssertEqual(result.artifacts.map(\.url.lastPathComponent), ["deck.pptx"])
    }

    func testOutManifestExposesBuildCommandForExplicitConfirmation() throws {
        let output = try temporaryDirectory()
        try Data(#"{"build":"npm run export","path":"deck.pptx","format":"pptx"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let command = try HyphaArtifactOutputResolver().buildCommand(outDirectory: output)

        XCTAssertEqual(command, "npm run export")
    }

    func testBuildOnlyManifestFallsBackToSupportedOutputDiscovery() throws {
        let output = try temporaryDirectory()
        try Data("presentation".utf8).write(to: output.appendingPathComponent("deck.pptx"))
        try Data(#"{"build":"npm run export"}"#.utf8)
            .write(to: output.appendingPathComponent("out.json"))

        let selection = try XCTUnwrap(HyphaArtifactOutputResolver().resolve(outDirectory: output))

        XCTAssertEqual(selection.url.lastPathComponent, "deck.pptx")
        XCTAssertEqual(selection.source, .manifest)
    }

    func testRepositoryOutputSchemaSplitsViewerVocabulariesAndCanonicalExampleParses() throws {
        let root = repositoryRoot()
        let schemaURL = root.appendingPathComponent("docs/out.schema.json")
        let exampleURL = root.appendingPathComponent("docs/examples/out.v2.json")
        let schema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any]
        )
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])

        func viewerValues(_ name: String) throws -> Set<String> {
            let definition = try XCTUnwrap(definitions[name] as? [String: Any])
            return Set(try XCTUnwrap(definition["enum"] as? [String]))
        }

        let legacy = try viewerValues("legacyInputViewer")
        let mirror = try viewerValues("oldClientSafeMirrorViewer")
        let artifact = try viewerValues("artifactViewer")

        XCTAssertEqual(legacy, ["quickLook", "pdf", "web", "image", "markdown", "text"])
        XCTAssertEqual(mirror, ["quickLook", "web", "image", "text"])
        XCTAssertEqual(artifact, ["quickLook", "pdf", "web", "image", "markdown", "text", "slideshow"])
        XCTAssertFalse(legacy.contains("slideshow"))
        for artifactOnlyValue in ["slideshow", "pdf", "markdown"] {
            XCTAssertTrue(artifact.contains(artifactOnlyValue))
            XCTAssertFalse(mirror.contains(artifactOnlyValue))
        }

        let example = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: exampleURL)) as? [String: Any]
        )
        XCTAssertEqual(example["version"] as? Int, 2)
        XCTAssertEqual(example["primary"] as? String, "deck")
        XCTAssertEqual(example["viewer"] as? String, "quickLook")
        XCTAssertEqual((example["artifacts"] as? [[String: Any]])?.count, 4)
    }

    func testRepositoryOutputSchemaConformanceSuite() throws {
        let root = repositoryRoot()
        try runNPM(
            ["--prefix", "docs", "ci", "--ignore-scripts", "--no-audit", "--no-fund"],
            at: root
        )
        try runNPM(["--prefix", "docs", "test"], at: root)
    }

    func testRepositoryOutputDocumentationRecordsCompatibilityAndRemoteExecutionBoundaries() throws {
        let root = repositoryRoot()
        let documentation = try String(
            contentsOf: root.appendingPathComponent("docs/repository-output-contract.md"),
            encoding: .utf8
        )
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)

        for marker in [
            "Three viewer vocabularies",
            "stable identifier",
            "bundle_root",
            "media_type",
            "PPTX/PPSX slideshow",
            "must ignore it and must never execute it",
            "Artifact order is stable",
        ] {
            XCTAssertTrue(documentation.contains(marker), "Missing output-contract documentation: \(marker)")
        }
        XCTAssertTrue(readme.contains("docs/repository-output-contract.md"))
        XCTAssertTrue(readme.contains("docs/out.schema.json"))
        XCTAssertTrue(readme.contains("docs/examples/out.v2.json"))
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
        let privatePathMarker = ["", "Users", "local", "repo"].joined(separator: "/")
        XCTAssertFalse(encoded.contains(privatePathMarker))
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

    func testLocalBindingStoreAcceptsAnEmptyBuildCommand() throws {
        let repository = try temporaryDirectory()
        let suiteName = "hypha-repository-binding-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HyphaRoomRepositoryLocalBindingStore(defaults: defaults)

        try store.save(
            roomID: "!room:example.org",
            repositoryRoot: repository,
            buildCommand: ""
        )

        XCTAssertEqual(try store.load(roomID: "!room:example.org")?.buildCommand, "")
    }

    private func canonicalVersionTwoOutput() throws -> URL {
        let output = try temporaryDirectory()
        let slides = output.appendingPathComponent("slides", isDirectory: true)
        let site = output.appendingPathComponent("site", isDirectory: true)
        try FileManager.default.createDirectory(at: slides, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: site, withIntermediateDirectories: true)
        try Data("presentation".utf8).write(to: slides.appendingPathComponent("deck.pptx"))
        try Data("pdf".utf8).write(to: output.appendingPathComponent("launch.pdf"))
        try Data("<html></html>".utf8).write(to: site.appendingPathComponent("index.html"))
        try Data("# Notes".utf8).write(to: output.appendingPathComponent("notes.md"))
        try Data(contentsOf: repositoryRoot().appendingPathComponent("docs/examples/out.v2.json"))
            .write(to: output.appendingPathComponent("out.json"))
        return output
    }

    private func runNPM(
        _ arguments: [String],
        at root: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm"] + arguments
        process.currentDirectoryURL = root
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(
            process.terminationStatus,
            0,
            "npm \(arguments.joined(separator: " ")) failed:\n\(text)",
            file: file,
            line: line
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypha-output-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
