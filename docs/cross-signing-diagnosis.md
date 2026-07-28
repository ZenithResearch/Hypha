# Cross-signing and device-verification diagnosis

Status: source-grounded diagnosis against `matrix-rust-components-swift` 26.05.13 and matrix-rust-sdk `f50309786e5d4019d7d73f4b126483f68068f785`.

## Boundaries

Cross-signing identity and device trust are account-wide. Megolm message keys are room/session-specific. Creating a room can establish new room sessions, but it cannot verify a device, restore the account identity, or recover historical room keys.

Account recovery now covers both onboarding directions:

- a first trusted Zenith device can enable Matrix Recovery and Secure Backup, wait for room-key upload, and show the generated key once;
- an additional device uses `recoverAndFixBackup` to recover cross-signing secrets and repair inconsistent backup state.

Recovery setup and restoration are independent of direct SAS interoperability.

## Confirmed cross-signing issues

### 1. Hypha cannot receive a Hypha-to-Hypha verification request

`MatrixRustLiveClient` creates `SessionVerificationController` only when the local user initiates `requestDeviceVerification()`. It does not retain a controller for incoming requests. In addition, `MatrixSASVerificationSession.didReceiveVerificationRequest` is empty.

Consequences:

- another Zenith device has no complete incoming request path;
- the app does not acknowledge the sender/flow ID;
- it cannot expose an incoming consent UI or call `acceptVerificationRequest()`;
- direct Hypha-to-Hypha SAS is therefore incomplete even if the outgoing path works with another implementation.

This is the primary product gap after recovery. A persistent verification coordinator must own one controller per signed-in client, route incoming request details to UI, and implement explicit acknowledge/accept/decline behavior.

### 2. The pinned FFI contains a confirmed delegate deadlock

The pinned `session_verification.rs` invokes every delegate callback while holding an `RwLock` read guard. A delegate that detaches itself via `setDelegate(nil)` needs the same lock's write guard.

Zenith clears its retained verification session after terminal continuations resume, and `MatrixSASVerificationSession.deinit` calls `setDelegate(nil)`. This creates a potential terminal callback/deinitialization deadlock even if challenge exchange succeeds.

Upstream evidence:

- matrix-rust-sdk issue [#6669](https://github.com/matrix-org/matrix-rust-sdk/issues/6669)
- fix PR [#6682](https://github.com/matrix-org/matrix-rust-sdk/pull/6682)
- fix commit `4bd5e819302ac5fd0cce86e2ec602a7540247dd5`

The fix merged on 2026-06-24. Available Swift releases 26.05.13 and 26.06.06 predate it, so neither published Swift binary contains the fix. Moving only to 26.06.06 would also violate the current macOS 26.4 host boundary and would not solve this defect.

### 3. Element's flashed failure screen is the unsupported QR-login path, not a SAS challenge

The captured Element Settings → Sessions → Link new device screen says:

- “QR code not supported”
- “Your account provider doesn't support signing into a new device with a QR code.”

No emoji or decimal challenge is rendered in that state. Live homeserver capability evidence explains it:

- `org.matrix.e2e_cross_signing: true`
- `org.matrix.msc4108: false`
- login flows: `m.login.password` and `m.login.application_service`
- no delegated OAuth/OIDC login flow

The Hub Synapse configuration also contains no delegated-auth/MSC4108 setup. Element can briefly render an earlier link-device phase before capability discovery replaces it with the unsupported screen. This is a real homeserver/account-provider limitation, but it is distinct from SAS. MSC4108 QR login is not required for recovery-key onboarding or emoji/decimal SAS.

### 4. Precise accept-to-key suppression branch: pinned Ruma rejects the valid Element event

A bounded live reproduction with a new flow reached the exact internal branch. Element rendered the “Compare emojis” modal with a spinner, but no emoji or decimal values, then sent `m.key.verification.accept`. Zenith's sync received that event immediately and logged:

```text
matrix_sdk_crypto::machine: Received an invalid to-device event:
missing field `method`
event_type="m.key.verification.accept"
```

The event is suppressed in pinned matrix-rust-sdk `crates/matrix-sdk-crypto/src/machine/mod.rs`:

1. `receive_to_device_event` calls `raw_event.deserialize_as()` at line 1542.
2. Deserialization fails because pinned `ruma-events` requires `method` on accept content.
3. Lines 1544–1547 classify it as `ProcessedToDeviceEvent::Invalid` and return.
4. `VerificationMachine::receive_any_event` is never called.
5. Its accept branch therefore never reaches `Sas::receive_any_event`, `SasState<Accepted>::as_content`, or `queue_up_content`.
6. No `m.key.verification.key` request can be generated.

This eliminates the previous candidates:

- the flow and SAS object are not failing lookup; the event is rejected before lookup;
- the outgoing queue is not dropping a generated key; no key is generated;
- the remote key is not missing; the initiator must first process accept and send its key;
- Synapse is not suppressing the event; it is delivered in Zenith's immediate sync response.

The incompatibility is version-specific. The pinned SDK lockfile contains `ruma 0.15.1` and `ruma-events 0.33.0`. Ruma issue [#2494](https://github.com/ruma/ruma/issues/2494) confirms that `m.key.verification.accept` does not have a `method` field in the current Matrix specification. Ruma PR [#2496](https://github.com/ruma/ruma/pull/2496), merge commit `67d27c766ee61eca55707ddad232e57769344e5f`, removes the erroneous requirement.

Element is therefore sending the current protocol shape. The pinned Zenith SDK rejects it because its Ruma dependency predates that correction. The optional Element `msgid` diagnostic is unrelated.

### 5. Patched artifact live validation

Zenith now builds against a macOS 26.4 arm64 SDK artifact containing both the Ruma accept-event correction and the FFI delegate-lock correction. The source provenance and binary checksum are recorded in `Vendor/MatrixRustSDK/PROVENANCE.md`.

A live Zenith-to-Element run on 2026-07-16 crossed every previously blocked boundary. The app's allowlisted stage log recorded:

```text
acceptanceReceived
sasProtocolStarted
challengeReceived
approvalSubmitted
finished
```

This proves that the methodless accept event was deserialized, the key exchange was generated and processed, the SAS challenge reached Swift, approval completed, and the FFI terminal callback returned without deadlocking.

After completion and restart, the app still reported “This Matrix device is not verified” and offered “Restore encryption identity and backed-up room keys.” A forced own-user `/keys/query` then confirmed the authoritative server state: the current device exists and has its normal device self-signature, but it has no signature from the account's current self-signing key. The UI is therefore no longer displaying a stale cached value; the device is not cross-signed on the homeserver.

`SasState::Done` proves that both devices completed the SAS/MAC exchange. It does not guarantee that either side possessed the private self-signing key needed to create and upload a cross-signing signature. The SDK deliberately permits SAS to finish after marking the peer locally verified when `sign_device()` returns `MissingSigningKey`. Zenith must not translate that into `.verified`.

The integrated SDK now forces a fresh own-user keys query before reporting verification state, so the banner will update as soon as a valid self-signing signature exists. For this account, recovery-key restoration—or a trusted peer that actually holds the private self-signing key—is still required before the banner can truthfully become verified.

### 6. Broad SDK tracing is not safe to ship

The temporary reproduction tracing was removed immediately after isolating the branch. Broad `matrix_sdk_crypto=debug` output can include sensitive backup or recovery material, even when HTTP credentials are redacted. Production diagnostics must not enable it.

Any permanent diagnostic layer must emit only an allowlisted event type, flow stage, request class, HTTP status, and sanitized error category. It must never emit access tokens, event bodies, room keys, backup keys, recovery keys, private key material, or raw SDK state.

### 7. Verification state is sampled, not subscribed

Zenith refreshes `verificationState` after sign-in, recovery, or a local verification action. It does not retain the SDK's `verificationStateListener`.

Remote identity changes, remote completion, or trust changes can therefore leave the UI stale until another explicit refresh. The listener should become part of the signed-in client lifecycle and terminate with continuous sync/logout.

## Non-issues and rejected workarounds

- The VPN and homeserver transport are not the observed blocker; sync remains active during failure.
- Emoji comparison is not the blocker; failure occurs before emoji or decimal challenge generation.
- `acknowledgeVerificationRequest` and `acceptVerificationRequest` are not missing from the outgoing initiator sequence; they belong to the incoming flow Zenith has not implemented.
- Calling `startSasVerification()` repeatedly is invalid. Zenith now submits it once, and duplicate callbacks are idempotent.
- Creating a new encrypted room does not repair cross-signing.
- An unauthenticated “Trust anyway” control would be a security downgrade and remains prohibited.

## Recommended fix sequence

1. Use the integrated macOS 26.4 artifact containing Ruma `67d27c766e…` and FFI `4bd5e819…`; preserve its checksum and provenance.
2. Restore the local cross-signing identity with the existing recovery key, or create a clean additional-device session if the current session/store remains inconsistent.
3. Keep broad SDK tracing disabled; use only bounded, allowlisted diagnostics that cannot emit cryptographic material.
4. Implement a persistent incoming verification coordinator and explicit request-consent UI.
5. Subscribe to verification-state changes for the full signed-in lifecycle.
6. Exercise Hypha-to-Hypha recovery, outgoing SAS, incoming SAS, cancellation, mismatch, timeout, and historical Megolm restoration before removing the final Element emergency session.
