# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added

- Added an authoritative, compatibility-mirrored repository collection with a 42-attachment limit and attachment-scoped local bindings — rooms can compose many repositories without old single-repository clients erasing the new state or leaking device-local paths.
- Added global device-only Keychain storage for the verified GitHub credential plus remote-first immutable output materialization and same-commit cache fallback — one connection can safely serve every room without placing credentials in Matrix, caches, or logs.
- Added path-preserving, repository-grouped Assets with byte/container classification and centralized viewer routing — every supported output opens through the correct bounded native viewer while identical paths in different repositories remain distinct.
- Added a sandboxed room Canvas host, v1 capability bridge, TypeScript/ESM/Web Components and Rust/WASM SDKs, local validation preview, sanitized Hermes handoff, and immutable shared template references — room layouts can be authored without giving templates or agents credentials, filesystem authority, builds, Matrix mutation, or general network access.
- Added broker-backed, short-lived homeserver administration sessions — keeps Synapse service authority and operator secrets out of the native client while preserving explicit typed administration actions.
- Added a first-class Tailscale homeserver connection card with native app launch, official install fallback, and actionable tailnet errors — makes private self-hosted deployments understandable and connectable without exposing Tailscale credentials to Hypha.

### Changed

- Moved the global GitHub connection CTA and live account/repository status into the room repository sheet — users can connect once, see whether discovery is ready, refresh it, or disconnect without detouring through Settings.
- Made `out.json` version 2 support explicit `asset_discovery.mode = recognized` while retaining declared-only omission semantics — existing writers do not expose undeclared files after a client update, while opted-in repositories project every validated output into Assets.
- Moved builds behind attachment-scoped **Rebuild** with exact confirmation, cancellation, process-group termination, and output rollback — opening, attaching, and refreshing never execute repository code or destroy the last usable output.

- Read the first-run Matrix homeserver from `HYPHA_DEFAULT_HOMESERVER` and embed that deployment value in packaged apps — Hypha can target different homeservers without shipping a server address in application source.
- Made canonical builds hydrate the exact reviewed Matrix SDK from its source-commit release with checksum verification — CI, releases, and in-app updates no longer fail when Git LFS bandwidth is unavailable.
- Tightened broker response validation for Matrix user and room identifiers — malformed empty or control-character-bearing IDs now revoke local administration authority and fail closed.
- Prepared the Apple clients and release notice as version 0.2.0 (build 2).
- Made release packaging reject modified or untracked source trees so generated metadata always names the exact bytes that were built.
- Replaced the public ad-hoc tag channel with a protected, fail-closed Developer ID signing and Apple notarization workflow; local ad-hoc packages remain non-distributable proofs only.

### Fixed

- Prefer the synchronized `m.room.name` state when rebuilding room summaries — room names now survive refreshes, relaunches, and encrypted session restoration instead of falling back to a computed label, alias, or room ID.
