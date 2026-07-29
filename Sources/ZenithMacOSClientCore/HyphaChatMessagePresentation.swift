import Foundation

public struct HyphaChatMessagePresentation: Equatable, Sendable {
    public enum Direction: Equatable, Sendable {
        case own
        case peer
    }

    public enum DisplayContent: Equatable, Sendable {
        case text(String)
        case undecryptable(reason: String)
        case unsupported(type: String)
    }

    public struct Authenticity: Equatable, Sendable {
        public enum Severity: Equatable, Sendable {
            case warning
            case critical
        }

        public let severity: Severity
        public let label: String

        public init(severity: Severity, label: String) {
            self.severity = severity
            self.label = label
        }
    }

    public let direction: Direction
    public let senderDisplayName: String
    public let showsSender: Bool
    public let isGroupedWithPrevious: Bool
    public let isGroupedWithNext: Bool
    public let timestampLabel: String
    public let displayContent: DisplayContent
    public let authenticity: Authenticity?

    public init(
        event: MatrixTimelineEvent,
        previousEvent: MatrixTimelineEvent? = nil,
        nextEvent: MatrixTimelineEvent? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        direction = event.isOwn ? .own : .peer
        senderDisplayName = event.senderDisplayName
        isGroupedWithPrevious = Self.canGroup(event, with: previousEvent)
        isGroupedWithNext = Self.canGroup(event, with: nextEvent)
        showsSender = !event.isOwn && !isGroupedWithPrevious

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        timestampLabel = formatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1_000)
        )
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{00A0}", with: " ")

        switch event.content {
        case let .text(body):
            displayContent = .text(body)
        case let .undecryptable(reason):
            displayContent = .undecryptable(reason: reason)
        case let .unsupported(type):
            displayContent = .unsupported(type: type)
        }

        authenticity = Self.authenticityPresentation(for: event.authenticity)
    }

    private static func canGroup(
        _ event: MatrixTimelineEvent,
        with adjacentEvent: MatrixTimelineEvent?
    ) -> Bool {
        guard let adjacentEvent else { return false }
        return event.isOwn == adjacentEvent.isOwn
            && event.senderDisplayName == adjacentEvent.senderDisplayName
    }

    private static func authenticityPresentation(
        for authenticity: MatrixEventAuthenticity
    ) -> Authenticity? {
        switch authenticity {
        case .noWarning:
            nil
        case .authenticityNotGuaranteed:
            Authenticity(
                severity: .warning,
                label: "Message authenticity cannot be guaranteed"
            )
        case .unknownDevice:
            Authenticity(
                severity: .warning,
                label: "Encrypted by an unknown device"
            )
        case .unsignedDevice:
            Authenticity(
                severity: .warning,
                label: "Encrypted by a device not verified by its owner"
            )
        case .unverifiedIdentity:
            Authenticity(
                severity: .warning,
                label: "The sender's Matrix identity is not verified"
            )
        case .verificationViolation:
            Authenticity(
                severity: .critical,
                label: "The sender's verified Matrix identity changed"
            )
        case .mismatchedSender:
            Authenticity(
                severity: .critical,
                label: "The encrypted session does not match the event sender"
            )
        case .sentInClear:
            Authenticity(
                severity: .critical,
                label: "Sent without encryption in an encrypted room"
            )
        }
    }
}
