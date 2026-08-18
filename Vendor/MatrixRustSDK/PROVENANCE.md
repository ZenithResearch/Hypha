# Zenith MatrixSDKFFI 26.08.17-zenith.13

Purpose: universal Apple Matrix Rust SDK artifact for Hypha on macOS 26.4 arm64, iOS 18 arm64, and the Apple Silicon iOS 18 Simulator. This fork-only integration preserves the existing authoritative device-trust, recovery-reset, UIAA, room-state, and first-device bootstrap surfaces while adding post-login QR verification between two already signed-in devices.

## Source

- Fork: `bananawalnut/matrix-rust-sdk`
- Integration branch: `fix/hypha-post-login-qr-verification-main`
- Exact source commit: `99d79bdde4bb2ff87c015e50d3537b4f512c5bf5`
- Exact source base: `d28c164ef37cd67723aa565bf5aec9c0cefc3bb8`
- Reviewed post-login QR source diff SHA-256: `16ef3f5f722a0f87b07b9de44c1c749d9d927a1223190871a8231e20ca176208`
- Identity-reset authorization base: `f4889ec898e77d8b8c9013adadd77f3d0901fc2d`
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

## Build

```bash
export MACOSX_DEPLOYMENT_TARGET=26.4
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cargo xtask swift build-framework \
  --release \
  --target aarch64-apple-darwin \
  --target aarch64-apple-ios \
  --target aarch64-apple-ios-sim \
  --ios-deployment-target 18.0 \
  --sequentially
```

The XCFramework contains `macos-arm64`, `ios-arm64`, and `ios-arm64-simulator` libraries. Representative objects report `LC_BUILD_VERSION` values of `MACOS minos 26.4`, `IOS minos 18.0`, and `IOSSIMULATOR minos 18.0`, respectively. Seven generated Swift bindings are byte-identical to the previous artifact; `matrix_sdk_ffi.swift` is the reviewed post-login QR API change and is promoted with the matching native ABI.

The archive was packaged from `bindings/apple/generated` with `COPYFILE_DISABLE=1 /usr/bin/zip -X -qry`, and verification rejects `__MACOSX`, `._*` AppleDouble metadata, absolute paths, and parent traversal entries.

## Verification

- `matrix-sdk` library: 612 passed, 0 failed
- `matrix-sdk-ffi` library: 44 passed, 0 failed
- post-login QR controller tests cover method negotiation, QR generation/scanning state, confirmation, cancellation, and callback lock reentrancy
- password-authenticated identity-reset integration test: 1 passed, 0 failed
- authoritative own-device integration classifications: 4 passed, 0 failed
- password UIAA tests include typed challenge continuation and password non-disclosure
- room-state tests include object validation, collision rejection, tuple uniqueness, and joined/stripped exact lookup
- first-device bootstrap tests include existing-identity no-op, retained UIAA requests, transient retry, concurrent continuation serialization, and interrupted-signature reconciliation
- identity-reset tests include retained-session/current-user authority, updated wrong-password challenges, password and OAuth cancellation races, OAuth single-flight terminal behavior, compatibility for generic Rust callers, drop-safe FFI password zeroization, and single-flight backup finalization
- strict `matrix-sdk-ffi` Clippy passed with only the known unrelated `widget/mod.rs:133` unfulfilled-lint expectation explicitly allowed
- signature diagnostic `Debug` output omits the upload request and signature material
- artifact architecture, deployment target, package linkage, generated bindings, Swift tests, app packaging, and code signature are verified below or by the consuming repository gates

## Artifact

- `MatrixSDKFFI.xcframework.zip`
- SHA-256 / SwiftPM checksum: `bbb53ca9440b5ae11a25adf650cd7ce0fe134ee7c63dcb2da36dda8cf47716f0`
- generated `matrix_sdk_ffi.swift` SHA-256: `6a97878dfe5cb23f20091c9fd6f9097bbba5fb396ad94ee111c4c7fae86ca045`

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

The generated file’s SHA-256 is `fcaea90f82dc3aa6f0ab1761310e19c554ae771829e7a77d167c84128f9e42f2`.
