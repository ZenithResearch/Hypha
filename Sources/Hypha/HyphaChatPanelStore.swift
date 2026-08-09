import HyphaCore
import SwiftUI

@MainActor
final class HyphaChatPanelStore: ObservableObject {
    @Published private(set) var state = HyphaChatPanelState()

    var activeRoomID: String? { state.activeRoomID }
    var presentation: HyphaChatPanelPresentation { state.presentation }

    func send(_ action: HyphaChatPanelAction) {
        var next = state
        HyphaChatPanelReducer.reduce(state: &next, action: action)
        guard next != state else { return }
        state = next
    }
}
