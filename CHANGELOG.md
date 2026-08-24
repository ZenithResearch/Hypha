# Changelog

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added

- Added broker-backed, short-lived homeserver administration sessions — keeps Synapse service authority and operator secrets out of the native client while preserving explicit typed administration actions.

### Changed

- Tightened broker response validation for Matrix user and room identifiers — malformed empty or control-character-bearing IDs now revoke local administration authority and fail closed.
- Prepared the Apple clients and release notice as version 0.2.0 (build 2).
- Made release packaging reject modified or untracked source trees so generated metadata always names the exact bytes that were built.
