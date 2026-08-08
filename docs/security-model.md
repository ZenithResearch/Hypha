# Security model

- Human Matrix identity is separate from Sophia/appservice, Dregg, Hub, and ZenithOS authority.
- Matrix Rust SDK manages Olm/Megolm; this repository never implements custom Matrix cryptography.
- Access/refresh tokens, device/session metadata, random store keys, cross-signing/recovery material, registration tokens, account passwords, and crypto-store secrets never enter logs, screenshots, fixtures, repository files, or UserDefaults.
- Successful sign-in and invite-registration passwords are persisted in all builds as per-username generic-password items under the human-readable macOS Keychain service `Hypha`; only Keychain receives the reusable password value, and UI password state is cleared before network requests.
- Recovery keys and invite tokens use one-line obfuscated fields, are cleared from SwiftUI state before awaiting the live request, and are not persisted by the app.
- Invite registration is capability-gated on the homeserver advertising a token-only UIA flow. The client rejects redirects, unsupported UIA stages, and changed response origins; it requests `inhibit_login` so registration does not create an unused Matrix device session.
- First-device cross-signing bootstrap is explicit and non-destructive: it never resets an existing server identity, retains UIAA requests in the SDK handle, clears the password field before awaiting continuation, and trusts success only after fresh server signature confirmation.
- Synapse administrator credentials and the registration shared secret remain server/operator-only and are never shipped in the client.
- Production homeserver is normalized HTTPS. Loopback HTTP is permitted only in explicit development configuration.
- Missing/corrupt crypto state fails closed into recovery/reset UI; it is never silently recreated.
- Recovery setup waits for room-key backup upload and returns the generated key only to a privacy-sensitive one-time sheet. The key is not logged, persisted, auto-copied, or retained after that sheet closes.
- Encrypted-room failure never falls back to plaintext or silently excludes unverified recipient devices.
- Device verification and encryption recovery are optional security capabilities, not prerequisites for encrypted room creation or current encrypted chat.
- Unsigned, unavailable-trust, and recovery-incomplete states remain visible guidance without becoming chat authority. Proven invalid-signature identity violations block room creation and sends before service mutation until explicitly reviewed.
- The packaged app is audited for unresolved non-system dynamic libraries before signing.
- A room repository attachment publishes only its repository name, optional Git origin, and fixed `out/`/`out.json` contract as Matrix room state. Local filesystem paths, security-scoped bookmarks, and build commands remain device-local and are never placed in Matrix events.
- Local repository access is user-selected and security-scoped. Hypha executes a build command only after an explicit confirmation and runs it from the selected repository root with the user's own permissions; room state can never supply or trigger a command.
- Output discovery is confined to `<repo>/out`, rejects manifest and symlink traversal, and renders only formats in the supported-type map. HTML previews disable JavaScript, use a non-persistent web data store, and deny network or out-of-directory navigation.
