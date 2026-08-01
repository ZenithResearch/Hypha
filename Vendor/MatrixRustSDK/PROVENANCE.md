# Zenith MatrixSDKFFI 26.07.23-zenith.10

Purpose: macOS 26.4 arm64 Matrix Rust SDK artifact for the Zenith macOS client. This fork-only integration preserves the existing authoritative device-trust surface while adding password-change UIAA, atomic custom room initial state with exact reconciliation, and non-destructive first-device cross-signing bootstrap.

## Source

- Fork: `bananawalnut/matrix-rust-sdk`
- Integration branch: `zenith/macos-first-client-sdk-integration-20260723`
- Exact source commit: `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`
- Password-change UIAA head (#6783): `533973cb7d918108fa111214575382bfbe30f765`
- Atomic room-state/reconciliation head (#6784): `2ee2199867bb28b723d80b1c6f80315301058c57`
- First-device bootstrap head (#6785): `94f7106f93016e212fe69e9cc6f6d098f6dc71b6`
- Initial integration merge: `1a35497202350c48be5d3728d7626bd02d63b5ca`
- FFI delegate deadlock fix inherited from upstream: `4bd5e819302ac5fd0cce86e2ec602a7540247dd5`
- Ruma methodless SAS accept fix inherited by pinned Ruma `db24422e03aea7c7974230098fe9aeb5481cddc6`: `67d27c766ee61eca55707ddad232e57769344e5f`

### Preserved Zenith authority lineage

The following source commits were ported from the preserved `zenith/macos-26.4-sas-fix` checkout onto the current SDK integration branch:

- Own-device verification refresh: `3932fd4e8bcdb55738920de53e6dd6dad75c07a9` → `d998dcd82`
- Current-device signing after recovery: `238e8745a9103cf0ee071771d7e93e007939cd20` → `59fcb3bf4`
- Cross-signing key-presence status: `f53e2ac81` → `a867c15c5`
- Partial signature-upload failure handling: `c73782cbb` → `5ef31e940`
- One-shot boolean/enum diagnostic receipt: `5f028b9e0` → `3788ae5cc`
- Exact raw server-device signing: `f2f814679` → `bf2b3f168`
- Raw server-signature confirmation: `94640f619` → `8e29384da`
- Classified exact-current-key signature authority: `d4bd226ecc2ff85dad23b90559f46147f62f5786` → `de5853cc0`
- Authoritative own-device trust query and FFI enum: `97fa91b0c756604ef0b03ab9479fc704d1362c55` → `65fee25af`
- Authoritative integration tests: `222981b869ca41f2ef887d1e7932b35bd3fa6a61` → `9018366b0`
- Redacted diagnostic documentation and strict-lint adaptation: `7358eece8`, `f4889ec89`

The `DeviceSignaturePreparation` debug representation intentionally excludes the signature upload request and exposes only non-secret boolean diagnostics.

## MatrixRTC qualification gap

The selected contract is the exact open-MSC snapshot `ca.hypha.matrixrtc.open-msc-snapshot.2026-07-30.2`, fingerprint `630c781b782eb94965fb83767a39247f2d127ac31f0c89065f18711b375f8f6d`. Its mechanically checked comparison is recorded in [`../../docs/matrixrtc/sdk-capability-evidence.json`](../../docs/matrixrtc/sdk-capability-evidence.json).

This pinned artifact exposes notification/decline and earlier observation/OpenID surfaces, including a legacy well-known-backed LiveKit convenience signal. It does not expose the complete selected-profile membership, sticky-map, participant-device, recipient-validation, sender-key, bounded-grant, registered-transport, or native-session surface. That convenience signal is diagnostic evidence only and cannot qualify availability. Both this artifact and current upstream evidence are unsupported for native MatrixRTC joining; this provenance entry adds no runtime, transport, media, or production-readiness claim.

## Build

```bash
export MACOSX_DEPLOYMENT_TARGET=26.4
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CARGO_TARGET_DIR="$PWD/target"
export CARGO_BUILD_JOBS=2
cargo xtask swift build-framework \
  --release \
  --target aarch64-apple-darwin \
  --components-path "$PWD/components"
```

The XCFramework contains one `macos-arm64` library. Representative object `matrix_sdk_ffi.matrix_sdk_ffi.2a926db79d3771b8-cgu.00.rcgu.o` reports `LC_BUILD_VERSION platform MACOS minos 26.4`.

## Verification

- `matrix-sdk` library: 602 passed, 0 failed
- `matrix-sdk-ffi` library: 42 passed, 0 failed
- authoritative own-device integration classifications: 4 passed, 0 failed
- password UIAA tests include typed challenge continuation and password non-disclosure
- room-state tests include object validation, collision rejection, tuple uniqueness, and joined/stripped exact lookup
- first-device bootstrap tests include existing-identity no-op, retained UIAA requests, transient retry, concurrent continuation serialization, and interrupted-signature reconciliation
- strict `matrix-sdk-ffi` Clippy passed with only the known unrelated `widget/mod.rs:133` unfulfilled-lint expectation explicitly allowed
- signature diagnostic `Debug` output omits the upload request and signature material
- artifact architecture, deployment target, package linkage, generated bindings, Swift tests, app packaging, and code signature are verified below or by the consuming repository gates

## Artifact

- `MatrixSDKFFI.xcframework.zip`
- SHA-256 / SwiftPM checksum: `ca8796d0f065ade3787de2f18693afd940914ce2e35f807ccf479d2f14c5c565`
- generated `matrix_sdk_ffi.swift` SHA-256: `7d823dda5f112ebc60887fc0ff238129b49e0173870ad616978f17b3ace5bdbc`

## License

The Matrix Rust SDK’s own code and Zenith fork modifications are distributed under Apache-2.0. The binary also incorporates dependencies under the complete license and attribution set listed in [`../../THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md) and [`../../THIRD_PARTY_LICENSES.html`](../../THIRD_PARTY_LICENSES.html). The Apache-2.0 text is available at [`../../LICENSES/Apache-2.0.txt`](../../LICENSES/Apache-2.0.txt).

The package-specific attribution document was generated with cargo-about 0.9.1 from the exact source checkout:

```bash
cargo about generate \
  --locked --fail \
  --target aarch64-apple-darwin \
  --config /path/to/Hypha/Vendor/MatrixRustSDK/about.toml \
  --manifest-path /path/to/matrix-rust-sdk/bindings/matrix-sdk-ffi/Cargo.toml \
  --output-file /path/to/Hypha/THIRD_PARTY_LICENSES.html \
  /path/to/Hypha/Vendor/MatrixRustSDK/third-party-licenses.hbs
```

The generated file’s SHA-256 is `f1e427b7af156b275595b0dbc78c0dcf1c85aee0240a9b92f856e07d5f55ed61`.
