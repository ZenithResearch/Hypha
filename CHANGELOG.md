# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added

- Added broker-backed, short-lived homeserver administration sessions — keeps Synapse service authority and operator secrets out of the native client while preserving explicit typed administration actions.

### Changed

- Made canonical builds hydrate the exact reviewed Matrix SDK from its source-commit release with checksum verification — CI, releases, and in-app updates no longer fail when Git LFS bandwidth is unavailable.
- Tightened broker response validation for Matrix user and room identifiers — malformed empty or control-character-bearing IDs now revoke local administration authority and fail closed.
- Prepared the Apple clients and release notice as version 0.2.0 (build 2).
- Made release packaging reject modified or untracked source trees so generated metadata always names the exact bytes that were built.
- Replaced the public ad-hoc tag channel with a protected, fail-closed Developer ID signing and Apple notarization workflow; local ad-hoc packages remain non-distributable proofs only.

### Fixed

- Prefer the synchronized `m.room.name` state when rebuilding room summaries — room names now survive refreshes, relaunches, and encrypted session restoration instead of falling back to a computed label, alias, or room ID.
