## Hypha for macOS

This Hypha build is signed with Zenith Research's Apple Developer ID and
notarized by Apple. The release workflow also staples the notarization ticket
and verifies the final app with Gatekeeper before publishing it.

Requirements:

- Apple silicon Mac (`arm64`)
- macOS 26.4 or later

### Install

1. Download the macOS archive, release metadata, and `SHA256SUMS`.
2. Verify both published files:

   ```bash
   shasum -a 256 -c SHA256SUMS
   ```

3. Unzip the archive and move `Hypha.app` to Applications.
4. Open Hypha normally. Do not bypass a Gatekeeper failure.

The machine-readable release metadata binds the archive checksum to the exact
source commit, bundle identity, architecture, signing mode, notarization state,
and production encryption-gate evidence.

### Source code

GitHub provides source snapshots for the exact release tag. Those automatic
snapshots may contain Git LFS pointers rather than the large Matrix SDK
artifact. For a buildable checkout, clone the tag and fetch LFS objects:

```bash
git clone --branch vMAJOR.MINOR.PATCH --depth 1 https://github.com/ZenithResearch/Hypha.git
cd Hypha
git lfs install --local
git lfs pull
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

### Encryption gate

Before release, a production two-account test must verify encrypted send,
room-key sharing, suspended-session restoration, synchronization, and
decryption against `synapse.zenith-research.ca`. The machine-readable receipt
is committed at `release/encryption-gate.json` and summarized in the release
metadata.
