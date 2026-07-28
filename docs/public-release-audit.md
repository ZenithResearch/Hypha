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

## Completed publication transition

- Published clean root `ed94fdf5ae054702e4201a490ca9e62ccf6cccf8`, whose parent count is zero and whose author uses a GitHub noreply address.
- Verified that the only branch initially published was `main`; no historical branch, pull-request ref, release, issue, Actions run, or old tag was copied.
- Kept `ZenithResearch/Hypha-private-archive` private and set it read-only with GitHub's archive control.
- Verified public README and AGPL detection through unauthenticated GitHub endpoints.
- Verified an unauthenticated HTTPS clone and Git LFS retrieval of the SDK artifact at SHA-256 `ca8796d0f065ade3787de2f18693afd940914ce2e35f807ccf479d2f14c5c565`.
- Enabled and verified GitHub private vulnerability reporting.
- Enabled secret scanning, secret-scanning push protection, and Dependabot security updates.
- Applied active `Protect main` ruleset `19932949`: no deletion or force push, linear history, pull-request changes, resolved review threads, and required `macos` status checks.
- Kept Actions token defaults at `contents: read`; workflows cannot approve pull requests.
- Created lightweight tag `public-ci-ed94fdf` only to trigger verification on the root commit after Actions was enabled.
- Verified the standard `macos-26` job executed every workflow step successfully on that exact root: [run 30408519317](https://github.com/ZenithResearch/Hypha/actions/runs/30408519317).
- Rechecked the public boundary after publication: no releases, no copied issues or pull requests, and no transferred package publication or association.
