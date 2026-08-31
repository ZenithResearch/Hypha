# Hypha

`SPDX-License-Identifier: AGPL-3.0-or-later`

Hypha is Zenith Research's native Apple-platform client for Zenith on macOS, iPhone, and iPad. It is intended to grow into a broader sovereign interface for participating in Zenith and Castalia. Matrix chat is the first implemented capability, not the product boundary.

## Product boundary

The app is a standalone human Zenith client, not part of the ZenithOS daemon/UI bundle. Swift and SwiftUI own the native Apple-platform shells. Capabilities remain isolated behind narrow adapters so Matrix does not become Hypha's product architecture. For the first implemented capability, the official Matrix Rust SDK owns Matrix networking, sync, Olm/Megolm, crypto storage, device trust, and recovery state.

Current Matrix capability:

- configurable HTTPS Matrix homeserver with loopback-only HTTP development support;
- password sign-in and capability-gated invite-token registration;
- per-username Matrix passwords saved through the platform's protected credential store under the human-readable service `Hypha`;
- durable session/device restoration with Keychain-backed crypto-store material;
- joined and invited rooms;
- private, invite-only encrypted room creation;
- encrypted text history and live messages;
- encrypted text send with no plaintext downgrade;
- Matrix room repository attachments with a shared remote repository URL and local-only security-scoped repository paths;
- content-first rooms whose draggable global left sheet contextually swaps from workspace navigation to the selected room’s thread, while roomless chat access opens a searchable global directory and the main room dashboard remains stable;
- optional, explicitly confirmed local builds from the repository root, with commands entered in Hypha or read from local `out/out.json`;
- every renderable existing output discovered under `out/` when no build command is provided, with an in-room asset picker when several outputs exist;
- room-content PowerPoint (`.pptx`), PDF, HTML, image, rendered Markdown, and text output viewers, kept out of repository settings;
- first-device cross-signing and Matrix Secure Backup setup with a one-time recovery key;
- Matrix Secure Backup recovery-key restoration on additional devices;
- explicit session-expiry, undecryptable, trust, verification, and recovery states;
- Hypha-to-Hypha encrypted chat as the primary Matrix interoperability path.

Device verification and encryption recovery remain visible security capabilities, but they are not prerequisites for encrypted room creation or current encrypted chat. A proven invalid-signature or active identity-compromise state still fails closed. Element is an optional compatibility probe, not an authority, prerequisite, or release gate. Restart, verification, and recovery conformance evidence is tracked separately and is not claimed here.

Not included: ZenithOS integration, Sophia/appservice credentials, Dregg/Hub authority, Rolodex, calls, Matrix message-file attachments, reactions, public-room creation, broad room administration, or Element feature parity.

## Why a separate app

A temporary ZenithOS development-package smoke crashed because a dynamic `libMatrixRustSDK.dylib` was not embedded. It was a packaging error, not a size or memory crash. Static release packaging subsequently launched successfully. The Rust SDK makes the app materially larger (roughly 120–132 MB in local release proofs), but that is acceptable for the current focused desktop Matrix capability and is separate from the crash cause.

A standalone app keeps human credentials and capability state away from ZenithOS/Sophia authority, gives Hypha a normal macOS lifecycle, and lets future Apple clients share product behavior without coupling either to the operating-system shell. Matrix remains one bounded capability within that larger client.

## Glossary

- **Hypha:** this native macOS, iPhone, and iPad human client.
- **Zenith:** the broader user-owned network and product ecosystem Hypha is designed to participate in.
- **Castalia:** Zenith's permissioned homeserver-syndicate architecture; it is future integration context, not an authority implemented by this client.
- **Matrix Rust SDK:** the pinned upstream SDK that exclusively owns Matrix networking, rooms, sync, devices, and E2EE state below Hypha's adapter boundary.
- **E2EE:** client-side end-to-end encryption using Matrix Olm/Megolm; Hypha does not add a plaintext fallback for encrypted rooms.

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
HYPHA_DEFAULT_HOMESERVER=https://matrix.example.org ./build-app.sh
open Hypha.app
```

`HYPHA_DEFAULT_HOMESERVER` is the single default-homeserver configuration key. It
must contain an HTTPS URL. At runtime it overrides a packaged default; at build
time `build-app.sh` records it as `HyphaDefaultHomeserver` in the app bundle so a
normal Finder launch receives the same setting. If neither value is present or
the explicit environment value is invalid, Hypha leaves the homeserver
unconfigured and shows the chooser. A homeserver previously selected by the user
is restored before this first-run default, so changing a deployment default does
not silently move existing accounts. The value is a public endpoint, never a
credential.

For an unpackaged development launch, provide the same key to `swift run Hypha`.

## Repository output contract

An attached room shares the remote repository URL and fixed `out/` contract through Matrix room state. Each Mac separately chooses its local checkout. The local build command is optional: with no command, Hypha loads every supported file from `<repo>/out`. If the manifest selects a primary output, that output opens first while the remaining supported assets stay available in the room-content picker.

`out/out.json` can select one legacy output or declare a versioned, ordered artifact set with stable IDs, titles, MIME hints, constrained renderers, and a bounded HTML bundle root. The normative contract and compatibility rules are in [`docs/repository-output-contract.md`](docs/repository-output-contract.md); the machine-readable writer contract is [`docs/out.schema.json`](docs/out.schema.json), with a canonical [`docs/examples/out.v2.json`](docs/examples/out.v2.json) example.

A version-2 PowerPoint artifact uses the slideshow route while mirroring its primary through the old-reader fields:

```json
{
  "version": 2,
  "primary": "deck",
  "artifacts": [
    {
      "id": "deck",
      "title": "Quarterly deck",
      "path": "slides/deck.pptx",
      "format": "pptx",
      "viewer": "slideshow"
    }
  ],
  "viewer": "quickLook",
  "path": "slides/deck.pptx",
  "format": "pptx"
}
```

Version-1 manifests with only `build`, `viewer`, `path`, and `format` remain readable. Any command from the UI or a user-selected local manifest requires explicit confirmation before local execution. Remote, cached, or Matrix-loaded content ignores `build`; local paths and commands are never published to Matrix.

Repository settings only bind the local checkout, remote identity, optional command, and output contract. Builds and output viewers run from the room's content dashboard. A global chat store independently owns the active room reference, the current leading sheet, and main-view presentation. The application shell—not room content—gives the native draggable `NavigationSplitView` sidebar three explicit states: workspace navigation, a Messages-inspired global directory, and the selected room’s timeline/composer. The contextual chat control opens the selected room’s chat in that leading sheet while keeping the room dashboard in the main surface; only a roomless workspace opens the global directory. There are no sidebar tabs and no simultaneous trailing chat column. Compact, accessible chat, repository, security, and Settings controls sit beside the native drawer icon instead of depending on focus-sensitive custom application-menu commands. Markdown uses a dedicated bounded renderer rather than the raw monospaced text viewer.

GitHub is connected globally from Settings, not separately for each room. Until the Hypha Git GitHub App/device flow is available, Settings accepts a fine-grained personal access token as a temporary fallback, validates the GitHub account, clears the input before the request, and holds the token only in memory for the current app session. A room's Repository control can then verify read access to a private `github.com` remote without receiving or storing a credential. Tokens are never persisted or published to Matrix. The selected checkout remains local; Hypha does not silently clone, fetch, or pull it.

Generate and build the iPhone/iPad project with XcodeGen:

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project HyphaMobile.xcodeproj -scheme HyphaMobile \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO \
  HYPHA_DEFAULT_HOMESERVER=https://matrix.example.org build
```

The generated `HyphaMobile` target supports iPhone and iPad and uses bundle identifier `ca.zenithresearch.ios.client`. Device builds require the Zenith Research development team and normal Xcode provisioning.

The packaged app uses an exact, checksum-pinned Matrix Rust SDK binary built from the documented Zenith fork commit. Git keeps only its LFS pointer as the source-tree receipt; `scripts/hydrate-matrix-sdk.sh` downloads the matching public source-release asset over HTTPS and rejects any bytes that do not match the reviewed SHA-256. `build-app.sh`, CI, releases, and the in-app updater all invoke that same fail-closed hydration path, so canonical builds do not depend on Git LFS bandwidth. Its source commits, macOS 26.4 build boundary, regression tests, distribution URL, and checksum are recorded in [`Vendor/MatrixRustSDK/PROVENANCE.md`](Vendor/MatrixRustSDK/PROVENANCE.md). It never offers a synthetic room or plaintext fallback. Invite-token account creation is shown only when the connected homeserver's registration UIA advertises `m.login.registration_token`; otherwise the sign-in surface does not solicit an invite token.

### One-time local identity migration

The bundle identity changed to `ca.zenithresearch.macos.client`. Before first launch of the renamed bundle on a Mac that ran the legacy development build, quit both clients and run:

```bash
xcrun swift scripts/migrate_legacy_local_identity.swift
```

The tool copies the sandboxed encrypted Matrix store, homeserver preference, and Keychain records into the renamed identity without printing secret values. It verifies the renamed Keychain records and keeps the legacy container as a rollback copy. Distribution outside this development workflow requires an installer or updater that performs the same migration before launching the renamed sandbox.

## Releases

Downloadable builds are published on [GitHub Releases](https://github.com/ZenithResearch/Hypha/releases) only after the live two-account encryption gate and checksum verification pass. The current free distribution channel is explicitly ad-hoc signed and not Apple-notarized, so macOS requires a one-time **Open Anyway** approval. Every release page includes that warning, checksum instructions, and source archives. See the [release process](docs/release.md) for the exact automation and security boundary.

## Security and interoperability

- [Security model](docs/security-model.md)
- [Cross-signing and device-verification diagnosis](docs/cross-signing-diagnosis.md)
- [FAQ](docs/faq.md)

Security reports should follow [`SECURITY.md`](SECURITY.md). Contributions should follow [`CONTRIBUTING.md`](CONTRIBUTING.md).

## License

Hypha is free software licensed under **GNU AGPL v3 or later**. See [`LICENSE`](LICENSE). Vendored components retain their own compatible licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/`](LICENSES/).
