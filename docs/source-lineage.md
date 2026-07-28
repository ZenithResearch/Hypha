# Native shell source lineage

The macOS interaction model was derived selectively from an internal Zenith Mobile iOS prototype. Only SDK-neutral interaction and safety invariants were carried forward; private repository history and non-shipping research refs are not part of this public source lineage.

## Port invariants; rewrite implementation

- `Sources/ZenithMobileCore/MatrixAppCoordinator.swift`: preserve signed-out/restoring/rooms/thread/expired routing, password clearing, centralized idempotent session loss, stale-task suppression, deterministic cancellation, and safe errors. Replace polling, pagination, networking, and send ownership with SDK adapter events.
- `Tests/ZenithMobileCoreTests/MatrixCoordinatorTests.swift`: adapt login, malformed restore, password clearing, and idempotent session-loss cases. Soft logout must preserve the SDK crypto store.
- `Tests/ZenithMobileCoreTests/MatrixForegroundLifecycleTests.swift`: preserve cancellation/race intent but rewrite around retained SDK listener/sync handles rather than foreground `/sync` polling.
- `Sources/ZenithMobileCore/MatrixSecureStorage.swift` and `Tests/ZenithMobileCoreTests/MatrixSecureStorageTests.swift`: reuse only the fail-closed storage interface/fake pattern and malformed-record/isolation assertions. Replace the record with SDK-supported session material plus a separately generated random crypto-store key under a new macOS service/account namespace.
- `ZenithMobileIOS/MatrixChatView.swift`: reuse login/error vocabulary, fixed-homeserver disclosure, loading state, and accessibility identifiers; redesign the layout for macOS.
- `ZenithMobileIOS/MatrixShippingViews.swift`: reuse empty/offline/server/expired wording, retry affordances, room lock semantics, and accessibility labels; redesign room/thread composition.
- `ZenithMobileIOS/MatrixSyntheticDependencies.swift`: recreate deterministic scenarios behind the new product adapter, extended for undecryptable, unverified, identity violation, recovery unavailable, and recovery required states.
- `Tests/ZenithMobileCoreTests/MatrixUXContractTests.swift`: adapt state-presence/accessibility assertions to native macOS views.

## Research checklist only

The earlier SDK spike did not approve a shipping dependency. Use these only as API/security checklists:

- `docs/spikes/e2ee-001/api-inventory.md`
- `docs/spikes/e2ee-001/decision-packet.md`

The macOS adapter must revisit client/session APIs, session paths and encrypted store key, sync/room-list services, timelines and unable-to-decrypt callbacks, retained handles, fixed-origin redirects, logging, device trust, verification, and recovery against a corrected exact official release.

## macOS redesign

- Native `NavigationSplitView`: joined/invited room sidebar, selected timeline detail, and toolbar actions for account, verification, recovery, logout, and eventual explicit device forgetting.
- App state remains independent from window state; closing all windows must not be treated as iOS foreground/background sync.
- SDK-derived visible states must eventually include joined versus invited, decrypting, unable-to-decrypt, unverified device/identity, identity-change red shield, recovery unavailable/required/in-progress/completed, expired soft logout preserving the crypto store, and destructive `Forget this device` confirmation.
- SDK timeline diffs own local echo, retry, redactions, pagination, and transaction/event identity. SwiftUI consumes stable Zenith-owned view models only.
- Fixed Synapse remains visible, but fail-closed redirect/origin behavior requires executable SDK evidence.
- macOS Keychain, directory permissions, backup exclusion, corruption behavior, soft logout, and explicit deletion replace iOS file-protection assumptions.

## Do not port

The Matrix Rust SDK supersedes these production paths:

- `Sources/ZenithMobileCore/MatrixURLSessionClient.swift`
- HTTP/network portions of `Sources/ZenithMobileCore/MatrixClient.swift`
- `Sources/ZenithMobileCore/MatrixAuthentication.swift`
- foreground polling from `Sources/ZenithMobileCore/MatrixSync.swift`
- `Sources/ZenithMobileCore/MatrixSendReconciliation.swift`
- handwritten `Sources/ZenithMobileCore/MatrixTimeline.swift`
- corresponding URLSession, timeline, reconciliation, pagination, and shipping-integration tests

Do not copy the iOS Xcode project, screenshot inventory, fixture shell, Dregg, Rolodex, credential-bundle, privileged-action, Hub/secS, Sophia/appservice, or ZenithOS surfaces. Do not introduce a dependency on ZenithOS.

## Current macOS boundary

The current shell implements a fresh SDK-neutral `MatrixChatService` and native state/view models; it does not copy the iOS transport or SDK spike. The future Matrix Rust SDK adapter implements this boundary. Generated SDK/FFI clients, timelines, listeners, and task handles remain below it and do not enter SwiftUI.
