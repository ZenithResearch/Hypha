# FAQ

## What caused the ZenithOS crash?

The executable was linked against `@rpath/libMatrixRustSDK.dylib`, but the temporary local development app bundle did not include that dylib. `dyld` aborted before app code ran. It was not an out-of-memory crash and was not caused by the app being 120 MB.

## Is the Rust SDK too large?

It is large compared with a handwritten plaintext client: local optimized static app proofs were roughly 120–132 MB, while local dependency/build caches were much larger and are not shipped. That size is acceptable for a desktop E2EE client if the app remains focused. Correctness and maintained Matrix cryptography matter more than recreating Olm/Megolm to save package size.

## Is the app written in Rust?

The native UI and product state are Swift/SwiftUI. The official Matrix Rust SDK owns the protocol and E2EE implementation through its generated Swift bindings. This keeps the macOS experience native without maintaining custom cryptography.

## Can I recover encryption without SAS verification?

Yes, if Matrix Secure Backup is configured and you have its recovery key. Zenith can restore the account's cross-signing identity and backed-up Megolm room keys through the Matrix Rust SDK. The recovery key is not saved by Zenith. Creating a new encrypted room is not equivalent: it gives this device keys for that new room but does not restore historical keys or verify the device.

On a new account's first Zenith device, use **Set up device security** first. Zenith asks the Matrix Rust SDK to create the cross-signing identity, completes password UIAA without retaining the password, and confirms the current device signature from fresh server state. Then use **Set up recovery** to enable Secure Backup, wait for room keys to upload, and receive the generated recovery key once. Store it in a password manager before acknowledging the sheet. Additional Zenith devices can then recover without Element.

## Must verification or recovery finish before I can chat?

No. They are not prerequisites for encrypted room creation or current encrypted chat. Hypha keeps unsigned, unavailable-trust, and recovery-incomplete states visible as optional security guidance while current encrypted chat remains available. A proven invalid-signature identity violation is different: Hypha blocks room creation and send before mutation and requires review. Hypha-to-Hypha is the primary path; Element is only an optional compatibility probe.

## How does account creation work?

Zenith supports Synapse invite-token registration only. The create-account control appears only after a credential-free capability probe confirms a token-only `m.login.registration_token` UIA flow. Registration inhibits an unused server-created session, then performs one deliberate SDK login with an encrypted local store. The first-run banner offers explicit first-device security bootstrap and recovery setup; neither blocks current encrypted chat unless the authoritative trust check proves an invalid signature. The app never contains a Synapse administrator token or registration shared secret, and unrestricted public registration is not supported.

## Why not keep Matrix in ZenithOS?

A standalone app gives human chat normal application lifecycle, credential isolation, simpler signing/notarization, and direct parity with Zenith Mobile iOS. ZenithOS integration is deferred and can be revisited later from preserved research evidence.
