# Asset provenance

## `Resources/ZenithOSIcon.icns`

- SHA-256: `61ad8afdb2674ba035cdfbab4a850e327a872fbc1ba940c76469d0349d3e5342`
- Canonical editable source and reproducible renderer: `scripts/generate_hypha_icon.py`, which encodes the vector geometry and rasterizes each macOS icon size.
- Generated editable SVG companion: `Resources/HyphaIconSource.svg` (SHA-256 `3ed8f9878335d2cf9199577b0ec4dbf981a35d8195f8999b7fe16db6cfcfad92`). The generator writes this matching representation for reuse and inspection; the `.icns` renderer does not read it as an input.
- Creation record: designed and generated in-repository for Hypha as an original branching-hypha mark; it does not incorporate the superseded icon or third-party artwork.
- License: AGPL-3.0-or-later with the repository.

Regenerate both outputs from the repository root with `python3 scripts/generate_hypha_icon.py`. The generator creates the SVG companion, all required macOS iconset sizes, and the `.icns` with Apple's `iconutil`.

## `docs/evidence/issue-2/native-shell.png`

- SHA-256: `7e88b4366551f923c2e12b33eea737cef01558899484060b37a5ce2a37a0b84b`
- Synthetic project screenshot.
- Generation and privacy review: `docs/evidence/issue-2/verification.md`.
- Contains no live account, room, message, token, ciphertext, or recovery material.
- Distributed under AGPL-3.0-or-later with the repository.
