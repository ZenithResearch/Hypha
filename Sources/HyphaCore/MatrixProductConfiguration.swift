import Foundation

public struct MatrixProductConfiguration: Equatable, Sendable {
    public static let defaultHomeserverEnvironmentKey = "HYPHA_DEFAULT_HOMESERVER"
    public static let defaultHomeserverBundleKey = "HyphaDefaultHomeserver"

    public let homeserver: URL
    public let allowsPlaintextFallback: Bool

    public init(homeserver: URL, allowsPlaintextFallback: Bool = false) {
        self.homeserver = homeserver
        self.allowsPlaintextFallback = allowsPlaintextFallback
    }

    public static var configuredDefault: MatrixProductConfiguration? {
        defaultConfiguration(
            environment: ProcessInfo.processInfo.environment,
            bundleValue: Bundle.main.object(forInfoDictionaryKey: defaultHomeserverBundleKey) as? String
        )
    }

    public static func defaultConfiguration(
        environment: [String: String],
        bundleValue: String?
    ) -> MatrixProductConfiguration? {
        if let environmentValue = nonempty(environment[defaultHomeserverEnvironmentKey]) {
            return configuration(from: environmentValue)
        }

        guard let bundleValue = nonempty(bundleValue) else { return nil }
        return configuration(from: bundleValue)
    }

    private static func configuration(from value: String) -> MatrixProductConfiguration? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let homeserver = components.url else {
            return nil
        }

        return MatrixProductConfiguration(homeserver: homeserver)
    }

    private static func nonempty(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
}

public enum MatrixChatReadiness: Equatable, Sendable {
    case signedOut
    case restoringSession
    case ready
    case sessionExpired
    case recoveryRequired
    case unavailable(reason: String)
}
