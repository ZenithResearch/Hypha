import Foundation

public struct MatrixProductConfiguration: Equatable, Sendable {
    public let homeserver: URL
    public let allowsPlaintextFallback: Bool

    public init(homeserver: URL, allowsPlaintextFallback: Bool = false) {
        self.homeserver = homeserver
        self.allowsPlaintextFallback = allowsPlaintextFallback
    }

    public static let production = MatrixProductConfiguration(
        homeserver: URL(string: "https://synapse.zenith-research.ca")!
    )
}

public enum MatrixChatReadiness: Equatable, Sendable {
    case signedOut
    case restoringSession
    case ready
    case sessionExpired
    case recoveryRequired
    case unavailable(reason: String)
}
