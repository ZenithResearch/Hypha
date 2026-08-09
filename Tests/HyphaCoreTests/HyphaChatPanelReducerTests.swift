import XCTest
@testable import HyphaCore

final class HyphaChatPanelReducerTests: XCTestCase {
    func testPanelTransitionsKeepTheActiveChatReferenceGlobal() {
        var state = HyphaChatPanelState()

        XCTAssertEqual(state.sidebarSheet, .navigation)
        XCTAssertEqual(state.mainPresentation, .content)

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-a"))
        XCTAssertEqual(state.activeRoomID, "room-a")
        XCTAssertEqual(state.sidebarSheet, .navigation)

        HyphaChatPanelReducer.reduce(state: &state, action: .showChatSheet)
        XCTAssertEqual(state.sidebarSheet, .chat)
        XCTAssertEqual(state.mainPresentation, .content)

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-b"))
        XCTAssertEqual(state.activeRoomID, "room-b")
        XCTAssertEqual(state.sidebarSheet, .chat)

        HyphaChatPanelReducer.reduce(state: &state, action: .showMain)
        XCTAssertEqual(state.mainPresentation, .chat)
        XCTAssertEqual(state.sidebarSheet, .chat)

        HyphaChatPanelReducer.reduce(state: &state, action: .showNavigationSheet)
        XCTAssertEqual(state.sidebarSheet, .navigation)
        XCTAssertEqual(state.mainPresentation, .chat)

        HyphaChatPanelReducer.reduce(state: &state, action: .showContent)
        XCTAssertEqual(state.mainPresentation, .content)
        XCTAssertEqual(state.activeRoomID, "room-b")
    }

    func testPanelCannotOpenWithoutAnActiveChatAndClearResetsEverything() {
        var state = HyphaChatPanelState()

        HyphaChatPanelReducer.reduce(state: &state, action: .showChatSheet)
        XCTAssertEqual(state, HyphaChatPanelState())

        HyphaChatPanelReducer.reduce(state: &state, action: .activate(roomID: "room-a"))
        HyphaChatPanelReducer.reduce(state: &state, action: .showMain)
        XCTAssertEqual(state.mainPresentation, .chat)
        HyphaChatPanelReducer.reduce(state: &state, action: .clear)

        XCTAssertEqual(state, HyphaChatPanelState())
    }

}
