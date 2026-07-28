# Public-release audit

This document records the release gate for publishing Hypha without exposing superseded private repository history.

Audit date: 2026-07-28.

## Completed checks

### Git and current tree

- Fetched every visible remote branch, tag, and pull-request head: 26 refs covering 88 commits.
- Scanned all reachable refs with Gitleaks using `--all`: zero detected secret findings.
- Verified the current text tree contains no contributor-machine absolute paths.
- Sanitized current Matrix SDK provenance while retaining reproducible build inputs and exact source/artifact checksums.
- Added a fail-closed `scripts/verify_public_release.py` gate for canonical license hashes, normalized dependency expressions, immutable source links, every workflow/action pin, least privilege, provenance paths, reviewed binary checksums, generated attribution integrity, and app packaging.
- Added behavioral mutation tests proving the verifier rejects fake license text, mutable Actions, job-level write permissions, proprietary dependency-license substitution, a redirected security endpoint, an additional unsafe workflow, and UTF-16 scanner bypass input.

### GitHub-native surfaces

- Scanned the title/body and available comments/reviews for all 25 issues and pull requests: no email, private-path, private-key, GitHub-token, AWS-key, bearer-token, or Matrix access-token pattern hits.
- Inspected 47 Actions runs. Logs were available for 44; their absolute paths were standard GitHub-hosted runner paths, with no unexpected contributor-machine path or credential-pattern hit.
- Three Actions runs ended before runner allocation and therefore produced no job logs to inspect.
- No Actions artifacts, Actions caches, environments, deployments, forks, Pages site, or wiki repository were present.
- Repository-default workflow permissions are now `read`; workflows cannot approve pull requests.
- The CI workflow declares `contents: read`, does not use `pull_request_target`, pins checkout to an immutable commit, and runs checksum-pinned Gitleaks 8.30.1 against both committed history and the candidate tree on every push and pull request.

### Releases and third-party materials

- Inspected eight historical Matrix SDK prereleases containing sixteen assets, then deleted all eight obsolete prereleases and their tags before publication.
- Downloaded and archive-scanned every release asset with Gitleaks: zero detected secret findings.
- Historical release provenance files contain no personal email or contributor-machine absolute path.
- The current vendored SDK source commit and checksum are recorded in `THIRD_PARTY_NOTICES.md`.
- Generated the exact 507-package notice set emitted by cargo-about 0.9.1 from the locked `matrix-sdk-ffi` manifest for `aarch64-apple-darwin`, with raw Cargo metadata, normalized/validated SPDX expressions, package metadata attribution, and immutable corresponding-source links. The checked-in machine-readable inventory is checksum-pinned and must match the human-readable table and cargo-about attribution package set exactly.
- Generated `THIRD_PARTY_LICENSES.html` with cargo-about 0.9.1 from exact dependency source license files, preserving their package-specific copyright and license text, and pinned its checksum.
- Included canonical texts for every license and exception identifier represented by that inventory.
- Updated app packaging to carry AGPL, complete notices, generated package-specific attribution, canonical license texts, and a source/commit receipt; the build fails if packaged copies differ.
- The checked-in screenshot is documented as a synthetic project asset without account, token, room, message, ciphertext, or recovery material.

## Clean-history publication strategy

The private repository history contains:

- three personal-style commit-author or committer email addresses;
- one historical commit whose Matrix SDK provenance contains a contributor username and machine-specific local build path.

A new tip commit cannot erase those records. Hypha is therefore published from a new clean root containing only the reviewed integrated tree. The existing repository, its pull-request refs, and its GitHub-native history remain private at `ZenithResearch/Hypha-private-archive`. No historical author email, contributor-machine path, old pull-request ref, release, or tag is copied to the public repository.

The new `ZenithResearch/Hypha` repository was created empty. Before the clean-root push it had zero releases, tags, Actions runs, and issues. No package was published, transferred, or associated during bootstrap. The unavailable organization-wide package listing is not treated as evidence of absence and is not copied into this repository boundary.

## Publication transition gate

- Push only the reviewed clean root while Actions remain disabled.
- Verify the new repository still has no copied releases, tags, issues, pull requests, Actions history, or private refs.
- Change visibility only after that verification passes.
- Immediately enable private vulnerability reporting and default-branch rules; revert to private if the security transition cannot be completed.

## Required post-publication verification

- As part of the visibility transition, enable and verify GitHub private vulnerability reporting before release announcement or continued public development. If enablement fails, revert visibility to private.
- Configure and verify default-branch protection/rules.
- Verify GitHub recognizes AGPL-3.0-or-later and renders the public README/security guidance.
- Verify unauthenticated clone and Git LFS retrieval.
- Rerun exact-head CI and confirm jobs execute rather than failing before runner allocation.
- Recheck releases, packages, Pages, environments, deployments, artifacts, caches, forks, and wiki state from the public boundary.
