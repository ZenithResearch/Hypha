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
            "chatPanel.mainPresentation == .chat",
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

    func testContextualChatUsesSelectedRoomSheetAndRoomlessDirectoryInTheLeadingSidebar() throws {
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
            "chatPanel.sidebarSheet",
            "chatNavigationSheet",
            "roomChatSheet",
            "case .roomChat:",
            ".openContextualChat(selectedRoomID: activeRepositoryRoom?.id)",
            "where !room.isSpace && !room.hasInvite",
            "matrix.global.chat-sheet",
            "matrix.room.chat-sheet",
            "matrix.global.chat-search",
            "matrix.global.chat-recents",
            "matrix.global.chat-conversations",
            ".navigationSplitViewColumnWidth(min: 230, ideal: 320, max: 560)",
            "chatPanel.send(",
            "activeRoomID",
            "ToolbarItemGroup(placement: .navigation)",
            "matrix.toolbar.chat",
            "matrix.toolbar.repository",
            "matrix.toolbar.security",
            "matrix.toolbar.settings",
        ] {
            XCTAssertTrue(app.contains(marker), "Missing global sidebar chat contract: \(marker)")
        }
        XCTAssertFalse(app.contains("struct HyphaCommands: Commands"))
        XCTAssertFalse(app.contains(".focusedSceneValue(\\.hyphaCommandActions"))
        XCTAssertFalse(app.contains(".commands { HyphaCommands() }"))
        XCTAssertFalse(app.contains(".inspector(isPresented:"))
        XCTAssertFalse(app.contains("matrix.global.chat-overlay"))
        XCTAssertFalse(app.contains("Picker(\"Sidebar\""))
        XCTAssertFalse(app.contains("matrix.global.sidebar.tabs"))
        XCTAssertFalse(app.contains("showChatNavigationSheet"))
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
            "Rebuild",
            "matrix.room.content.rebuild",
            "@State private var artifacts: [HyphaArtifactSelection]",
            "@State private var selectedArtifactID: String?",
            "loadAvailableOutputs()",
            "ScrollView(.horizontal",
            "LazyHStack",
            "HyphaArtifactGalleryCard",
            "matrix.room.content.output-gallery",
            "matrix.room.content.output-card",
            "result.artifacts",
            "ForEach(artifacts)",
            "selectedArtifactID = selection.id",
        ] {
            XCTAssertTrue(roomContent.contains(marker), "Missing room-content output contract: \(marker)")
        }
        XCTAssertFalse(
            roomContent.contains("Open output"),
            "Available output assets must open from the gallery without starting a build"
        )
        XCTAssertFalse(
            roomContent.contains("artifacts = []\n        selectedArtifactID = nil\n        buildLog = \"\""),
            "Starting a rebuild must not clear the last usable output gallery"
        )
        let loadBody = try XCTUnwrap(
            roomContent.components(separatedBy: "private func load() async").last?
                .components(separatedBy: "private func loadAvailableOutputs()").first
        )
        XCTAssertFalse(loadBody.contains("builder.build"), "Loading available assets must never start a build")

        let rebuildBody = try XCTUnwrap(
            roomContent.components(separatedBy: "private func runRebuild(command: String)").last?
                .components(separatedBy: "private func beginSecurityScope").first
        )
        XCTAssertTrue(rebuildBody.contains("builder.build"))
        XCTAssertFalse(rebuildBody.contains("artifacts = []"), "A rebuild must preserve usable output on failure")
        for marker in [
            "import PDFKit",
            "import QuickLookUI",
            "PDFView",
            "QLPreviewView",
            "case .quickLook",
            "case .pdf",
            "case .web",
            "case .image",
            "case .markdown",
            "case .text",
            "case .slideshow",
            "HyphaSlideshowCompatibilityView",
            "HyphaMarkdownArtifactView",
            "HyphaMarkdownParser.blocks",
            "case let .heading",
            "case let .codeBlock",
            "AttributedString(markdown:",
            "selection.bundleRoot",
            "WKContentRuleListStore",
            "ca.zenithresearch.hypha.offline-artifact-v1",
        ] {
            XCTAssertTrue(viewer.contains(marker), "Missing artifact-viewer contract: \(marker)")
        }
        XCTAssertTrue(app.contains("HyphaRoomRepositorySheet"))
        XCTAssertTrue(app.contains("label: \"Repository settings\""))
        XCTAssertTrue(app.contains("repositoryRoom = room"))
        XCTAssertTrue(app.contains("Section(\"GitHub\")"))
        XCTAssertTrue(app.contains("SecureField(\"GitHub API token"))
        XCTAssertTrue(app.contains("Connect GitHub"))
        XCTAssertTrue(app.contains("HyphaGitHubConnectionModel"))
        XCTAssertFalse(sheet.contains("SecureField(\"GitHub API token"))
    }
}
