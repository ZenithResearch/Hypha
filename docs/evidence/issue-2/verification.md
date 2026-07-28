# Native macOS chat shell verification

This checkpoint verifies the native shell source and test contracts without a Matrix SDK dependency.

## RED/GREEN

- Commit 1 RED: seven coordinator tests failed because Matrix service/models/coordinator did not exist.
- Commit 1 GREEN: seven focused coordinator tests pass.
- Commit 2 RED: the native shell source contract reported eleven missing safe-state/accessibility markers.
- Commit 2 GREEN: the shell contract and full suite pass.
- Visual follow-up RED: source contract reported the missing synthetic disclosure, wider sidebar, and dynamic detail-title markers.
- Visual follow-up GREEN: those markers pass and the synthetic screenshot confirms the room title is no longer truncated.

## Commands and results

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`: 9 tests, 0 failures.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`: passed.
- `./build-app.sh`: release build, pre-sign dependency audit, ad-hoc signing, and deep strict verification passed.
- Release app: arm64, macOS minimum 26.4, SDK 26.4.
- Packaged shell size: approximately 516 KB.
- Matrix dynamic-library load commands: 0.
- Launch smoke: process remained alive until intentionally terminated.
- `git diff --check`: required before push.

## Visual evidence

`native-shell.png` is a synthetic public fixture launched with `--synthetic-chat`. It contains no account, token, room ID, private message, ciphertext, or recovery material.

Observed:

- full `Encrypted room` title in the wider sidebar;
- explicit `Synthetic preview • no live Matrix connection` disclosure;
- native macOS split-view layout with no clipping or overflow;
- clear choose-room empty selection state.

The earlier synthetic thread view also showed an explicit orange `Waiting for room keys` event and a disabled empty composer. Neither image proves live Matrix, E2EE, or SDK integration.

## Claim boundary

This PR proves only the native macOS shell, SDK-neutral service/state contract, safe UI states, packaging, signing, and launchability. It does not provide live login, Matrix networking, durable sessions, crypto storage, E2EE, encrypted send/receive, verification, or recovery.
