/// Deterministic policy for deciding whether a room timeline should follow its live edge.
public enum HyphaChatLiveEdgePolicy {
    public struct State: Equatable, Sendable {
        public var roomID: String
        public var eventCount: Int
        public var isAtLiveEdge: Bool
        public var showsNewMessageAffordance: Bool

        public init(
            roomID: String,
            eventCount: Int,
            isAtLiveEdge: Bool,
            showsNewMessageAffordance: Bool
        ) {
            self.roomID = roomID
            self.eventCount = eventCount
            self.isAtLiveEdge = isAtLiveEdge
            self.showsNewMessageAffordance = showsNewMessageAffordance
        }
    }

    public enum Event: Equatable, Sendable {
        case roomOpened(roomID: String, eventCount: Int)
        case eventsUpdated(roomID: String, eventCount: Int)
        case liveEdgeChanged(Bool)
        case jumpToLatest
    }

    public struct Decision: Equatable, Sendable {
        public var autoScrollToLatest: Bool
        public var showsNewMessageAffordance: Bool

        public init(autoScrollToLatest: Bool, showsNewMessageAffordance: Bool) {
            self.autoScrollToLatest = autoScrollToLatest
            self.showsNewMessageAffordance = showsNewMessageAffordance
        }
    }

    @discardableResult
    public static func reduce(state: inout State?, event: Event) -> Decision {
        switch event {
        case let .roomOpened(roomID, eventCount):
            state = State(
                roomID: roomID,
                eventCount: eventCount,
                isAtLiveEdge: true,
                showsNewMessageAffordance: false
            )
            return Decision(autoScrollToLatest: true, showsNewMessageAffordance: false)

        case let .eventsUpdated(roomID, eventCount):
            guard var current = state, current.roomID == roomID else {
                return Decision(autoScrollToLatest: false, showsNewMessageAffordance: false)
            }

            let receivedNewEvents = eventCount > current.eventCount
            current.eventCount = eventCount

            if receivedNewEvents, current.isAtLiveEdge {
                current.showsNewMessageAffordance = false
                state = current
                return Decision(autoScrollToLatest: true, showsNewMessageAffordance: false)
            }

            if receivedNewEvents {
                current.showsNewMessageAffordance = true
            }
            state = current
            return Decision(
                autoScrollToLatest: false,
                showsNewMessageAffordance: current.showsNewMessageAffordance
            )

        case let .liveEdgeChanged(isAtLiveEdge):
            guard var current = state else {
                return Decision(autoScrollToLatest: false, showsNewMessageAffordance: false)
            }

            current.isAtLiveEdge = isAtLiveEdge
            if isAtLiveEdge {
                current.showsNewMessageAffordance = false
            }
            state = current
            return Decision(
                autoScrollToLatest: false,
                showsNewMessageAffordance: current.showsNewMessageAffordance
            )

        case .jumpToLatest:
            guard var current = state else {
                return Decision(autoScrollToLatest: false, showsNewMessageAffordance: false)
            }

            current.isAtLiveEdge = true
            current.showsNewMessageAffordance = false
            state = current
            return Decision(autoScrollToLatest: true, showsNewMessageAffordance: false)
        }
    }
}
