/// Synchronous single-flight gate for account authentication and session restoration.
///
/// The owning `@MainActor` model mutates this gate before creating any asynchronous
/// authentication work, so a second route cannot begin while the first operation is suspended.
public struct HyphaAuthenticationOperationGate: Sendable {
    public private(set) var isInFlight = false

    public init() {}

    public mutating func begin() -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        return true
    }

    public mutating func finish() {
        isInFlight = false
    }
}
