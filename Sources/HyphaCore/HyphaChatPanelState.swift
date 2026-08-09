import Foundation

public enum HyphaChatPanelPresentation: Equatable, Sendable {
    case hidden
    case inspector
    case main
}

public struct HyphaChatPanelState: Equatable, Sendable {
    public var activeRoomID: String?
    public var presentation: HyphaChatPanelPresentation

    public init(
        activeRoomID: String? = nil,
        presentation: HyphaChatPanelPresentation = .hidden
    ) {
        self.activeRoomID = activeRoomID
        self.presentation = presentation
    }
}

public enum HyphaChatPanelAction: Equatable, Sendable {
    case activate(roomID: String)
    case showInspector
    case showMain
    case showContent
    case clear
}

public enum HyphaChatPanelReducer {
    public static func reduce(
        state: inout HyphaChatPanelState,
        action: HyphaChatPanelAction
    ) {
        switch action {
        case let .activate(roomID):
            guard !roomID.isEmpty else { return }
            state.activeRoomID = roomID
        case .showInspector:
            guard state.activeRoomID != nil else { return }
            state.presentation = .inspector
        case .showMain:
            guard state.activeRoomID != nil else { return }
            state.presentation = .main
        case .showContent:
            state.presentation = .hidden
        case .clear:
            state = HyphaChatPanelState()
        }
    }
}
