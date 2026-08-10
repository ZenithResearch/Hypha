import HyphaCore
import SwiftUI

@MainActor
final class HyphaChatPanelStore: ObservableObject {
    @Published private(set) var state = HyphaChatPanelState()

    var activeRoomID: String? { state.activeRoomID }
    var sidebarSheet: HyphaSidebarSheet { state.sidebarSheet }
    var mainPresentation: HyphaMainPresentation { state.mainPresentation }

    func send(_ action: HyphaChatPanelAction) {
        var next = state
        HyphaChatPanelReducer.reduce(state: &next, action: action)
        guard next != state else { return }
        state = next
    }
}
