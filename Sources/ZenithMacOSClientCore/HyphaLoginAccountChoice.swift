import Foundation

public struct HyphaLoginAccountChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayAccount: String
    public let session: MatrixSDKSessionRecord?
    public let credential: HyphaMatrixCredentialDescriptor?

    public static func grouped(
        sessions: [MatrixSDKSessionRecord],
        credentials: [HyphaMatrixCredentialDescriptor]
    ) -> [HyphaLoginAccountChoice] {
        var sessionsByAccount = Dictionary(uniqueKeysWithValues: sessions.map { ($0.accountKey, $0) })
        var credentialsByAccount = Dictionary(uniqueKeysWithValues: credentials.map { ($0.id, $0) })
        let accountKeys = Set(sessionsByAccount.keys).union(credentialsByAccount.keys)

        return accountKeys.map { accountKey in
            let session = sessionsByAccount.removeValue(forKey: accountKey)
            let credential = credentialsByAccount.removeValue(forKey: accountKey)
            return HyphaLoginAccountChoice(
                id: accountKey,
                displayAccount: session?.userId ?? credential?.username ?? accountKey,
                session: session,
                credential: credential
            )
        }.sorted {
            $0.displayAccount.localizedCaseInsensitiveCompare($1.displayAccount) == .orderedAscending
        }
    }
}
