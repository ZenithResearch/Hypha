import Foundation
import XCTest

final class HyphaChatViewIntegrationSourceTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testChatViewUsesDedicatedSemanticMessageRowsAndEmptyState() throws {
        let app = try source("Sources/Hypha/HyphaApp.swift")
        XCTAssertTrue(app.contains("HyphaChatMessageRow("))
        XCTAssertTrue(app.contains("HyphaChatEmptyState("))
    }

    func testChatViewDefinesLiveEdgeAndJumpToLatestBehavior() throws {
        let app = try source("Sources/Hypha/HyphaApp.swift")
        XCTAssertTrue(app.contains("ScrollViewReader"))
        XCTAssertTrue(app.contains("HyphaChatLiveEdgePolicy"))
        XCTAssertTrue(app.contains("matrix.thread.jump-to-latest"))
    }

    func testSendDoesNotClearDraftBeforeTheOperationSucceeds() throws {
        let app = try source("Sources/Hypha/HyphaApp.swift")
        XCTAssertFalse(
            app.contains("let body = composer\n        composer = \"\"\n        await coordinator.send(body)")
        )
        XCTAssertTrue(app.contains("HyphaMessageDraft"))
    }

    func testComposerExposesSendingDisabledAndFailurePresentation() throws {
        let app = try source("Sources/Hypha/HyphaApp.swift")
        XCTAssertTrue(app.contains("Sending…"))
        XCTAssertTrue(app.contains("disabledReason"))
        XCTAssertTrue(app.contains("matrix.thread.send-failure"))
    }
}
