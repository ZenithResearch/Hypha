import Foundation

public enum HyphaSidebarSheet: Equatable, Sendable {
    case navigation
    case chat
}

public enum HyphaMainPresentation: Equatable, Sendable {
    case content
    case chat
}

public struct HyphaChatPanelState: Equatable, Sendable {
    public var activeRoomID: String?
    public var sidebarSheet: HyphaSidebarSheet
    public var mainPresentation: HyphaMainPresentation

    public init(
        activeRoomID: String? = nil,
        sidebarSheet: HyphaSidebarSheet = .navigation,
        mainPresentation: HyphaMainPresentation = .content
    ) {
        self.activeRoomID = activeRoomID
        self.sidebarSheet = sidebarSheet
        self.mainPresentation = mainPresentation
    }
}

public enum HyphaChatPanelAction: Equatable, Sendable {
    case activate(roomID: String)
    case showNavigationSheet
    case showChatSheet
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
        case .showNavigationSheet:
            state.sidebarSheet = .navigation
        case .showChatSheet:
            guard state.activeRoomID != nil else { return }
            state.sidebarSheet = .chat
        case .showMain:
            guard state.activeRoomID != nil else { return }
            state.mainPresentation = .chat
        case .showContent:
            state.mainPresentation = .content
        case .clear:
            state = HyphaChatPanelState()
        }
    }
}
