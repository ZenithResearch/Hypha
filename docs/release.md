# Release process

Hypha publishes macOS downloads only from semantic-version tags after the production encryption gate has passed. The temporary free channel is ad-hoc signed and explicitly non-notarized; Developer ID distribution remains implemented but inactive until Apple credentials are available.

## Release boundary

A distributable release must satisfy all of the following:

1. The tag uses `vMAJOR.MINOR.PATCH` and points at the workflow commit.
2. The tag version equals `CFBundleShortVersionString` in `Resources/Info.plist`.
3. `release/encryption-gate.json` records a passed live two-account encrypted send, restore, synchronization, and decryption proof, its commit is an ancestor of the tagged commit, and no packaged runtime input has changed since that proof.
4. The complete Swift test suite and public-release policy checks pass on the tagged commit.
5. The temporary build is ad-hoc signed and its metadata must explicitly report `notarized: false` and `distributable: false`.
6. The release notes must disclose the missing Apple publisher identity and provide Gatekeeper **Open Anyway** instructions.
7. GitHub provides source archives for the exact release tag.
8. The archive, release metadata, and `SHA256SUMS` verify before upload.

Ad-hoc packages are explicitly marked non-distributable and cannot claim notarization. The current tag workflow opts into that boundary deliberately and verifies it again immediately before publication.

## Future Developer ID channel

When the paid Developer ID channel is enabled, the protected `release` GitHub environment will supply these secrets:

- `MACOS_CERTIFICATE_P12` — base64-encoded Developer ID Application certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD` — password for the PKCS#12 archive.
- `RELEASE_KEYCHAIN_PASSWORD` — ephemeral CI keychain password.
- `APPLE_API_KEY_P8` — base64-encoded App Store Connect API private key.
- `APPLE_API_KEY_ID` — App Store Connect key identifier.
- `APPLE_API_ISSUER_ID` — App Store Connect issuer identifier.

The packaging script already supports hardened-runtime signing, notarization, stapling, and Gatekeeper assessment. The current ad-hoc workflow does not request or use these secrets.

## Prepare without publishing

Commit the exact candidate first. Release packaging requires a clean worktree so
the generated metadata cannot claim a source commit that differs from the bytes
being packaged. Then run the ordinary gates and a non-distributable proof:

```bash
swift test
python3 scripts/verify_public_release.py
python3 scripts/test_public_release_verifier.py
python3 scripts/test_release_metadata.py
python3 scripts/test_package_release.py
proof_dir=$(mktemp -d)
HYPHA_RELEASE_MODE=adhoc \
HYPHA_ALLOW_NON_DISTRIBUTABLE_RELEASE=1 \
HYPHA_RELEASE_ALLOW_UNTAGGED=1 \
scripts/package-release.sh v0.2.0 "$proof_dir"
```

This does not create a tag or GitHub release. It does create a checksum-bound
local artifact whose source commit is the clean candidate HEAD.

## Publish

Publishing is intentionally tag-only. Once the version and encryption gate are approved, push the exact semantic-version tag. `.github/workflows/release.yml` builds, ad-hoc signs, verifies, packages, and creates the GitHub release with `release/ADHOC_RELEASE_NOTICE.md` as the mandatory warning and installation guide.

Published assets:

- `Hypha-vMAJOR.MINOR.PATCH-macos-arm64.zip`
- `Hypha-vMAJOR.MINOR.PATCH-release.json`
- `SHA256SUMS`

No release should be created manually outside the reviewed tag workflow.

## Verify a download

```bash
shasum -a 256 -c SHA256SUMS
codesign --verify --deep --strict --verbose=2 Hypha.app
spctl --assess --type execute --verbose=4 Hypha.app
```

The JSON metadata binds the archive checksum to its source commit, bundle identity, executable, minimum macOS version, signing/notarization status, and encryption-gate evidence.
