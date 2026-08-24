## Important: temporary ad-hoc macOS release

This Hypha build is **ad-hoc signed and not notarized by Apple**. It is being distributed this way temporarily to avoid the Apple Developer Program fee. The SHA-256 checksum verifies the downloaded bytes, but this build does not provide Apple-verified publisher identity or notarization.

Requirements:

- Apple silicon Mac (`arm64`)
- macOS 26.4 or later

### Verify the download

Download these three assets into the same directory:

- `Hypha-v0.2.0-macos-arm64.zip`
- `Hypha-v0.2.0-release.json`
- `SHA256SUMS`

Then run:

```bash
shasum -a 256 -c SHA256SUMS
```

Both files must report `OK`. Do not open the app if verification fails.

### Open the app

1. Unzip `Hypha-v0.2.0-macos-arm64.zip`.
2. Move `Hypha.app` to Applications if desired.
3. Try to open Hypha once. macOS will warn or block it because it is not notarized.
4. Open **System Settings → Privacy & Security**.
5. Find the message that Hypha was blocked and choose **Open Anyway**.
6. Authenticate with your Mac password or Touch ID, then confirm **Open**.

Only bypass Gatekeeper if you downloaded Hypha from the official `ZenithResearch/Hypha` GitHub release and its checksum passed.

### Source code

GitHub provides **Source code (zip)** and **Source code (tar.gz)** snapshots for this exact `v0.2.0` tag on the release page. Those automatic snapshots may contain Git LFS pointer files rather than the large Matrix SDK artifact. For a buildable source checkout, clone the tag and fetch LFS objects:

```bash
git clone --branch v0.2.0 --depth 1 https://github.com/ZenithResearch/Hypha.git
cd Hypha
git lfs install --local
git lfs pull
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
HYPHA_SIGNING_MODE=adhoc ./build-app.sh
```

The source build is also ad-hoc signed unless you provide your own Apple signing identity.

### Encryption gate

Before this release candidate was prepared, a production two-account test verified encrypted send, room-key sharing, suspended-session restoration, synchronization, and decryption against `synapse.zenith-research.ca`. The machine-readable receipt is included in `release/encryption-gate.json` and summarized in the release metadata.
