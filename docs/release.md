# Release process

Hypha publishes macOS downloads only from signed semantic-version tags after the production encryption gate has passed.

## Release boundary

A distributable release must satisfy all of the following:

1. The tag uses `vMAJOR.MINOR.PATCH` and points at the workflow commit.
2. The tag version equals `CFBundleShortVersionString` in `Resources/Info.plist`.
3. `release/encryption-gate.json` records a passed live two-account encrypted send, restore, synchronization, and decryption proof, its commit is an ancestor of the tagged commit, and no packaged runtime input has changed since that proof.
4. The complete Swift test suite and public-release policy checks pass on the tagged commit.
5. The app is signed with a Developer ID Application identity for the expected Zenith Research team, a secure timestamp, and Apple's hardened runtime.
6. Apple accepts the app through `notarytool`; the notarization ticket is stapled and validated.
7. Gatekeeper accepts the stapled app.
8. The archive, release metadata, and `SHA256SUMS` verify before upload.

Ad-hoc packages are explicitly marked non-distributable and cannot claim notarization. They are available only for local packaging verification with both `HYPHA_RELEASE_MODE=adhoc` and `HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE=1`.

## Protected release environment

The `release` GitHub environment supplies these secrets:

- `MACOS_CERTIFICATE_P12` — base64-encoded Developer ID Application certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD` — password for the PKCS#12 archive.
- `RELEASE_KEYCHAIN_PASSWORD` — ephemeral CI keychain password.
- `APPLE_API_KEY_P8` — base64-encoded App Store Connect API private key.
- `APPLE_API_KEY_ID` — App Store Connect key identifier.
- `APPLE_API_ISSUER_ID` — App Store Connect issuer identifier.

The workflow creates an ephemeral keychain and credential files, then removes the keychain, PKCS#12 archive, and notarization key in an `always()` cleanup step. It never prints certificate, key, password, or API-key contents.

## Prepare without publishing

Run the ordinary gates and a non-distributable packaging proof:

```bash
swift test
python3 scripts/verify_public_release.py
python3 scripts/test_public_release_verifier.py
python3 scripts/test_release_metadata.py
proof_dir=$(mktemp -d)
HYPHA_RELEASE_MODE=adhoc \
HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE=1 \
HYPHA_RELEASE_ALLOW_UNTAGGED=1 \
scripts/package-release.sh v0.1.0 "$proof_dir"
```

This does not create a tag or GitHub release.

## Publish

Publishing is intentionally tag-only. Once the version and encryption gate are approved, push the exact semantic-version tag. `.github/workflows/release.yml` builds, signs, notarizes, staples, verifies, packages, and creates the GitHub release.

Published assets:

- `Hypha-vMAJOR.MINOR.PATCH-macos-arm64.zip`
- `Hypha-vMAJOR.MINOR.PATCH-release.json`
- `SHA256SUMS`

No release should be created manually from an unsigned local bundle.

## Verify a download

```bash
shasum -a 256 -c SHA256SUMS
codesign --verify --deep --strict --verbose=2 Hypha.app
spctl --assess --type execute --verbose=4 Hypha.app
```

The JSON metadata binds the archive checksum to its source commit, bundle identity, executable, minimum macOS version, signing/notarization status, and encryption-gate evidence.
