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

## MatrixRTC Step 1

- Matrix remains authoritative for accounts, devices, room membership, and future call participation. Transport connectivity cannot substitute for Matrix authority.
- Qualification is fail-closed for missing, malformed, stale, mixed-profile, fallback-only, or incomplete SDK/server evidence. Production remains unsupported.
- Peer evidence distinguishes authenticated, cross-signed, locally SAS-verified, invalid, revoked, unknown, and malformed states. Revoked and invalid evidence are terminal; local SAS evidence cannot repair a missing or invalid current device or cross-signing chain.
- No trust classification grants media-key authority. The policy for a valid cross-signed but not locally SAS-verified peer remains unresolved and is not represented as accepted behavior.
- Secret-kind contracts contain ownership, lifetime, and redaction metadata only. Access tokens, OpenID tokens, sender keys, authorization headers, and transport grants have no values in qualification fixtures or public descriptions.
- The immutable future origin binds account, homeserver, room, device, selected profile, and generation. Navigation never silently rebinds it; account switching requires an explicit Leave and switch or Cancel choice, and a conflicting second call is blocked.
- These are nonruntime contracts. No sender-key operation, transport grant, media connection, permission request, call UI, or production mutation is implemented.
