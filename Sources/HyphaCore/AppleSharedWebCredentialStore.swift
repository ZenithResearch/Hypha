import Foundation
import Security

private typealias SharedWebCredentialCompletion = @convention(block) (CFError?) -> Void

// Security.framework has not yet exposed the macOS replacement named by the
// SDK deprecation annotation, so call the still-supported symbol directly.
@_silgen_name("SecAddSharedWebCredential")
private func HyphaSecAddSharedWebCredential(
    _ domain: CFString,
    _ account: CFString,
    _ password: CFString?,
    _ completion: SharedWebCredentialCompletion
)

public enum AppleSharedWebCredentialError: Error, Equatable, Sendable {
    case invalidInput
    case saveFailed
}

public protocol HyphaSharedWebCredentialStore: Sendable {
    func save(password: String, username: String, domain: String) async throws
}

public final class AppleSharedWebCredentialStore: HyphaSharedWebCredentialStore, @unchecked Sendable {
    public typealias AddCredential = @Sendable (
        _ domain: String,
        _ username: String,
        _ password: String,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) -> Void

    private let addCredential: AddCredential

    public convenience init() {
        self.init { domain, username, password, completion in
            HyphaSecAddSharedWebCredential(
                domain as CFString,
                username as CFString,
                password as CFString
            ) { error in
                completion(error)
            }
        }
    }

    public init(addCredential: @escaping AddCredential) {
        self.addCredential = addCredential
    }

    public static func isAvailable(for domain: String) -> Bool {
        guard validDomain(domain),
              let task = SecTaskCreateFromSelf(nil),
              let associatedDomains = SecTaskCopyValueForEntitlement(
                  task,
                  "com.apple.developer.associated-domains" as CFString,
                  nil
              ) as? [String] else {
            return false
        }
        return associatedDomains.contains("webcredentials:\(domain)")
    }

    public func save(password: String, username: String, domain: String) async throws {
        guard Self.validDomain(domain),
              Self.validSecretField(username),
              Self.validSecretField(password) else {
            throw AppleSharedWebCredentialError.invalidInput
        }
        try await withCheckedThrowingContinuation { continuation in
            addCredential(domain, username, password) { error in
                if error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AppleSharedWebCredentialError.saveFailed)
                }
            }
        }
    }

    private static func validDomain(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.utf8.count <= 253,
              !value.contains("/"),
              !value.contains(":"),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: "https://\(value)"),
              url.host?.lowercased() == value.lowercased() else {
            return false
        }
        return true
    }

    private static func validSecretField(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= 1_024
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
