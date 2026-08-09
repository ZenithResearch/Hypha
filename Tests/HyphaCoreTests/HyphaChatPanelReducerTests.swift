import XCTest
@testable import HyphaCore

final class HyphaChatPanelReducerTests: XCTestCase {
    func testContextualSelectedRoomOpensItsLeadingChatSheetAndKeepsMainContent() {
        var state = HyphaChatPanelState()
        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-remembered"))
        HyphaChatPanelReducer.reduce(state: &state, action: .showMain)
        HyphaChatPanelReducer.reduce(
            state: &state,
            action: .openContextualChat(selectedRoomID: "room-selected")
        )

        XCTAssertEqual(state.activeRoomID, "room-selected")
        XCTAssertEqual(state.sidebarSheet, .roomChat)
        XCTAssertEqual(state.mainPresentation, .content)
    }

    func testContextualRoomlessActionOpensDirectoryWithoutUsingRememberedRoom() {
        var state = HyphaChatPanelState()
        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-remembered"))

        HyphaChatPanelReducer.reduce(
            state: &state,
            action: .openContextualChat(selectedRoomID: nil)
        )

        XCTAssertEqual(state.sidebarSheet, .chatDirectory)
        XCTAssertEqual(state.mainPresentation, .content)
        XCTAssertEqual(state.activeRoomID, "room-remembered")
    }

    func testGlobalDirectoryCanOpenWithoutAnActiveRoom() {
        var state = HyphaChatPanelState()

        HyphaChatPanelReducer.reduce(state: &state, action: .showChatDirectory)

        XCTAssertEqual(state.sidebarSheet, .chatDirectory)
        XCTAssertNil(state.activeRoomID)
    }

    func testSelectedRoomChatRequiresAnActiveRoom() {
        var state = HyphaChatPanelState(sidebarSheet: .chatDirectory)

        HyphaChatPanelReducer.reduce(state: &state, action: .showRoomChat)

        XCTAssertEqual(state.sidebarSheet, .chatDirectory)
    }

    func testNavigationReturnPreservesRoomAndMainContent() {
        var state = HyphaChatPanelState()
        HyphaChatPanelReducer.reduce(
            state: &state,
            action: .openContextualChat(selectedRoomID: "room-a")
        )

        HyphaChatPanelReducer.reduce(state: &state, action: .showNavigationSheet)

        XCTAssertEqual(state.sidebarSheet, .navigation)
        XCTAssertEqual(state.mainPresentation, .content)
        XCTAssertEqual(state.activeRoomID, "room-a")
    }

    func testClearResetsEveryPresentationDimension() {
        var state = HyphaChatPanelState()
        HyphaChatPanelReducer.reduce(
            state: &state,
            action: .openContextualChat(selectedRoomID: "room-a")
        )

        HyphaChatPanelReducer.reduce(state: &state, action: .clear)

        XCTAssertEqual(state, HyphaChatPanelState())
    }
}
