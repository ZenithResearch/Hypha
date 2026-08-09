import Foundation
import XCTest

final class HyphaRepositoryUISourceContractTests: XCTestCase {
    func testRoomContentStartsPrimaryAndKeepsArtifactViewerOutOfRepositorySettings() throws {
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
            "HyphaRoomContentView",
            "HyphaChatPanelStore",
            "chatPanel.presentation == .main",
            "matrix.global.chat-main",
            "roomContentRefreshID",
            "onDismiss:",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing content-first room workspace contract: \(marker)")
        }
        XCTAssertFalse(
            sheet.contains("HyphaArtifactViewerView"),
            "Repository settings must configure output without rendering it"
        )
    }

    func testGlobalChatStoreOwnsTheRightInspectorOutsideRoomContent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roomContent = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomContentView.swift"),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaApp.swift"),
            encoding: .utf8
        )

        for marker in [
            "@StateObject private var chatPanel",
            "HyphaChatPanelStore",
            ".inspector(isPresented: chatInspectorIsPresented)",
            ".inspectorColumnWidth(",
            "matrix.global.chat-inspector",
            "matrix.global.chat-menu",
            "roomChatInspector",
            "chatPanel.send(",
            "activeRoomID",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing global chat inspector contract: \(marker)")
        }
        for forbidden in [
            "HyphaRoomWorkspaceView",
            "Room view",
            "matrix.room.chat-inspector.toggle",
            "HSplitView",
            ".sheet(isPresented:",
        ] {
            XCTAssertFalse(roomContent.contains(forbidden), "Room content must not own global chat UI: \(forbidden)")
        }
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
        let roomContent = try String(
            contentsOf: root.appendingPathComponent("Sources/Hypha/HyphaRoomContentView.swift"),
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
            XCTAssertTrue(roomContent.contains(marker), "Missing room-content output contract: \(marker)")
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
            "HyphaMarkdownParser.blocks",
            "case let .heading",
            "case let .codeBlock",
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
