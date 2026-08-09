import Foundation
import XCTest

final class HyphaRepositoryUISourceContractTests: XCTestCase {
    func testRoomWorkspaceStartsContentFirstAndKeepsArtifactViewerOutOfRepositorySettings() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaApp.swift"),
            encoding: .utf8
        )
        let sheet = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomRepositorySheet.swift"),
            encoding: .utf8
        )

        for marker in [
            "HyphaRoomWorkspaceView",
            "HyphaRoomContentView",
            "HyphaRoomChatPlacement",
            ".content",
            "roomContentRefreshID",
            "onDismiss:",
            "matrix.room.layout.content",
            "matrix.room.layout.chat-main",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing content-first room workspace contract: \(marker)")
        }
        XCTAssertFalse(
            sheet.contains("HyphaArtifactViewerView"),
            "Repository settings must configure output without rendering it"
        )
    }

    func testChatUsesATrailingOverlaySheetWithoutCompressingRoomContent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workspace = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomWorkspaceView.swift"),
            encoding: .utf8
        )

        for marker in [
            "showsChatSheet",
            ".overlay(alignment: .trailing)",
            ".transition(.move(edge: .trailing))",
            "matrix.room.chat-sheet",
            "matrix.room.chat-sheet.toggle",
        ] {
            XCTAssertTrue(workspace.contains(marker), "Missing trailing chat-sheet contract: \(marker)")
        }
        XCTAssertFalse(workspace.contains("HSplitView"), "Chat must overlay content rather than resize it")
        XCTAssertFalse(workspace.contains("Content + chat"), "The room mode control must not describe another split view")
    }

    func testRepositorySettingsConfigureBindingWhileRoomContentOwnsBuildAndViewer() throws {
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
        let workspace = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomWorkspaceView.swift"),
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
            "Verify private access",
            "githubConnection.verify(remote:",
            "out.json",
            "matrix.room.repository.attach",
        ] {
            XCTAssertTrue(sheet.contains(marker), "Missing repository-sheet contract: \(marker)")
        }
        for forbidden in [
            "HyphaArtifactViewerView",
            "HyphaRepositoryBuilder",
            "Run this local build command?",
            "matrix.room.repository.build",
        ] {
            XCTAssertFalse(sheet.contains(forbidden), "Repository settings own configuration only: \(forbidden)")
        }
        for marker in [
            "HyphaArtifactViewerView",
            "HyphaRepositoryBuilder",
            "Run this local build command?",
            "Open output",
            "matrix.room.content.open-output",
        ] {
            XCTAssertTrue(workspace.contains(marker), "Missing room-content output contract: \(marker)")
        }
        for marker in [
            "import QuickLookUI",
            "QLPreviewView",
            "case .quickLook",
            "case .web",
            "case .image",
            "case .markdown",
            "case .text",
            "HyphaMarkdownArtifactView",
            "AttributedString(markdown:",
        ] {
            XCTAssertTrue(viewer.contains(marker), "Missing artifact-viewer contract: \(marker)")
        }
        XCTAssertTrue(app.contains("HyphaRoomRepositorySheet"))
        XCTAssertTrue(app.contains("matrix.room.repository.open"))
        XCTAssertTrue(app.contains("Section(\"GitHub\")"))
        XCTAssertTrue(app.contains("SecureField(\"GitHub API token"))
        XCTAssertTrue(app.contains("Connect GitHub"))
        XCTAssertTrue(app.contains("HyphaGitHubConnectionModel"))
        XCTAssertFalse(sheet.contains("SecureField(\"GitHub API token"))
    }
}
