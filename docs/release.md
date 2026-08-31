# Release process

Hypha publishes macOS downloads only from semantic-version tags after the production encryption gate has passed. Public tag releases are Developer ID signed, notarized by Apple, stapled, and assessed by Gatekeeper. Ad-hoc packaging remains available only as a local, explicitly non-distributable proof.

## Release boundary

A distributable release must satisfy all of the following:

1. The tag uses `vMAJOR.MINOR.PATCH` and points at the workflow commit.
2. The tag version equals `CFBundleShortVersionString` in `Resources/Info.plist`.
3. `release/encryption-gate.json` records a passed live two-account encrypted send, restore, synchronization, and decryption proof, its commit is an ancestor of the tagged commit, and no packaged runtime input has changed since that proof.
4. The complete Swift test suite and public-release policy checks pass on the tagged commit.
5. The app is signed with the single Developer ID Application identity imported into the ephemeral release keychain, with hardened runtime and a timestamp.
6. Apple accepts the notarization submission; the workflow staples and validates the ticket and Gatekeeper accepts the app.
7. Release metadata reports `mode: developer-id`, `notarized: true`, and `distributable: true`.
8. GitHub provides source archives for the exact release tag.
9. The archive, release metadata, and `SHA256SUMS` verify before upload.
10. `HYPHA_DEFAULT_HOMESERVER` is supplied by the protected release environment and embedded as the public first-run HTTPS endpoint.

Ad-hoc packages are explicitly marked non-distributable and cannot claim notarization. The tag workflow has no non-distributable escape hatch: missing or invalid Apple credentials stop publication.

## Protected release environment

The protected `release` GitHub environment allows only `v*` tags, requires an operator review, and must supply these secrets:

- `MACOS_CERTIFICATE_P12` — base64-encoded Developer ID Application certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD` — password for the PKCS#12 archive.
- `RELEASE_KEYCHAIN_PASSWORD` — ephemeral CI keychain password.
- `APPLE_API_KEY_P8` — base64-encoded App Store Connect API private key.
- `APPLE_API_KEY_ID` — App Store Connect key identifier.
- `APPLE_API_ISSUER_ID` — App Store Connect issuer identifier.

It must also define the non-secret environment variable
`HYPHA_DEFAULT_HOMESERVER` as the intended public HTTPS Matrix endpoint. The
release job fails if it is absent; the endpoint is not an authentication secret.

No release secret is optional. The workflow imports the certificate into an ephemeral keychain, writes the notarization key under `RUNNER_TEMP`, and removes both after the job.

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
HYPHA_DEFAULT_HOMESERVER=https://matrix.example.org \
scripts/package-release.sh v0.2.0 "$proof_dir"
```

This does not create a tag or GitHub release. It does create a checksum-bound
local artifact whose source commit is the clean candidate HEAD.

## Publish

Publishing is intentionally tag-only. Once the version, encryption gate, and Apple credentials are approved, push the exact semantic-version tag. `.github/workflows/release.yml` builds, Developer ID signs, notarizes, staples, verifies, packages, and creates the GitHub release with `release/RELEASE_NOTES.md`.

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

The JSON metadata binds the archive checksum to its source commit, bundle identity, executable, minimum macOS version, signing/notarization status, and encryption-gate evidence. A public tag release is valid only when its signing block is `{"mode":"developer-id","notarized":true,"distributable":true}`.

The application release workflow checks out without Git LFS and runs `scripts/hydrate-matrix-sdk.sh` before any audit or build. That script accepts only the exact Matrix SDK source-release artifact and SHA-256 recorded in `Vendor/MatrixRustSDK/PROVENANCE.md`; unavailable or mismatched bytes stop the release.
