# Contributing to Hypha

Thank you for helping improve Hypha.

## Before opening a pull request

1. Search the issue tracker for an existing issue or discussion of the change.
2. For security-sensitive behavior, follow [`SECURITY.md`](SECURITY.md) instead of opening a public issue.
3. Keep each pull request focused on one reviewed issue boundary.
4. Do not include credentials, account identifiers, room IDs, private messages, recovery material, or machine-specific paths in code, fixtures, logs, screenshots, commits, or PR descriptions.

## Development requirements

Hypha currently targets macOS 26.4 and uses Xcode 26.4. Clone with Git LFS enabled so the checksummed Matrix SDK artifact is available.

```bash
git lfs pull
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
HYPHA_SIGNING_MODE=adhoc ./build-app.sh
codesign --verify --deep --strict --verbose=2 Hypha.app
```

Live Matrix tests are opt-in and require disposable test accounts supplied through their documented environment variables. Never use production credentials in public CI or bug reports.

## Pull-request expectations

- Explain the user-visible boundary, security implications, and non-goals.
- Add RED/GREEN regression evidence for behavior changes.
- Preserve Matrix Rust SDK ownership of networking, E2EE, crypto storage, trust, and recovery authority.
- Never add plaintext chat fallback or synthetic authority.
- Keep passwords, access tokens, invite tokens, recovery keys, and session material out of logs and diagnostics.
- Require all local and hosted checks to pass before merge. Infrastructure failures are not green checks.

## Licensing contributions

Unless stated otherwise in a file, contributions submitted to this repository are licensed under GNU AGPL v3 or later, matching the repository license. Third-party code and assets must retain their original compatible license and attribution in `THIRD_PARTY_NOTICES.md` and `LICENSES/`.
