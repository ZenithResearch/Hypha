# Architecture

## Surfaces

- `Hypha`: native SwiftUI application and macOS lifecycle.
- `HyphaCore`: SDK-neutral product models, state machines, and adapter protocols.
- `MatrixRustSDK` adapter: the sole production owner of Matrix networking, sync, session, crypto store, encrypted timelines, sends, device trust, verification, backup, and recovery.
- Keychain/Application Support: session metadata, random encrypted-store key, and account-scoped durable crypto database.

SwiftUI must not directly retain generated FFI clients, listeners, timelines, or task handles. Adapter callbacks cross onto `MainActor`; retained handles are cancelled deterministically.

## Product authority

The coordinator exposes security guidance separately from chat authority. Unsigned or unavailable trust and incomplete recovery produce guidance without replacing rooms/chat or disabling encrypted room creation and current encrypted send. Only a proven invalid-signature identity violation blocks those operations, and encrypted-room failures never downgrade to plaintext.

First-device setup is an explicit post-login operation. The SDK creates or reconciles cross-signing state non-destructively, retains any UIAA request inside its bootstrap handle, and accepts the account password only for the continuation call. The app reports success only after a fresh authoritative server query says the current device is signed by the current self-signing key.

Hypha-to-Hypha is the primary interoperability boundary. Element may be used as an optional compatibility probe, but it does not define Hypha trust, recovery, or release readiness.

## Native atomic design system

Hypha’s macOS interface keeps reusable presentation under `Sources/Hypha/DesignSystem/`:

- **Atoms** own irreducible interactive treatments such as buttons, pointer/hover/press behavior, text-field styling, and semantic status messages.
- **Molecules** compose atoms into one-purpose interface units such as the authentication identity header and saved-account action card.
- **Organisms** own reusable surface composition such as the scrolling authentication shell, responsive spacing, navigation placement, and background treatment.
- **Views** under `Sources/Hypha/Auth/` select organisms and bind application state. Matrix orchestration, credentials, account routing, and protocol authority remain outside the component library.

The authentication landing, saved-account chooser, manual password sign-in, and invite-token account creation are separate routed views. Registration is exposed only after the credential-free capability probe advertises the exact invite-token flow. Leaving registration clears username, password, confirmation, and invite-token state. Manual password sign-in remains reachable independently of saved sessions or credentials.

## Room removal semantics

Hypha exposes destructive room removal only when the active Matrix account appears in the room's authenticated creator set. Switching accounts recomputes that capability from the active SDK client; one account cannot remove a room on behalf of another.

Removal calls Matrix `leave` and then `forget`, and only then removes the room from Hypha's active list. It is intentionally described as deleting the room **from this account**. This does not physically erase federated history, copies retained by other members or homeservers, or the room for members who remain. A genuine homeserver-wide shutdown/purge is a separate server-administrator operation and is not claimed by the client.

## iOS relationship

The macOS app mirrors accepted Zenith Mobile iOS login/rooms/thread/composer behavior and security states, but is a sibling product surface rather than a second target inside ZenithOS. Port SDK-neutral models and interaction contracts selectively from the reviewed iOS prototype. Do not copy its handwritten URLSession Matrix transport into production E2EE.

Exact reviewed paths, head, ported concepts, and exclusions are recorded in `source-lineage.md`.

## Shipping rule

There is exactly one Matrix session/sync/send/crypto owner. No handwritten-client fallback and no plaintext downgrade in encrypted rooms.
