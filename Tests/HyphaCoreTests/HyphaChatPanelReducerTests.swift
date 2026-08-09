import XCTest
@testable import HyphaCore

final class HyphaChatPanelReducerTests: XCTestCase {
    func testPanelTransitionsKeepTheActiveChatReferenceGlobal() {
        var state = HyphaChatPanelState()

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-a"))
        XCTAssertEqual(state.activeRoomID, "room-a")
        XCTAssertEqual(state.presentation, .hidden)

        HyphaChatPanelReducer.reduce(state: &state, action: .showSidebar)
        XCTAssertEqual(state.presentation, .sidebar)

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-b"))
        XCTAssertEqual(state.activeRoomID, "room-b")
        XCTAssertEqual(state.presentation, .sidebar)

        HyphaChatPanelReducer.reduce(state: &state, action: .showMain)
        XCTAssertEqual(state.presentation, .main)

        HyphaChatPanelReducer.reduce(state: &state, action: .showContent)
        XCTAssertEqual(state.presentation, .hidden)
        XCTAssertEqual(state.activeRoomID, "room-b")
    }

    func testPanelCannotOpenWithoutAnActiveChatAndClearResetsEverything() {
        var state = HyphaChatPanelState()

        HyphaChatPanelReducer.reduce(state: &state, action: .showSidebar)
        XCTAssertEqual(state, HyphaChatPanelState())

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-a"))
        HyphaChatPanelReducer.reduce(state: &state, action: .showMain)
        HyphaChatPanelReducer.reduce(state: &state, action: .clear)

        XCTAssertEqual(state, HyphaChatPanelState())
    }

}
