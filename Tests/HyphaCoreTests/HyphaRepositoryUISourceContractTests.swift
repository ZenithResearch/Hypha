import Foundation
import XCTest

final class HyphaRepositoryUISourceContractTests: XCTestCase {
    func testRoomRepositorySheetUsesSecurityScopedSelectionExplicitBuildConfirmationAndArtifactViewer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sheet = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomRepositorySheet.swift"),
            encoding: .utf8
        )
        let viewer = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaArtifactViewerView.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaApp.swift"),
            encoding: .utf8
        )

        for marker in [
            "NSOpenPanel",
            "canChooseDirectories = true",
            "startAccessingSecurityScopedResource()",
            "HyphaRoomRepositoryLocalBindingStore",
            "Remote repository URL",
            "Run this local build command?",
            "Build commands run with your user permissions",
            "Load output",
            "buildCommand(outDirectory:",
            "out.json",
            "HyphaRepositoryBuilder",
            "matrix.room.repository.build",
        ] {
            XCTAssertTrue(sheet.contains(marker), "Missing repository-sheet contract: \(marker)")
        }
        for marker in [
            "import QuickLookUI",
            "QLPreviewView",
            "case .quickLook",
            "case .web",
            "case .image",
            "case .text",
        ] {
            XCTAssertTrue(viewer.contains(marker), "Missing artifact-viewer contract: \(marker)")
        }
        XCTAssertTrue(app.contains("HyphaRoomRepositorySheet"))
        XCTAssertTrue(app.contains("matrix.room.repository.open"))
    }
}
