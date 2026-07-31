# I01: pin the MatrixRTC proposal-snapshot profile and source gates

## Owning repo

`ZenithResearch/Hypha`

## Objective

Freeze the exact open-MSC profile, stable/unstable identifiers, pinned/current SDK capability gap, sanitized production-unsupported evidence, and deterministic source-integrity gates without claiming a native session.

## Dependencies

- Parent initiative: https://github.com/ZenithResearch/Hypha/issues/6
- `origin/main@a6f425b91946b3177410abcadc2155bbc58feff7`

## Complexity

- Total: 3
- Intrinsic: 3
- Existing: 1
- Remaining: 2
- Angles: proposal provenance 2; identifier contract 2; SDK gap 2; static integrity 1

## PR boundary

One docs/manifest/static-verifier PR. No app UI, RTC session, transport, crypto, or production mutation.

## Commit specs

### Commit 1 — `docs(matrixrtc): pin source-grounded contract snapshot`

- Paths: `docs/matrixrtc/**`, `docs/issues/matrixrtc-step1/**`.
- Add a machine-readable profile manifest, deterministic canonical manifest fingerprint, and human-readable qualification contract.
- Pin MSC4143, MSC4140, MSC4195, MSC4196, MSC4075, MSC4310, MSC4519, mandatory MSC4354 Sticky Events, and mandatory MSC4518 Registries heads, source paths, SHA-256 digests, exhaustive stable/unstable event/capability/API identifiers, state-key rules, required capabilities, and explicit exclusions.
- Record a pinned-artifact/current-upstream/required-profile SDK capability matrix plus sanitized current production evidence.
- Acceptance evidence: manifest parses; every exact pin matches the reviewed source packet; no release-style profile name.
- Forbidden scope: no Swift app behavior, network client, token, call UI, media, sender key, or LiveKit implementation.

### Additive repair commit — `fix(matrixrtc): complete mandatory profile dependencies`

- Paths: `docs/matrixrtc/**`, `docs/issues/matrixrtc-step1/**`.
- Preserve Commit 1 and add exact MSC4354 and MSC4518 pins because the selected MSC4143 and MSC4519 snapshots normatively depend on them.
- Add the MSC4354 sticky-event identifier family and ephemeral-map requirements, every MSC4140 unstable route/feature/capability/unsigned identifier, and MSC4518 registry semantics.
- Expand the pinned/current/required SDK capability matrix with exact source locators and source-file digests; fallback-derived `isLivekitRtcSupported()` remains explicitly insufficient.
- Recompute the canonical profile fingerprint and update all profile-count/source-evidence references.
- Acceptance evidence: all nine exact source bytes independently hash to the manifest digests; canonical fingerprint recomputes; no runtime/SDK/UniFFI implementation is added.
- Repair rationale: CTO exact-line review found that Commit 1 omitted mandatory transitive dependencies and therefore could not qualify the selected snapshot.

### Commit 2 — `test(matrixrtc): enforce profile source integrity`

- Paths: `scripts/verify_matrixrtc_contract.py`, `scripts/test_matrixrtc_contract_verifier.py`, `.github/workflows/ci.yml`, and I01 status rows under `docs/issues/matrixrtc-step1/**`.
- Add deterministic no-network manifest/source/static checks and mutation tests.
- Hook the verifier into existing CI.
- Acceptance evidence: valid tree passes; missing proposal, digest drift, mixed identifiers, legacy MSC3401 membership, MSC4515 widget-only promotion, fallback qualification, and fictional profile names fail.
- Forbidden scope: do not scan or rewrite generated vendor code as if the pinned artifact already implements the selected profile.

## Acceptance

- [ ] All nine proposal heads, paths, statuses, content digests, and canonical manifest fingerprint are exact.
- [ ] Stable/unstable event, capability, application, encryption, and API identifiers are complete and unambiguous.
- [ ] MSC4354 ephemeral-map and MSC4518 registry requirements are explicit and mechanically checked.
- [ ] Pinned and current SDK gaps are separately stated.
- [ ] Production evidence is sanitized and typed unsupported.
- [ ] CI runs deterministic no-network source gates.
- [ ] The fictional July 2026 release-style profile label is absent from current governing artifacts.

## Verification

- `python3 scripts/verify_matrixrtc_contract.py`
- `python3 scripts/test_matrixrtc_contract_verifier.py`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build`
- `git diff --check`

## Non-claims

No selected-profile availability, SDK join capability, transport authorization, sender-key support, media, UI, or production readiness.

## Stop conditions

Stop if any upstream pin/digest cannot be reproduced, stable/unstable identifiers conflict, current SDK source has materially moved from the reconciled head, or verification requires network/credentials in CI.

## Allowed paths

`docs/matrixrtc/**`, `docs/issues/matrixrtc-step1/**`, `scripts/verify_matrixrtc_contract.py`, `scripts/test_matrixrtc_contract_verifier.py`, `.github/workflows/ci.yml`.

## Stacked PR base

Branch `feat/matrixrtc-contract-profile`; base `main` at the frozen base SHA.
