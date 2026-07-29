# Asset provenance

## `Resources/ZenithOSIcon.icns`

- SHA-256: `59f627b5e8996335d8be81b5fcc6092088b9c1915ed9b2cd82e49e0b9a348a78`
- Canonical editable source: `Resources/ZenithOSIcon.svg` (SHA-256 `b553714e443d6ab856295676f92ee363d9b9ccfb8a0a6711e73ce9780fe2ac78`).
- Reproducible renderer: `scripts/generate_zenith_icon.py`, which encodes the same vector geometry and rasterizes each required macOS icon size.
- Creation record: restored from the project-owned ZenithOS icon at commit `bc78d05` so Hypha uses the established Zenith product mark rather than the short-lived branching-hypha variant.
- License: AGPL-3.0-or-later with the repository.

Regenerate the `.icns` from the repository root with `python3 scripts/generate_zenith_icon.py`. The generator creates all required macOS iconset sizes and packages them with Apple's `iconutil`.

## `docs/evidence/issue-2/native-shell.png`

- SHA-256: `7e88b4366551f923c2e12b33eea737cef01558899484060b37a5ce2a37a0b84b`
- Synthetic project screenshot.
- Generation and privacy review: `docs/evidence/issue-2/verification.md`.
- Contains no live account, room, message, token, ciphertext, or recovery material.
- Distributed under AGPL-3.0-or-later with the repository.
