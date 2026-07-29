import Foundation
import XCTest
@testable import ZenithMacOSClientCore

final class HyphaChatLiveEdgePolicyTests: XCTestCase {
    func testOpeningRoomStartsAtLiveEdgeAndRequestsLatestEvent() {
        var state: HyphaChatLiveEdgePolicy.State?

        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .roomOpened(roomID: "room-a", eventCount: 3)
        )

        XCTAssertEqual(decision, .init(autoScrollToLatest: true, showsNewMessageAffordance: false))
        XCTAssertEqual(
            state,
            .init(roomID: "room-a", eventCount: 3, isAtLiveEdge: true, showsNewMessageAffordance: false)
        )
    }

    func testNewEventsAutoScrollWhenAlreadyAtLiveEdge() {
        var state = openedRoom()

        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .eventsUpdated(roomID: "room-a", eventCount: 4)
        )

        XCTAssertEqual(decision, .init(autoScrollToLatest: true, showsNewMessageAffordance: false))
        XCTAssertTrue(state?.isAtLiveEdge == true)
    }

    func testNewEventsPreserveHistoryPositionAndShowAffordance() {
        var state = openedRoom()
        _ = HyphaChatLiveEdgePolicy.reduce(state: &state, event: .liveEdgeChanged(false))

        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .eventsUpdated(roomID: "room-a", eventCount: 4)
        )

        XCTAssertEqual(decision, .init(autoScrollToLatest: false, showsNewMessageAffordance: true))
        XCTAssertTrue(state?.isAtLiveEdge == false)
    }

    func testJumpToLatestReturnsToFollowingAndClearsAffordance() {
        var state = openedRoom()
        _ = HyphaChatLiveEdgePolicy.reduce(state: &state, event: .liveEdgeChanged(false))
        _ = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .eventsUpdated(roomID: "room-a", eventCount: 4)
        )

        let decision = HyphaChatLiveEdgePolicy.reduce(state: &state, event: .jumpToLatest)

        XCTAssertEqual(decision, .init(autoScrollToLatest: true, showsNewMessageAffordance: false))
        XCTAssertTrue(state?.isAtLiveEdge == true)
    }

    func testOpeningDifferentRoomResetsHistoryStateAndAffordance() {
        var state = openedRoom()
        _ = HyphaChatLiveEdgePolicy.reduce(state: &state, event: .liveEdgeChanged(false))
        _ = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .eventsUpdated(roomID: "room-a", eventCount: 4)
        )

        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .roomOpened(roomID: "room-b", eventCount: 2)
        )

        XCTAssertEqual(decision, .init(autoScrollToLatest: true, showsNewMessageAffordance: false))
        XCTAssertEqual(
            state,
            .init(roomID: "room-b", eventCount: 2, isAtLiveEdge: true, showsNewMessageAffordance: false)
        )
    }

    func testEventUpdateForInactiveRoomDoesNotChangeCurrentRoom() {
        var state = openedRoom()

        let decision = HyphaChatLiveEdgePolicy.reduce(
            state: &state,
            event: .eventsUpdated(roomID: "room-b", eventCount: 8)
        )

        XCTAssertEqual(decision, .init(autoScrollToLatest: false, showsNewMessageAffordance: false))
        XCTAssertEqual(state, openedRoom())
    }

    func testEmptyStateUsesDesignTokensAndAccessibleEncryptedRoomCopy() throws {
        let sourceURL = repositoryRoot
            .appendingPathComponent("Sources/ZenithMacOSClient/Chat/HyphaChatEmptyState.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Your encrypted room is ready"))
        XCTAssertTrue(source.contains("Start the conversation"))
        XCTAssertTrue(source.contains("ZenithDesign.Typography"))
        XCTAssertTrue(source.contains("ZenithDesign.Palette"))
        XCTAssertTrue(source.contains("ZenithDesign.Space"))
        XCTAssertTrue(source.contains("matrix.chat.empty-state"))
        XCTAssertTrue(source.contains("matrix.chat.empty-state.title"))
        XCTAssertTrue(source.contains("matrix.chat.empty-state.message"))
    }

    private func openedRoom() -> HyphaChatLiveEdgePolicy.State? {
        .init(
            roomID: "room-a",
            eventCount: 3,
            isAtLiveEdge: true,
            showsNewMessageAffordance: false
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
