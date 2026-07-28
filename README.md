# Hypha

`SPDX-License-Identifier: AGPL-3.0-or-later`

Hypha is Zenith Research's native macOS client for Zenith. It is intended to grow into a broader sovereign interface for participating in Zenith and Castalia from the Mac. Matrix chat is the first implemented capability, not the product boundary.

## Product boundary

The app is a standalone human Zenith client, not part of the ZenithOS daemon/UI bundle. Swift and SwiftUI own the native macOS shell. Capabilities remain isolated behind narrow adapters so Matrix does not become Hypha's product architecture. For the first implemented capability, the official Matrix Rust SDK owns Matrix networking, sync, Olm/Megolm, crypto storage, device trust, and recovery state.

Current Matrix capability:

- configurable HTTPS Matrix homeserver with loopback-only HTTP development support;
- password sign-in and capability-gated invite-token registration;
- per-username Matrix passwords saved as generic-password items under the human-readable macOS Keychain service `Hypha` in all builds;
- durable session/device restoration with Keychain-backed crypto-store material;
- joined and invited rooms;
- private, invite-only encrypted room creation;
- encrypted text history and live messages;
- encrypted text send with no plaintext downgrade;
- first-device cross-signing and Matrix Secure Backup setup with a one-time recovery key;
- Matrix Secure Backup recovery-key restoration on additional devices;
- explicit session-expiry, undecryptable, trust, verification, and recovery states;
- Hypha-to-Hypha encrypted chat as the primary Matrix interoperability path.

Device verification and encryption recovery remain visible security capabilities, but they are not prerequisites for encrypted room creation or current encrypted chat. A proven invalid-signature or active identity-compromise state still fails closed. Element is an optional compatibility probe, not an authority, prerequisite, or release gate. Restart, verification, and recovery conformance evidence is tracked separately and is not claimed here.

Not included: ZenithOS integration, Sophia/appservice credentials, Dregg/Hub authority, Rolodex, calls, attachments, reactions, public-room creation, broad room administration, or Element feature parity.

## Why a separate app

A temporary ZenithOS development-package smoke crashed because a dynamic `libMatrixRustSDK.dylib` was not embedded. It was a packaging error, not a size or memory crash. Static release packaging subsequently launched successfully. The Rust SDK makes the app materially larger (roughly 120–132 MB in local release proofs), but that is acceptable for the current focused desktop Matrix capability and is separate from the crash cause.

A standalone app keeps human credentials and capability state away from ZenithOS/Sophia authority, gives Hypha a normal macOS lifecycle, and lets future Apple clients share product behavior without coupling either to the operating-system shell. Matrix remains one bounded capability within that larger client.

## Glossary

- **Hypha:** this native macOS human client.
- **Zenith:** the broader user-owned network and product ecosystem Hypha is designed to participate in.
- **Castalia:** Zenith's permissioned homeserver-syndicate architecture; it is future integration context, not an authority implemented by this client.
- **Matrix Rust SDK:** the pinned upstream SDK that exclusively owns Matrix networking, rooms, sync, devices, and E2EE state below Hypha's adapter boundary.
- **E2EE:** client-side end-to-end encryption using Matrix Olm/Megolm; Hypha does not add a plaintext fallback for encrypted rooms.

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
./build-app.sh
open Hypha.app
```

The packaged app uses a checksummed, repository-local Matrix Rust SDK binary artifact tracked with Git LFS. Run `git lfs pull` after cloning. Its source commits, macOS 26.4 build boundary, regression tests, and checksum are recorded in [`Vendor/MatrixRustSDK/PROVENANCE.md`](Vendor/MatrixRustSDK/PROVENANCE.md). It never offers a synthetic room or plaintext fallback. Invite-token account creation is shown only when the connected homeserver's registration UIA advertises `m.login.registration_token`; otherwise the sign-in surface does not solicit an invite token.

### One-time local identity migration

The bundle identity changed to `ca.zenithresearch.macos.client`. Before first launch of the renamed bundle on a Mac that ran the legacy development build, quit both clients and run:

```bash
xcrun swift scripts/migrate_legacy_local_identity.swift
```

The tool copies the sandboxed encrypted Matrix store, homeserver preference, and Keychain records into the renamed identity without printing secret values. It verifies the renamed Keychain records and keeps the legacy container as a rollback copy. Distribution outside this development workflow requires an installer or updater that performs the same migration before launching the renamed sandbox.

## Security and interoperability

- [Security model](docs/security-model.md)
- [Cross-signing and device-verification diagnosis](docs/cross-signing-diagnosis.md)
- [FAQ](docs/faq.md)

Security reports should follow [`SECURITY.md`](SECURITY.md). Contributions should follow [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Hypha is free software licensed under **GNU AGPL v3 or later**. See [`LICENSE`](LICENSE). Vendored components retain their own compatible licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/`](LICENSES/).
