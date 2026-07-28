# Matrix SDK compatibility checkpoint

## Host-compatible dependency

- `matrix-org/matrix-rust-components-swift`
- Manifest pin: `26.05.13`
- Resolved version: `26.5.13`
- Resolved revision: `02133b466cddbd5c911881acbb29cf14e5563344`
- Local validation host: macOS `26.4.1` (`25E253`)

## Selection evidence

The newer `26.06.06` artifact contains macOS archive members marked for macOS 26.5, which is newer than the current validation host. A disposable worktree tested `26.05.13` instead.

`26.05.13` results:

- Release build succeeds after using that release's `SqliteStoreBuilder.passphrase(...)` API with the existing random 32-byte Keychain-backed store secret encoded as Base64.
- Full suite passes: 28 tests, 0 failures, 1 opt-in live test skipped in the normal suite.
- Release app packaging, dependency audit, signing, and launch smoke pass.
- Archive-member linker warnings report macOS 26.4 rather than 26.5, so this exact artifact is usable for validation on the current macOS 26.4.1 host.
- Final executable and SDK both report minimum macOS 26.4.

## RED/GREEN

RED:

- `26.05.13` initially failed to compile because its `SqliteStoreBuilder` exposes `passphrase(...)`, not the newer `key(...)` API.
- CI/source contracts initially failed because they still required the `26.6.6` development pin and newer builder call.

GREEN:

- The encrypted store derives its passphrase from the existing random 32-byte store key held in macOS Keychain.
- Exact pin and CI contract now require `26.5.13`.
- Focused compatibility and service tests pass.
- Full suite, release app package, dependency audit, signing, and launch pass.

## Remaining shipping hold

This change establishes a working host-compatible build for macOS 26.4.1. It does **not** establish every-Mac compatibility: the app now declares macOS 26.4 to match the published SDK archive members.

Do not make broad older-Mac shipping or notarization claims until an exact official artifact is published with archive members built for the package minimum and a clean minimum-target consumer produces zero deployment-target mismatch warnings.
